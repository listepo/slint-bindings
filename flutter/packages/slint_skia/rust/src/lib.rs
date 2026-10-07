//! `slint_skia_*` C ABI: slint-interpreter plus `i-slint-renderer-skia`,
//! rendering into a GPU texture the Flutter plugin registers. Compiling,
//! instantiating and the property bridge go through `slint-dart-interpreter`;
//! the window, the renderer and the per-platform surfaces live in
//! `platform/`.

#![allow(non_camel_case_types)]
// C ABI entry points: only ever called through the C ABI with the pointer
// contract in the header — marking them `unsafe fn` changes nothing for
// those callers, and every dereference is already an explicit unsafe block.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

mod platform;

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::rc::Rc;

use slint::platform::WindowAdapter;
use slint::{ComponentHandle, LogicalSize, PhysicalSize, WindowSize};
use slint_dart_interpreter::{Definition, Engine, Instance};

use platform::{Attachment, SkiaWindowAdapter};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn set_error(msg: impl Into<String>) {
    let msg = msg.into().replace('\0', "\\0");
    let _ = LAST_ERROR.try_with(|e| *e.borrow_mut() = CString::new(msg).ok());
}

/// Runs one entry point: clears the error slot, checks the owner thread
/// (`slint_dart_core::thread`), catches panics, and on failure stores the
/// message and returns `fail`, the entry point's documented sentinel.
fn ffi<T>(name: &str, fail: T, body: impl FnOnce() -> Result<T, String>) -> T {
    let _ = LAST_ERROR.try_with(|e| e.borrow_mut().take());
    if let Err(e) = slint_dart_core::thread::check() {
        set_error(e);
        return fail;
    }
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(value)) => value,
        Ok(Err(e)) => {
            set_error(e);
            fail
        }
        Err(_) => {
            set_error(format!("panicked in {name}"));
            fail
        }
    }
}

fn utf8<'a>(ptr: *const c_char, what: &str) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err(format!("null {what}"));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| format!("{what} is not UTF-8: {e}"))
}

fn c_string(s: String) -> Result<*mut c_char, String> {
    CString::new(s)
        .map(CString::into_raw)
        .map_err(|e| e.to_string())
}

fn handle_of<'a>(instance: *mut c_void) -> Result<&'a InstanceHandle, String> {
    if instance.is_null() {
        return Err("null instance".into());
    }
    Ok(unsafe { &*instance.cast::<InstanceHandle>() })
}

// Only the platform attach calls take a texture size.
#[cfg_attr(
    not(any(
        target_vendor = "apple",
        target_os = "android",
        target_os = "linux",
        target_os = "windows"
    )),
    allow(dead_code)
)]
fn texture_size(width: u32, height: u32) -> Result<PhysicalSize, String> {
    if width == 0 || height == 0 {
        return Err(format!(
            "texture size must be positive, got {width}x{height}"
        ));
    }
    Ok(PhysicalSize::new(width, height))
}

/// A component instance, its window, and the GPU surface attached to it.
struct InstanceHandle {
    core: Instance,
    adapter: Rc<SkiaWindowAdapter>,
    /// What the attached surface renders into or borrows from the host;
    /// `None` while detached. Dropped after the surface (see `detach`).
    attachment: RefCell<Option<Attachment>>,
}

impl InstanceHandle {
    fn detach(&self) {
        // The surface first, then what it rendered into.
        let _ = self.adapter.skia().suspend();
        self.attachment.borrow_mut().take();
    }

    // Only the platform attach calls end here.
    #[cfg_attr(
        not(any(
            target_vendor = "apple",
            target_os = "android",
            target_os = "linux",
            target_os = "windows"
        )),
        allow(dead_code)
    )]
    fn attached(&self, attachment: Attachment, size: PhysicalSize) {
        *self.attachment.borrow_mut() = Some(attachment);
        self.adapter.set_size(size.into());
        // A fresh texture holds nothing yet.
        self.adapter.request_redraw();
    }

    /// `Ok(false)`: nothing changed since the last frame.
    fn render(&self) -> Result<bool, String> {
        if self.attachment.borrow().is_none() {
            return Err(
                "no GPU surface attached: create a SkiaTextureRenderTarget (or call an \
                 attach function) first"
                    .into(),
            );
        }
        slint::platform::update_timers_and_animations();
        if !self.adapter.take_redraw() {
            return Ok(false);
        }
        let _ = self.adapter.skia().render().map_err(|e| e.to_string())?;
        Ok(true)
    }
}

