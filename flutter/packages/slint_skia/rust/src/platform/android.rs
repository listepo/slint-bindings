//! Android: the plugin's `SurfaceProducer` gives it a `Surface`; the JNI
//! export in `lib.rs` turns that into an `ANativeWindow`, and Slint's own GL
//! surface (glutin, EGL/GLES) renders into it. Flutter composites the queued
//! buffers; there is no frame-available call.
//!
//! Not Vulkan: Slint 1.18.0's `VulkanSurface` has no `AndroidNdk` window
//! arm (`create_surface` ends in `unimplemented!()`), so the renderer's
//! `vulkan` feature could not take this window.

use std::ffi::c_void;
use std::ptr::NonNull;
use std::sync::Arc;

use raw_window_handle::{
    AndroidDisplayHandle, AndroidNdkWindowHandle, DisplayHandle, HandleError, HasDisplayHandle,
    HasWindowHandle, RawDisplayHandle, RawWindowHandle, WindowHandle,
};

#[link(name = "android")]
extern "C" {
    fn ANativeWindow_fromSurface(env: *mut c_void, surface: *mut c_void) -> *mut c_void;
    fn ANativeWindow_release(window: *mut c_void);
}

/// `ANativeWindow_fromSurface` for the JNI export; 0 on failure.
pub fn window_from_surface(env: *mut c_void, surface: *mut c_void) -> i64 {
    if env.is_null() || surface.is_null() {
        return 0;
    }
    // SAFETY: JNI passes a live JNIEnv* and a local reference to a Surface.
    unsafe { ANativeWindow_fromSurface(env, surface) as i64 }
}

/// One acquired `ANativeWindow` reference, released on drop.
pub struct NativeWindow(NonNull<c_void>);

// Slint's surface API takes `Send + Sync` handles; the pointer is only used
// by EGL on the Slint thread.
unsafe impl Send for NativeWindow {}
unsafe impl Sync for NativeWindow {}

impl NativeWindow {
    /// Takes over one reference (from `nativeWindowFromSurface`).
    pub fn adopt(window: *mut c_void) -> Option<Self> {
        NonNull::new(window).map(Self)
    }
}

impl Drop for NativeWindow {
    fn drop(&mut self) {
        unsafe { ANativeWindow_release(self.0.as_ptr()) }
    }
}

impl HasWindowHandle for NativeWindow {
    fn window_handle(&self) -> Result<WindowHandle<'_>, HandleError> {
        let raw = RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(self.0));
        // SAFETY: the window lives as long as `self`.
        Ok(unsafe { WindowHandle::borrow_raw(raw) })
    }
}

impl HasDisplayHandle for NativeWindow {
    fn display_handle(&self) -> Result<DisplayHandle<'_>, HandleError> {
        let raw = RawDisplayHandle::Android(AndroidDisplayHandle::new());
        // SAFETY: Android has no display object to outlive.
        Ok(unsafe { DisplayHandle::borrow_raw(raw) })
    }
}

/// The window Slint's surface renders into, released after the surface.
pub struct Attachment {
    pub window: Arc<NativeWindow>,
}
