//! Linux: Skia renders through a headless EGL (GLES) context into a
//! pbuffer and reads every frame back into memory, which the C plugin
//! copies into its `FlPixelBufferTexture`. libEGL is loaded on the first
//! attach, so a machine without it gets an error from that call rather than
//! a library that fails to load.

use std::cell::{Ref, RefCell};
use std::ffi::{c_char, c_int, c_void, CString};
use std::mem::transmute;
use std::ptr;
use std::rc::Rc;
use std::sync::{Arc, OnceLock};

use i_slint_core::api::{PhysicalSize, Window};
use i_slint_core::graphics::RequestedGraphicsAPI;
use i_slint_core::partial_renderer::DirtyRegion;
use i_slint_core::platform::PlatformError;
use i_slint_core::renderer::DrawOutcome;
use i_slint_renderer_skia::skia_safe::gpu::{self, gl};
use i_slint_renderer_skia::skia_safe::{AlphaType, Canvas, ColorType, ImageInfo};
use i_slint_renderer_skia::{SkiaSharedContext, Surface};

type EGLDisplay = *mut c_void;
type EGLConfig = *mut c_void;
type EGLContext = *mut c_void;
type EGLSurface = *mut c_void;
type EGLint = i32;
type EGLBoolean = u32;
type EGLenum = u32;

const EGL_TRUE: EGLBoolean = 1;
const EGL_NONE: EGLint = 0x3038;
const EGL_ALPHA_SIZE: EGLint = 0x3021;
const EGL_BLUE_SIZE: EGLint = 0x3022;
const EGL_GREEN_SIZE: EGLint = 0x3023;
const EGL_RED_SIZE: EGLint = 0x3024;
const EGL_STENCIL_SIZE: EGLint = 0x3026;
const EGL_SURFACE_TYPE: EGLint = 0x3033;
const EGL_PBUFFER_BIT: EGLint = 0x0001;
const EGL_RENDERABLE_TYPE: EGLint = 0x3040;
const EGL_OPENGL_ES2_BIT: EGLint = 0x0004;
const EGL_WIDTH: EGLint = 0x3057;
const EGL_HEIGHT: EGLint = 0x3056;
const EGL_DRAW: EGLint = 0x3059;
const EGL_READ: EGLint = 0x305A;
const EGL_CONTEXT_CLIENT_VERSION: EGLint = 0x3098;
const EGL_OPENGL_ES_API: EGLenum = 0x30A0;
const EGL_BAD_ACCESS: EGLint = 0x3002;
const EGL_PLATFORM_SURFACELESS_MESA: EGLenum = 0x31DD;

const RTLD_NOW: c_int = 2;

extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}

/// Declares [`Egl`], a table of libEGL functions resolved with `dlsym`.
macro_rules! egl_functions {
    ($($name:ident($($arg:ty),*) -> $ret:ty;)*) => {
        #[allow(non_snake_case)]
        struct Egl {
            $($name: unsafe extern "C" fn($($arg),*) -> $ret,)*
        }

        impl Egl {
            fn load() -> Result<Self, String> {
                // SAFETY: plain dlopen/dlsym; each symbol is cast to its EGL
                // 1.4 signature, and the library stays loaded for the process.
                unsafe {
                    let lib = dlopen(c"libEGL.so.1".as_ptr(), RTLD_NOW);
                    if lib.is_null() {
                        return Err("could not load libEGL.so.1 (install the EGL runtime, \
                                    e.g. the libegl1 package)"
                            .into());
                    }
                    Ok(Self {
                        $($name: {
                            let symbol = dlsym(lib, concat!(stringify!($name), "\0").as_ptr().cast());
                            if symbol.is_null() {
                                return Err(concat!("libEGL.so.1 lacks ", stringify!($name)).into());
                            }
                            transmute::<*mut c_void, unsafe extern "C" fn($($arg),*) -> $ret>(symbol)
                        },)*
                    })
                }
            }
        }
    };
}

