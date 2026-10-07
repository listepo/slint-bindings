//! The Slint platform behind this crate: every window is a
//! [`SkiaWindowAdapter`], a `SkiaRenderer` with no surface until the host
//! attaches one. The per-platform modules build those surfaces.

use std::cell::{Cell, RefCell};
use std::rc::{Rc, Weak};

use i_slint_renderer_skia::{SkiaRenderer, SkiaSharedContext};
use slint::platform::{Renderer, WindowAdapter, WindowEvent};
use slint::{PhysicalSize, PlatformError, Window, WindowSize};

#[cfg(target_os = "android")]
pub mod android;
#[cfg(target_os = "windows")]
pub mod d3d;
#[cfg(target_os = "linux")]
pub mod gl;
#[cfg(target_vendor = "apple")]
pub mod metal;

#[cfg(target_os = "android")]
pub use android::Attachment;
#[cfg(target_os = "windows")]
pub use d3d::Attachment;
#[cfg(target_os = "linux")]
pub use gl::Attachment;
#[cfg(target_vendor = "apple")]
pub use metal::Attachment;
/// No GPU surface on other targets: nothing ever attaches.
#[cfg(not(any(
    target_vendor = "apple",
    target_os = "android",
    target_os = "linux",
    target_os = "windows"
)))]
pub struct Attachment;

thread_local! {
    // The adapter the platform created for the most recent instantiation.
    // ponytail: single-slot handoff, as in slint_interpreter.
    static NEXT_ADAPTER: RefCell<Option<Rc<SkiaWindowAdapter>>> = const { RefCell::new(None) };
}

struct SkiaPlatform {
    context: SkiaSharedContext,
}

impl slint::platform::Platform for SkiaPlatform {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, PlatformError> {
        let adapter = SkiaWindowAdapter::new(&self.context);
        NEXT_ADAPTER.with(|slot| *slot.borrow_mut() = Some(adapter.clone()));
        Ok(adapter)
    }
}

/// Installs [`SkiaPlatform`]; an `Err` from Slint means it already is.
pub fn ensure_platform() {
    let _ = slint::platform::set_platform(Box::new(SkiaPlatform {
        context: SkiaSharedContext::default(),
    }));
}

pub fn take_adapter() -> Option<Rc<SkiaWindowAdapter>> {
    NEXT_ADAPTER.with(|slot| slot.borrow_mut().take())
}

/// A window the host sizes and pulls frames from
/// ([`SkiaWindowAdapter::take_redraw`]): `MinimalSoftwareWindow`'s shape
/// with a Skia renderer.
pub struct SkiaWindowAdapter {
    window: Window,
    renderer: SkiaRenderer,
    size: Cell<PhysicalSize>,
    needs_redraw: Cell<bool>,
}

impl SkiaWindowAdapter {
    fn new(context: &SkiaSharedContext) -> Rc<Self> {
        Rc::new_cyclic(|weak: &Weak<Self>| Self {
            window: Window::new(weak.clone()),
            // No surface yet: `set_window_handle` builds Slint's own
            // (Android), `set_surface` takes ours (everywhere else). Softbuffer
            // on Apple+Windows (and OpenGL on Linux) makes `default` available
            // for `skia_windowed`; the window-handle factory is unused on
            // desktop — we attach Metal/D3D/GL via `set_surface`.
            renderer: SkiaRenderer::default(context),
            size: Cell::new(PhysicalSize::new(0, 0)),
            needs_redraw: Cell::new(true),
        })
    }

    pub fn skia(&self) -> &SkiaRenderer {
        &self.renderer
    }

    /// Whether a frame is due, clearing the flag.
    pub fn take_redraw(&self) -> bool {
        self.needs_redraw.replace(false)
    }
}

impl WindowAdapter for SkiaWindowAdapter {
    fn window(&self) -> &Window {
        &self.window
    }

    fn renderer(&self) -> &dyn Renderer {
        &self.renderer
    }

    fn size(&self) -> PhysicalSize {
        self.size.get()
    }

    fn set_size(&self, size: WindowSize) {
        let scale = self.window.scale_factor();
        self.size.set(size.to_physical(scale));
        self.window.dispatch_event(WindowEvent::Resized {
            size: size.to_logical(scale),
        });
        self.needs_redraw.set(true);
    }

    fn request_redraw(&self) {
        self.needs_redraw.set(true);
    }
}

/// Rendering into a texture the host shares with Flutter (Metal, D3D12):
/// wrap it per frame, draw, and wait for the GPU, because the plugin marks
/// the frame available as soon as render returns.
#[cfg(any(target_vendor = "apple", target_os = "windows"))]
pub mod shared_texture {
    use std::cell::RefCell;

    use i_slint_core::partial_renderer::DirtyRegion;
    use i_slint_core::renderer::DrawOutcome;
    use i_slint_renderer_skia::skia_safe::gpu::{self, BackendRenderTarget, DirectContext};
    use i_slint_renderer_skia::skia_safe::{Canvas, ColorType};
    use slint::PlatformError;

    // `+ '_`: the trait takes `&dyn Fn...` (bound to the borrow), while a
    // bare `dyn Fn...` alias would default to `+ 'static` and its `&` would
    // no longer match the trait (E0308 method-not-compatible-with-trait).
    pub type RenderCallback<'a> =
        dyn Fn(&Canvas, Option<&mut DirectContext>, u8) -> Option<DirtyRegion> + 'a;

    pub fn render(
        context: &RefCell<DirectContext>,
        target: &BackendRenderTarget,
        color_type: ColorType,
        render_callback: &RenderCallback<'_>,
        pre_present_callback: &RefCell<Option<Box<dyn FnMut()>>>,
    ) -> Result<DrawOutcome, PlatformError> {
        let mut context = context.borrow_mut();
        let mut surface = gpu::surfaces::wrap_backend_render_target(
            &mut context,
            target,
            gpu::SurfaceOrigin::TopLeft,
            color_type,
            None,
            None,
        )
        .ok_or("Skia could not wrap the shared texture")?;
        // Age 0: the renderer repaints everything (no partial rendering here).
        render_callback(surface.canvas(), Some(&mut *context), 0);
        drop(surface);
        if let Some(callback) = pre_present_callback.borrow_mut().as_mut() {
            callback();
        }
        // ponytail: the CPU waits for every frame; a fence Flutter's
        // compositor waits on instead would let the two overlap.
        context.flush_submit_and_sync_cpu();
        Ok(DrawOutcome::Success)
    }

    /// The texture's pixels as RGBA8888 premultiplied.
    #[cfg(test)]
    pub fn read_rgba(
        context: &RefCell<DirectContext>,
        target: &BackendRenderTarget,
        color_type: ColorType,
        width: u32,
        height: u32,
    ) -> Vec<u8> {
        use i_slint_renderer_skia::skia_safe::{AlphaType, ImageInfo};

        let mut context = context.borrow_mut();
        let mut surface = gpu::surfaces::wrap_backend_render_target(
            &mut context,
            target,
            gpu::SurfaceOrigin::TopLeft,
            color_type,
            None,
            None,
        )
        .expect("wrap the texture for read-back");
        let info = ImageInfo::new(
            (width as i32, height as i32),
            ColorType::RGBA8888,
            AlphaType::Premul,
            None,
        );
        let mut pixels = vec![0; (width * height * 4) as usize];
        assert!(surface.read_pixels(&info, &mut pixels, width as usize * 4, (0, 0)));
        pixels
    }
}