/// The error of the last failed call on this thread, or null. Every entry
/// point clears it first. Caller frees with [slint_skia_string_free].
#[no_mangle]
pub extern "C" fn slint_skia_last_error() -> *mut c_char {
    LAST_ERROR
        .try_with(|e| e.borrow_mut().take())
        .ok()
        .flatten()
        .map_or(ptr::null_mut(), CString::into_raw)
}

#[no_mangle]
pub extern "C" fn slint_skia_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(unsafe { CString::from_raw(s) });
    }
}

// === Engine and definitions ===

#[no_mangle]
pub extern "C" fn slint_skia_engine_new() -> *mut c_void {
    ffi("slint_skia_engine_new", ptr::null_mut(), || {
        Ok(Box::into_raw(Box::new(Engine::new())).cast())
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_engine_free(engine: *mut c_void) {
    if engine.is_null() {
        return;
    }
    ffi("slint_skia_engine_free", (), || {
        drop(unsafe { Box::from_raw(engine.cast::<Engine>()) });
        Ok(())
    })
}

/// Compiles `source` (resolving imports relative to `path`) and returns its
/// one exported component; free with [slint_skia_definitions_free].
#[no_mangle]
pub extern "C" fn slint_skia_engine_compile(
    engine: *mut c_void,
    source: *const c_char,
    path: *const c_char,
) -> *mut c_void {
    ffi("slint_skia_engine_compile", ptr::null_mut(), || {
        if engine.is_null() {
            return Err("null engine".into());
        }
        let source = utf8(source, "source")?;
        let path = utf8(path, "path")?;
        let engine = unsafe { &mut *engine.cast::<Engine>() };
        let mut defs = engine.compile(source, path)?;
        // The compiler hands definitions back in HashMap order, so "the
        // first" would be a coin flip: this backend takes exactly one.
        match defs.len() {
            1 => Ok(Box::into_raw(Box::new(defs.remove(0))).cast()),
            0 => Err("no definitions compiled".into()),
            n => {
                let names: Vec<String> = defs.iter().map(|d| d.name()).collect();
                Err(format!(
                    "slint_skia takes a file exporting exactly one component, got {n}: {}",
                    names.join(", ")
                ))
            }
        }
    })
}

/// `slint_skia_engine_compile` returns the one definition itself, so the
/// "list" it enumerates is that definition: count 1, name at index 0.
#[no_mangle]
pub extern "C" fn slint_skia_definitions_count(definition: *mut c_void) -> usize {
    usize::from(!definition.is_null())
}

/// Caller frees with [slint_skia_string_free]; null for a bad index.
#[no_mangle]
pub extern "C" fn slint_skia_definitions_name(
    definition: *mut c_void,
    index: usize,
) -> *mut c_char {
    ffi("slint_skia_definitions_name", ptr::null_mut(), || {
        if definition.is_null() || index != 0 {
            return Err(format!("no definition at index {index}"));
        }
        c_string(unsafe { &*definition.cast::<Definition>() }.name())
    })
}

/// Frees what [slint_skia_engine_compile] returned.
#[no_mangle]
pub extern "C" fn slint_skia_definitions_free(definition: *mut c_void) {
    if definition.is_null() {
        return;
    }
    ffi("slint_skia_definitions_free", (), || {
        drop(unsafe { Box::from_raw(definition.cast::<Definition>()) });
        Ok(())
    })
}

// === Instances ===

/// Instantiates the component in a window of its own: size 0x0 and no GPU
/// surface until an attach call.
#[no_mangle]
pub extern "C" fn slint_skia_instantiate(definition: *mut c_void) -> *mut c_void {
    ffi("slint_skia_instantiate", ptr::null_mut(), || {
        if definition.is_null() {
            return Err("null definition".into());
        }
        platform::ensure_platform();
        // A stale adapter from an instantiation that failed after creating one.
        platform::take_adapter();
        let core = unsafe { &*definition.cast::<Definition>() }.instantiate()?;
        // show() creates the window through the platform, which parks the
        // adapter for us to pick up.
        core.inner.show().map_err(|e| e.to_string())?;
        let adapter = platform::take_adapter().ok_or("the Slint platform created no window")?;
        let handle = InstanceHandle {
            core,
            adapter,
            attachment: RefCell::new(None),
        };
        Ok(Box::into_raw(Box::new(handle)).cast())
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_free(instance: *mut c_void) {
    if instance.is_null() {
        return;
    }
    ffi("slint_skia_instance_free", (), || {
        let handle = unsafe { Box::from_raw(instance.cast::<InstanceHandle>()) };
        handle.detach();
        // show() parked a strong reference to the component in its window;
        // without hide() the component and its timers outlive the free.
        let _ = handle.core.inner.hide();
        Ok(())
    })
}

/// Sizes the window in logical pixels (the scale factor stays 1, so logical
/// == physical). The attach calls size the window to their texture already;
/// this drives a component that has none.
#[no_mangle]
pub extern "C" fn slint_skia_instance_set_size(
    instance: *mut c_void,
    width: f32,
    height: f32,
) -> bool {
    ffi("slint_skia_instance_set_size", false, || {
        let handle = handle_of(instance)?;
        if !(width.is_finite() && height.is_finite() && width >= 0.0 && height >= 0.0) {
            return Err(format!("invalid size {width}x{height}"));
        }
        handle
            .adapter
            .set_size(WindowSize::Logical(LogicalSize::new(width, height)));
        Ok(true)
    })
}

/// Renders a frame into the attached surface if the scene changed.
/// True: a frame was rendered and finished on the GPU (tell Flutter). False
/// with no error ([slint_skia_last_error] null): nothing changed. False with
/// an error: no surface attached, or rendering failed.
#[no_mangle]
pub extern "C" fn slint_skia_instance_render(instance: *mut c_void) -> bool {
    ffi("slint_skia_instance_render", false, || {
        handle_of(instance)?.render()
    })
}

/// Drops the attached surface and what it rendered into. Rendering fails
/// until the next attach.
#[no_mangle]
pub extern "C" fn slint_skia_instance_detach(instance: *mut c_void) -> bool {
    ffi("slint_skia_instance_detach", false, || {
        handle_of(instance)?.detach();
        Ok(true)
    })
}

// === Per-platform attach (each replaces any previous surface) ===

/// Apple: renders into `texture`, an `id<MTLTexture>` (BGRA8Unorm,
/// `width`x`height`, render-target usage) created on `device`, with
/// commands on `queue`, and sizes the window to it. Skia retains the three
/// objects; the plugin keeps the texture's backing (its `CVMetalTexture`)
/// alive until the next attach, detach or free.
#[cfg(target_vendor = "apple")]
#[no_mangle]
pub extern "C" fn slint_skia_instance_attach_metal(
    instance: *mut c_void,
    device: *mut c_void,
    queue: *mut c_void,
    texture: *mut c_void,
    width: u32,
    height: u32,
) -> bool {
    ffi("slint_skia_instance_attach_metal", false, || {
        let handle = handle_of(instance)?;
        let size = texture_size(width, height)?;
        if device.is_null() || queue.is_null() || texture.is_null() {
            return Err("null Metal device, queue or texture".into());
        }
        handle.detach();
        // SAFETY: the plugin passes live objects of these types (see above).
        let surface =
            unsafe { platform::metal::TextureSurface::wrap(device, queue, texture, size) }?;
        handle.adapter.skia().set_surface(Box::new(surface));
        handle.attached(Attachment, size);
        Ok(true)
    })
}

/// Android: renders into `window`, an `ANativeWindow*` from
/// `SlintSkiaNative.nativeWindowFromSurface` (one acquired reference, which
/// this call takes over, also when it fails), through Slint's own GL (EGL)
/// surface, and sizes the window to `width`x`height`. Flutter composites
/// the queued buffers itself.
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn slint_skia_instance_attach_android(
    instance: *mut c_void,
    window: *mut c_void,
    width: u32,
    height: u32,
) -> bool {
    ffi("slint_skia_instance_attach_android", false, || {
        // Adopt first, so the reference is released whatever fails below.
        let window = std::sync::Arc::new(
            platform::android::NativeWindow::adopt(window).ok_or("null ANativeWindow")?,
        );
        let handle = handle_of(instance)?;
        let size = texture_size(width, height)?;
        handle.detach();
        // 1.18: last arg is surface transparency (Flutter Texture keeps alpha).
        handle
            .adapter
            .skia()
            .set_window_handle(window.clone(), window.clone(), size, None, true)
            .map_err(|e| e.to_string())?;
        handle.attached(Attachment { window }, size);
        Ok(true)
    })
}

/// JNI for `dev.slint.slint_skia.SlintSkiaNative.nativeWindowFromSurface`:
/// acquires the `ANativeWindow` behind an `android.view.Surface`, 0 on
/// failure. Hand it to [slint_skia_instance_attach_android].
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_dev_slint_slint_1skia_SlintSkiaNative_nativeWindowFromSurface(
    env: *mut c_void,
    _class: *mut c_void,
    surface: *mut c_void,
) -> i64 {
    catch_unwind(AssertUnwindSafe(|| {
        platform::android::window_from_surface(env, surface)
    }))
    .unwrap_or(0)
}

/// Windows: creates a D3D12 device on the adapter with this LUID (Flutter's;
/// 0/0 = the first adapter) and a shared BGRA8 texture of
/// `width`x`height`, renders into it, and sizes the window. Returns the
/// texture's NT shared handle for the plugin's `GpuSurfaceTexture`, valid
/// until the next attach, detach or free; null on error.
#[cfg(target_os = "windows")]
#[no_mangle]
pub extern "C" fn slint_skia_instance_attach_d3d(
    instance: *mut c_void,
    luid_low: u32,
    luid_high: i32,
    width: u32,
    height: u32,
) -> *mut c_void {
    ffi("slint_skia_instance_attach_d3d", ptr::null_mut(), || {
        let handle = handle_of(instance)?;
        let size = texture_size(width, height)?;
        handle.detach();
        let (surface, attachment) = platform::d3d::create(luid_low, luid_high, size)?;
        let shared = attachment.shared_handle();
        handle.adapter.skia().set_surface(Box::new(surface));
        handle.attached(attachment, size);
        Ok(shared)
    })
}

/// Linux: renders offscreen through a headless EGL (GLES) context, reads
/// each frame back (see [slint_skia_instance_pixels]), and sizes the window
/// to `width`x`height`.
#[cfg(target_os = "linux")]
#[no_mangle]
pub extern "C" fn slint_skia_instance_attach_gl(
    instance: *mut c_void,
    width: u32,
    height: u32,
) -> bool {
    ffi("slint_skia_instance_attach_gl", false, || {
        let handle = handle_of(instance)?;
        let size = texture_size(width, height)?;
        handle.detach();
        let (surface, attachment) = platform::gl::create(size)?;
        handle.adapter.skia().set_surface(Box::new(surface));
        handle.attached(attachment, size);
        Ok(true)
    })
}

/// Linux: the last rendered frame, RGBA8888 premultiplied, `*len` =
/// width*height*4 bytes. Borrowed: valid until the next render, attach,
/// detach or free. Null (error set) before the first frame.
#[cfg(target_os = "linux")]
#[no_mangle]
pub extern "C" fn slint_skia_instance_pixels(instance: *mut c_void, len: *mut usize) -> *const u8 {
    ffi("slint_skia_instance_pixels", ptr::null(), || {
        let handle = handle_of(instance)?;
        if len.is_null() {
            return Err("null len".into());
        }
        let attachment = handle.attachment.borrow();
        let frame = attachment
            .as_ref()
            .ok_or("no GPU surface attached")?
            .frame();
        if frame.is_empty() {
            return Err("no frame rendered yet".into());
        }
        unsafe { *len = frame.len() };
        Ok(frame.as_ptr())
    })
}

// === Input ===

/// kind: 0 move, 1 down, 2 up, 3 scroll, 4 exit; button: 0 none, 1 left,
/// 2 right, 3 middle (see `slint_dart_core::events`). False (error set) for
/// an unknown kind or a press/release without a button.
#[no_mangle]
pub extern "C" fn slint_skia_instance_pointer_event(
    instance: *mut c_void,
    kind: u8,
    x: f32,
    y: f32,
    button: u8,
    dx: f32,
    dy: f32,
) -> bool {
    ffi("slint_skia_instance_pointer_event", false, || {
        let handle = handle_of(instance)?;
        let event = slint_dart_core::events::pointer_event(kind, x, y, button, dx, dy)
            .ok_or_else(|| format!("invalid pointer event: kind {kind}, button {button}"))?;
        handle.adapter.window().dispatch_event(event);
        Ok(true)
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_key_event(
    instance: *mut c_void,
    text: *const c_char,
    pressed: bool,
) -> bool {
    ffi("slint_skia_instance_key_event", false, || {
        let handle = handle_of(instance)?;
        let text = utf8(text, "key text")?;
        handle
            .adapter
            .window()
            .dispatch_event(slint_dart_core::events::key_event(text, pressed));
        Ok(true)
    })
}

// === Property bridge (JSON, as in slint-dart-interpreter) ===

/// Caller frees with [slint_skia_string_free].
#[no_mangle]
pub extern "C" fn slint_skia_instance_get_property(
    instance: *mut c_void,
    name: *const c_char,
) -> *mut c_char {
    ffi("slint_skia_instance_get_property", ptr::null_mut(), || {
        let handle = handle_of(instance)?;
        c_string(
            handle
                .core
                .get_property_json(utf8(name, "property name")?)?,
        )
    })
}

#[no_mangle]
pub extern "C" fn slint_skia_instance_set_property(
    instance: *mut c_void,
    name: *const c_char,
    value_json: *const c_char,
) -> bool {
    ffi("slint_skia_instance_set_property", false, || {
        let handle = handle_of(instance)?;
        handle
            .core
            .set_property_json(utf8(name, "property name")?, utf8(value_json, "value")?)?;
        Ok(true)
    })
}

/// Caller frees with [slint_skia_string_free].
#[no_mangle]
pub extern "C" fn slint_skia_instance_invoke(
    instance: *mut c_void,
    name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    ffi("slint_skia_instance_invoke", ptr::null_mut(), || {
        let handle = handle_of(instance)?;
        c_string(
            handle
                .core
                .invoke_json(utf8(name, "callback name")?, utf8(args_json, "arguments")?)?,
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A window of one colour: any pixel tells whether the GPU frame arrived.
    const PROBE: &str = "export component Probe inherits Window { background: #ff0000; }";

    fn last_error() -> String {
        let ptr = slint_skia_last_error();
        if ptr.is_null() {
            return String::new();
        }
        let msg = unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned();
        slint_skia_string_free(ptr);
        msg
    }

    /// With `SLINT_SKIA_NO_GPU=1` a machine without a usable GPU API skips the
    /// frame check (and says so); otherwise that fails the test.
    #[cfg_attr(
        not(any(target_vendor = "apple", target_os = "linux", target_os = "windows")),
        allow(dead_code)
    )]
    fn no_gpu(why: &str) {
        assert!(
            std::env::var_os("SLINT_SKIA_NO_GPU").is_some(),
            "{why} (set SLINT_SKIA_NO_GPU=1 to skip the frame check)"
        );
        eprintln!("{why}: GPU frame NOT checked");
    }

    #[cfg_attr(
        not(any(target_vendor = "apple", target_os = "linux", target_os = "windows")),
        allow(dead_code)
    )]
    fn assert_red(rgba: &[u8], width: u32, height: u32) {
        assert_eq!(rgba.len(), (width * height * 4) as usize);
        for (x, y) in [(0, 0), (width / 2, height / 2), (width - 1, height - 1)] {
            let at = ((y * width + x) * 4) as usize;
            assert_eq!(&rgba[at..at + 4], &[255, 0, 0, 255], "pixel ({x}, {y})");
        }
    }

    // One test on purpose: the entry points are pinned to the first thread
    // that calls in, and libtest runs every test on a thread of its own.
    #[test]
    fn renders_through_the_gpu_surface() {
        let engine = slint_skia_engine_new();
        let source = CString::new(PROBE).unwrap();
        let path = CString::new("probe.slint").unwrap();
        let definition = slint_skia_engine_compile(engine, source.as_ptr(), path.as_ptr());
        assert!(!definition.is_null(), "{}", last_error());
        let instance = slint_skia_instantiate(definition);
        assert!(!instance.is_null(), "{}", last_error());

        // No surface: an explicit error, never a silent success.
        assert!(!slint_skia_instance_render(instance));
        assert!(last_error().contains("no GPU surface"));

        assert!(!slint_skia_instance_pointer_event(
            instance, 9, 0.0, 0.0, 0, 0.0, 0.0
        ));
        assert!(last_error().contains("invalid pointer event"));
        assert!(
            slint_skia_instance_pointer_event(instance, 0, 1.0, 1.0, 0, 0.0, 0.0),
            "{}",
            last_error()
        );

        gpu::check_frame(instance, 64, 48);
        // A resize is a new texture: attach again at the new size.
        gpu::check_frame(instance, 32, 16);

        assert!(slint_skia_instance_detach(instance));
        assert!(!slint_skia_instance_render(instance));
        assert!(last_error().contains("no GPU surface"));

        slint_skia_instance_free(instance);
        slint_skia_definitions_free(definition);
        slint_skia_engine_free(engine);
    }

    /// Nothing changed since the frame just rendered: no second frame, no error.
    #[cfg_attr(
        not(any(target_vendor = "apple", target_os = "linux", target_os = "windows")),
        allow(dead_code)
    )]
    fn assert_idle(instance: *mut c_void) {
        assert!(!slint_skia_instance_render(instance));
        assert_eq!(last_error(), "");
    }

    #[cfg(target_vendor = "apple")]
    mod gpu {
        use super::*;
        use crate::platform::metal::test_support;

        pub fn check_frame(instance: *mut c_void, width: u32, height: u32) {
            let Some(objects) = test_support::metal_objects(width, height) else {
                return no_gpu("no Metal device");
            };
            assert!(
                slint_skia_instance_attach_metal(
                    instance,
                    objects.device,
                    objects.queue,
                    objects.texture,
                    width,
                    height
                ),
                "{}",
                last_error()
            );
            assert!(slint_skia_instance_render(instance), "{}", last_error());
            assert_idle(instance);
            assert_red(
                &test_support::read_rgba(&objects, width, height),
                width,
                height,
            );
        }
    }

    #[cfg(target_os = "linux")]
    mod gpu {
        use super::*;

        pub fn check_frame(instance: *mut c_void, width: u32, height: u32) {
            if !slint_skia_instance_attach_gl(instance, width, height) {
                return no_gpu(&format!("no EGL/GLES: {}", last_error()));
            }
            assert!(slint_skia_instance_render(instance), "{}", last_error());
            let mut len = 0;
            let pixels = slint_skia_instance_pixels(instance, &mut len);
            assert!(!pixels.is_null(), "{}", last_error());
            assert_red(
                unsafe { std::slice::from_raw_parts(pixels, len) },
                width,
                height,
            );
            assert_idle(instance);
        }
    }

    #[cfg(target_os = "windows")]
    mod gpu {
        use super::*;

        pub fn check_frame(instance: *mut c_void, width: u32, height: u32) {
            if slint_skia_instance_attach_d3d(instance, 0, 0, width, height).is_null() {
                return no_gpu(&format!("no D3D12 device: {}", last_error()));
            }
            assert!(slint_skia_instance_render(instance), "{}", last_error());
            assert_idle(instance);
            let handle = handle_of(instance).unwrap();
            let attachment = handle.attachment.borrow();
            let rgba = crate::platform::d3d::test_support::read_rgba(
                attachment.as_ref().unwrap(),
                width,
                height,
            );
            assert_red(&rgba, width, height);
        }
    }

    #[cfg(not(any(target_vendor = "apple", target_os = "linux", target_os = "windows")))]
    mod gpu {
        pub fn check_frame(_: *mut super::c_void, _: u32, _: u32) {}
    }
}