egl_functions! {
    eglGetProcAddress(*const c_char) -> *const c_void;
    eglGetDisplay(*mut c_void) -> EGLDisplay;
    eglInitialize(EGLDisplay, *mut EGLint, *mut EGLint) -> EGLBoolean;
    eglBindAPI(EGLenum) -> EGLBoolean;
    eglChooseConfig(EGLDisplay, *const EGLint, *mut EGLConfig, EGLint, *mut EGLint) -> EGLBoolean;
    eglGetConfigAttrib(EGLDisplay, EGLConfig, EGLint, *mut EGLint) -> EGLBoolean;
    eglCreatePbufferSurface(EGLDisplay, EGLConfig, *const EGLint) -> EGLSurface;
    eglCreateContext(EGLDisplay, EGLConfig, EGLContext, *const EGLint) -> EGLContext;
    eglMakeCurrent(EGLDisplay, EGLSurface, EGLSurface, EGLContext) -> EGLBoolean;
    eglGetCurrentDisplay() -> EGLDisplay;
    eglGetCurrentSurface(EGLint) -> EGLSurface;
    eglGetCurrentContext() -> EGLContext;
    eglDestroySurface(EGLDisplay, EGLSurface) -> EGLBoolean;
    eglDestroyContext(EGLDisplay, EGLContext) -> EGLBoolean;
    eglGetError() -> EGLint;
}

fn egl() -> Result<&'static Egl, String> {
    static EGL: OnceLock<Result<Egl, String>> = OnceLock::new();
    EGL.get_or_init(Egl::load).as_ref().map_err(Clone::clone)
}

fn egl_error(egl: &Egl, call: &str) -> String {
    let code = unsafe { (egl.eglGetError)() };
    let hint = if code == EGL_BAD_ACCESS {
        " (this thread has a context of another API current, e.g. GDK's GLX one)"
    } else {
        ""
    };
    format!("{call} failed: EGL error {code:#x}{hint}")
}

/// Mesa's surfaceless platform needs no X11 or Wayland connection (CI, a
/// headless box, a GPU render node); other drivers get the default display.
fn display(egl: &Egl) -> Result<EGLDisplay, String> {
    type GetPlatformDisplay =
        unsafe extern "C" fn(EGLenum, *mut c_void, *const EGLint) -> EGLDisplay;
    unsafe {
        let get_platform_display = (egl.eglGetProcAddress)(c"eglGetPlatformDisplayEXT".as_ptr());
        if !get_platform_display.is_null() {
            let get_platform_display =
                transmute::<*const c_void, GetPlatformDisplay>(get_platform_display);
            let display =
                get_platform_display(EGL_PLATFORM_SURFACELESS_MESA, ptr::null_mut(), ptr::null());
            if !display.is_null()
                && (egl.eglInitialize)(display, ptr::null_mut(), ptr::null_mut()) == EGL_TRUE
            {
                return Ok(display);
            }
        }
        let display = (egl.eglGetDisplay)(ptr::null_mut());
        if display.is_null() {
            return Err(egl_error(egl, "eglGetDisplay"));
        }
        if (egl.eglInitialize)(display, ptr::null_mut(), ptr::null_mut()) != EGL_TRUE {
            return Err(egl_error(egl, "eglInitialize"));
        }
        Ok(display)
    }
}

/// A GLES context and the pbuffer it draws into. The display stays
/// initialized: other instances share it.
struct Pbuffer {
    egl: &'static Egl,
    display: EGLDisplay,
    surface: EGLSurface,
    context: EGLContext,
    stencil_bits: usize,
}

impl Pbuffer {
    fn new(size: PhysicalSize) -> Result<Self, String> {
        let egl = egl()?;
        let display = display(egl)?;
        let config_attributes = [
            EGL_SURFACE_TYPE,
            EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE,
            EGL_OPENGL_ES2_BIT,
            EGL_RED_SIZE,
            8,
            EGL_GREEN_SIZE,
            8,
            EGL_BLUE_SIZE,
            8,
            EGL_ALPHA_SIZE,
            8,
            EGL_STENCIL_SIZE,
            8,
            EGL_NONE,
        ];
        let surface_attributes = [
            EGL_WIDTH,
            size.width as EGLint,
            EGL_HEIGHT,
            size.height as EGLint,
            EGL_NONE,
        ];
        let context_attributes = [EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE];
        unsafe {
            if (egl.eglBindAPI)(EGL_OPENGL_ES_API) != EGL_TRUE {
                return Err(egl_error(egl, "eglBindAPI(GLES)"));
            }
            let mut config = ptr::null_mut();
            let mut count = 0;
            if (egl.eglChooseConfig)(
                display,
                config_attributes.as_ptr(),
                &mut config,
                1,
                &mut count,
            ) != EGL_TRUE
                || count == 0
            {
                return Err("no EGL config with an RGBA8 GLES pbuffer".into());
            }
            let mut stencil_bits = 0;
            (egl.eglGetConfigAttrib)(display, config, EGL_STENCIL_SIZE, &mut stencil_bits);
            let surface =
                (egl.eglCreatePbufferSurface)(display, config, surface_attributes.as_ptr());
            if surface.is_null() {
                return Err(egl_error(egl, "eglCreatePbufferSurface"));
            }
            let context = (egl.eglCreateContext)(
                display,
                config,
                ptr::null_mut(),
                context_attributes.as_ptr(),
            );
            if context.is_null() {
                let error = egl_error(egl, "eglCreateContext");
                (egl.eglDestroySurface)(display, surface);
                return Err(error);
            }
            Ok(Self {
                egl,
                display,
                surface,
                context,
                stencil_bits: stencil_bits.max(0) as usize,
            })
        }
    }

    /// Makes this context current until the guard drops, which restores
    /// whatever EGL context the thread had (the host's, possibly).
    fn make_current(&self) -> Result<Current<'_>, String> {
        let egl = self.egl;
        unsafe {
            let previous = (
                (egl.eglGetCurrentDisplay)(),
                (egl.eglGetCurrentSurface)(EGL_DRAW),
                (egl.eglGetCurrentSurface)(EGL_READ),
                (egl.eglGetCurrentContext)(),
            );
            if (egl.eglMakeCurrent)(self.display, self.surface, self.surface, self.context)
                != EGL_TRUE
            {
                return Err(egl_error(egl, "eglMakeCurrent"));
            }
            Ok(Current {
                pbuffer: self,
                previous,
            })
        }
    }
}

impl Drop for Pbuffer {
    fn drop(&mut self) {
        unsafe {
            (self.egl.eglDestroySurface)(self.display, self.surface);
            (self.egl.eglDestroyContext)(self.display, self.context);
        }
    }
}

struct Current<'a> {
    pbuffer: &'a Pbuffer,
    previous: (EGLDisplay, EGLSurface, EGLSurface, EGLContext),
}

impl Drop for Current<'_> {
    fn drop(&mut self) {
        let egl = self.pbuffer.egl;
        let (display, draw, read, context) = self.previous;
        unsafe {
            if display.is_null() {
                (egl.eglMakeCurrent)(
                    self.pbuffer.display,
                    ptr::null_mut(),
                    ptr::null_mut(),
                    ptr::null_mut(),
                );
            } else {
                (egl.eglMakeCurrent)(display, draw, read, context);
            }
        }
    }
}

/// The last frame, shared between the surface (writes) and the instance
/// (hands it to the plugin).
pub struct Attachment {
    frame: Rc<RefCell<Vec<u8>>>,
}

impl Attachment {
    /// RGBA8888 premultiplied, top row first; empty before the first frame.
    pub fn frame(&self) -> Ref<'_, Vec<u8>> {
        self.frame.borrow()
    }
}

pub struct PbufferSurface {
    // Dropped before the pbuffer, with its context current (see Drop).
    context: RefCell<gpu::DirectContext>,
    target: gpu::BackendRenderTarget,
    pbuffer: Pbuffer,
    size: PhysicalSize,
    frame: Rc<RefCell<Vec<u8>>>,
}

/// Creates a pbuffer of `size` and a surface rendering into it.
pub fn create(size: PhysicalSize) -> Result<(PbufferSurface, Attachment), String> {
    let pbuffer = Pbuffer::new(size)?;
    let context = {
        let _current = pbuffer.make_current()?;
        let egl = pbuffer.egl;
        let interface = gl::Interface::new_load_with(|name| {
            CString::new(name).map_or(ptr::null(), |name| unsafe {
                (egl.eglGetProcAddress)(name.as_ptr())
            })
        })
        .ok_or("Skia could not load the GLES functions through EGL")?;
        gpu::direct_contexts::make_gl(interface, None)
            .ok_or("Skia could not create a GLES context")?
    };
    let target = gpu::backend_render_targets::make_gl(
        (size.width as i32, size.height as i32),
        None,
        pbuffer.stencil_bits,
        gl::FramebufferInfo {
            fboid: 0,
            format: gl::Format::RGBA8.into(),
            ..Default::default()
        },
    );
    let frame = Rc::new(RefCell::new(Vec::new()));
    let surface = PbufferSurface {
        context: RefCell::new(context),
        target,
        pbuffer,
        size,
        frame: frame.clone(),
    };
    Ok((surface, Attachment { frame }))
}

impl Drop for PbufferSurface {
    fn drop(&mut self) {
        match self.pbuffer.make_current() {
            // Frees Skia's GL objects while their context is current.
            Ok(_current) => {
                self.context.get_mut().release_resources_and_abandon();
            }
            Err(_) => {
                self.context.get_mut().abandon();
            }
        }
    }
}

impl Surface for PbufferSurface {
    fn new(
        _: &SkiaSharedContext,
        _: Arc<dyn raw_window_handle::HasWindowHandle + Sync + Send>,
        _: Arc<dyn raw_window_handle::HasDisplayHandle + Sync + Send>,
        _: PhysicalSize,
        _: Option<RequestedGraphicsAPI>,
    ) -> Result<Self, PlatformError> {
        Err("the EGL pbuffer surface is headless, not a window".into())
    }

    fn name(&self) -> &'static str {
        "egl-pbuffer"
    }

    fn with_active_surface(&self, callback: &mut dyn FnMut()) -> Result<(), PlatformError> {
        let _current = self.pbuffer.make_current()?;
        callback();
        Ok(())
    }

    fn render(
        &self,
        _window: &Window,
        _size: PhysicalSize,
        render_callback: &dyn Fn(
            &Canvas,
            Option<&mut gpu::DirectContext>,
            u8,
        ) -> Option<DirtyRegion>,
        pre_present_callback: &RefCell<Option<Box<dyn FnMut()>>>,
    ) -> Result<DrawOutcome, PlatformError> {
        let _current = self.pbuffer.make_current()?;
        let mut context = self.context.borrow_mut();
        let mut surface = gpu::surfaces::wrap_backend_render_target(
            &mut context,
            &self.target,
            gpu::SurfaceOrigin::BottomLeft,
            ColorType::RGBA8888,
            None,
            None,
        )
        .ok_or("Skia could not wrap the EGL pbuffer")?;
        // Age 0: the renderer repaints everything (no partial rendering here).
        render_callback(surface.canvas(), Some(&mut *context), 0);
        if let Some(callback) = pre_present_callback.borrow_mut().as_mut() {
            callback();
        }
        let (width, height) = (self.size.width as usize, self.size.height as usize);
        let info = ImageInfo::new(
            (width as i32, height as i32),
            ColorType::RGBA8888,
            AlphaType::Premul,
            None,
        );
        let mut frame = self.frame.borrow_mut();
        frame.resize(width * height * 4, 0);
        // ponytail: a synchronous GPU->CPU copy per frame, and the plugin
        // copies again; a dmabuf the compositor imports would skip both.
        if !surface.read_pixels(&info, frame.as_mut_slice(), width * 4, (0, 0)) {
            frame.clear();
            return Err("reading the frame back from the GPU failed".into());
        }
        Ok(DrawOutcome::Success)
    }

    fn resize_event(&self, _size: PhysicalSize) -> Result<(), PlatformError> {
        // A new size is a new pbuffer: the plugin attaches again.
        Ok(())
    }

    fn bits_per_pixel(&self) -> Result<u8, PlatformError> {
        Ok(32)
    }
}
