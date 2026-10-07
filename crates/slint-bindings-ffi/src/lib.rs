//! `sb_*` C ABI over `slint-bindings-core`.
//!
//! Every entry point only forwards: it checks pointers, catches panics so they
//! never unwind into Swift or C#, and stores the failure text for
//! [`sb_last_error`]. All calls must come from the thread that created the
//! host (the host app's UI thread), because Slint objects are not `Send`.

#![allow(non_camel_case_types)]

use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

use slint_bindings_core::{DemoForm, EmbeddedHost, Error, PointerButton};

thread_local! {
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

/// C callback for `submitted(string)`: `user_data`, then the UTF-8 name. Null clears it.
pub type SbSubmittedFn = Option<extern "C" fn(user_data: *mut c_void, name: *const c_char)>;

/// Opaque handle to the demo form and its pixel buffer.
pub struct SbHost {
    host: EmbeddedHost<DemoForm>,
}

/// Result of [`sb_host_render`].
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct SbFrame {
    /// 1 when the buffer was written, 0 when the previous frame is still valid.
    pub redrawn: u8,
    /// 1 while animations run: render again on the next vsync.
    pub animating: u8,
    /// 1 when the call failed; see `sb_last_error`.
    pub failed: u8,
}

/// Mouse buttons, mirrored by the Swift and C# wrappers.
#[repr(u8)]
#[derive(Debug, Clone, Copy)]
pub enum SbPointerButton {
    /// Primary button.
    Left = 0,
    /// Secondary button.
    Right = 1,
    /// Wheel button.
    Middle = 2,
}

impl From<SbPointerButton> for PointerButton {
    fn from(button: SbPointerButton) -> Self {
        match button {
            SbPointerButton::Left => Self::Left,
            SbPointerButton::Right => Self::Right,
            SbPointerButton::Middle => Self::Middle,
        }
    }
}

fn set_error(msg: String) {
    // Interior NULs would truncate the message on the C side; make them visible instead.
    let msg = msg.replace('\0', "\\0");
    LAST_ERROR.with_borrow_mut(|slot| *slot = CString::new(msg).ok());
}

/// Clears the error slot, runs `body`, and turns an error or a panic into
/// `fail` plus a message for `sb_last_error`.
fn guard<T>(fail: T, body: impl FnOnce() -> Result<T, Error>) -> T {
    LAST_ERROR.with_borrow_mut(|slot| *slot = None);
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(value)) => value,
        Ok(Err(err)) => {
            set_error(err.to_string());
            fail
        }
        Err(_) => {
            set_error("panic inside slint-bindings".to_owned());
            fail
        }
    }
}

/// # Safety
/// `host` must be null or a live pointer returned by [`sb_demo_new`].
unsafe fn host_ref<'a>(host: *const SbHost) -> Option<&'a SbHost> {
    // SAFETY: the caller guarantees `host` is null or live and unaliased by `sb_host_free`.
    unsafe { host.as_ref() }
}

/// # Safety
/// `text` must be null or a NUL-terminated string valid for the call.
unsafe fn str_arg<'a>(text: *const c_char) -> &'a str {
    if text.is_null() {
        return "";
    }
    // SAFETY: non-null and NUL-terminated per the caller's contract.
    unsafe { CStr::from_ptr(text) }.to_str().unwrap_or_default()
}

/// Message of the last failed call on this thread, or null. Valid until the next `sb_*` call.
#[unsafe(no_mangle)]
pub extern "C" fn sb_last_error() -> *const c_char {
    LAST_ERROR.with_borrow(|slot| slot.as_ref().map_or(ptr::null(), |s| s.as_ptr()))
}

/// Creates the demo form at `width`×`height` physical pixels. Null on failure.
#[unsafe(no_mangle)]
pub extern "C" fn sb_demo_new(width: u32, height: u32, scale: f32) -> *mut SbHost {
    guard(ptr::null_mut(), || {
        let host = EmbeddedHost::new(DemoForm::new, width, height, scale)?;
        Ok(Box::into_raw(Box::new(SbHost { host })))
    })
}

/// Destroys a host. Null is ignored.
///
/// # Safety
/// `host` must be null or a pointer from [`sb_demo_new`] not freed before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_free(host: *mut SbHost) {
    if !host.is_null() {
        // SAFETY: the pointer came from `Box::into_raw` in `sb_demo_new` and is freed once.
        drop(unsafe { Box::from_raw(host) });
    }
}

/// Bytes the buffer passed to [`sb_host_render`] must hold; 0 for a null host.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_frame_len(host: *const SbHost) -> usize {
    // SAFETY: forwarded caller contract.
    unsafe { host_ref(host) }.map_or(0, |h| h.host.frame_len())
}

/// Resizes the frame; returns false on failure.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_resize(
    host: *mut SbHost,
    width: u32,
    height: u32,
    scale: f32,
) -> bool {
    guard(false, || {
        // SAFETY: forwarded caller contract; exclusive because the caller holds the only handle.
        let Some(h) = (unsafe { host.as_mut() }) else {
            return Ok(false);
        };
        h.host.resize(width, height, scale)?;
        Ok(true)
    })
}

/// Renders into `buf` (premultiplied RGBA8, `len` bytes) if the scene changed.
///
/// # Safety
/// `host` must be null or live; `buf` must be valid for `len` writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_render(host: *mut SbHost, buf: *mut u8, len: usize) -> SbFrame {
    let failed = SbFrame {
        failed: 1,
        ..SbFrame::default()
    };
    guard(failed, || {
        // SAFETY: forwarded caller contract.
        let Some(h) = (unsafe { host.as_mut() }) else {
            return Ok(failed);
        };
        if buf.is_null() {
            return Ok(failed);
        }
        // SAFETY: the caller guarantees `buf` is valid for `len` writable bytes.
        let out = unsafe { std::slice::from_raw_parts_mut(buf, len) };
        let frame = h.host.render(out)?;
        Ok(SbFrame {
            redrawn: frame.redrawn.into(),
            animating: frame.animating.into(),
            failed: 0,
        })
    })
}

/// Advances Slint timers and animations; call once per host frame tick.
#[unsafe(no_mangle)]
pub extern "C" fn sb_tick() {
    guard((), || {
        EmbeddedHost::<DemoForm>::tick();
        Ok(())
    });
}

/// Runs one event forwarder: false for a null host or a failed dispatch.
///
/// # Safety
/// `host` must be null or live.
unsafe fn with_host(host: *const SbHost, f: impl FnOnce(&SbHost) -> Result<(), Error>) -> bool {
    guard(false, || {
        // SAFETY: forwarded caller contract.
        let Some(h) = (unsafe { host_ref(host) }) else {
            return Ok(false);
        };
        f(h)?;
        Ok(true)
    })
}

/// Pointer moved, in logical points from the top-left corner.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_pointer_moved(host: *const SbHost, x: f32, y: f32) -> bool {
    // SAFETY: forwarded caller contract.
    unsafe { with_host(host, |h| h.host.pointer_moved(x, y)) }
}

/// Pointer button pressed, in logical points.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_pointer_pressed(
    host: *const SbHost,
    x: f32,
    y: f32,
    button: SbPointerButton,
) -> bool {
    // SAFETY: forwarded caller contract.
    unsafe { with_host(host, |h| h.host.pointer_pressed(x, y, button.into())) }
}

/// Pointer button released, in logical points.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_pointer_released(
    host: *const SbHost,
    x: f32,
    y: f32,
    button: SbPointerButton,
) -> bool {
    // SAFETY: forwarded caller contract.
    unsafe { with_host(host, |h| h.host.pointer_released(x, y, button.into())) }
}

/// Pointer left the view.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_pointer_exited(host: *const SbHost) -> bool {
    // SAFETY: forwarded caller contract.
    unsafe { with_host(host, |h| h.host.pointer_exited()) }
}

/// Scroll delta at `x`,`y`, all in logical points.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_pointer_scrolled(
    host: *const SbHost,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
) -> bool {
    // SAFETY: forwarded caller contract.
    unsafe { with_host(host, |h| h.host.pointer_scrolled(x, y, dx, dy)) }
}

/// The host view gained (true) or lost (false) keyboard focus.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_focus_changed(host: *const SbHost, focused: bool) -> bool {
    // SAFETY: forwarded caller contract.
    unsafe { with_host(host, |h| h.host.focus_changed(focused)) }
}

/// A key went down; `text` is UTF-8 (the typed character or a Slint key code).
///
/// # Safety
/// `host` must be null or live; `text` null or NUL-terminated.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_key_pressed(host: *const SbHost, text: *const c_char) -> bool {
    guard(false, || {
        // SAFETY: forwarded caller contract.
        let Some(h) = (unsafe { host_ref(host) }) else {
            return Ok(false);
        };
        // SAFETY: forwarded caller contract.
        h.host.key_pressed(unsafe { str_arg(text) })?;
        Ok(true)
    })
}

/// A key went up.
///
/// # Safety
/// `host` must be null or live; `text` null or NUL-terminated.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_host_key_released(host: *const SbHost, text: *const c_char) -> bool {
    guard(false, || {
        // SAFETY: forwarded caller contract.
        let Some(h) = (unsafe { host_ref(host) }) else {
            return Ok(false);
        };
        // SAFETY: forwarded caller contract.
        h.host.key_released(unsafe { str_arg(text) })?;
        Ok(true)
    })
}

/// Sets the demo form's `name` property.
///
/// # Safety
/// `host` must be null or live; `name` null or NUL-terminated.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_demo_set_name(host: *const SbHost, name: *const c_char) {
    // SAFETY: forwarded caller contract.
    if let Some(h) = unsafe { host_ref(host) } {
        // SAFETY: forwarded caller contract.
        h.host.component().set_name(unsafe { str_arg(name) }.into());
    }
}

/// Registers `callback` for the demo form's `submitted(name)`; null clears it.
/// `user_data` is passed back untouched and must outlive the host.
///
/// # Safety
/// `host` must be null or live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sb_demo_on_submitted(
    host: *const SbHost,
    callback: SbSubmittedFn,
    user_data: *mut c_void,
) {
    // SAFETY: forwarded caller contract.
    let Some(h) = (unsafe { host_ref(host) }) else {
        return;
    };
    let component = h.host.component();
    let Some(callback) = callback else {
        component.on_submitted(|_| {});
        return;
    };
    // Raw pointers are not `'static + Fn`-friendly; carry the address instead.
    let user_data = user_data as usize;
    component.on_submitted(move |name| {
        let Ok(name) = CString::new(name.as_str()) else {
            return;
        };
        callback(user_data as *mut c_void, name.as_ptr());
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    const WIDTH: u32 = 64;
    const HEIGHT: u32 = 48;

    #[test]
    fn render_through_the_c_abi_writes_a_frame() {
        let host = sb_demo_new(WIDTH, HEIGHT, 1.0);
        assert!(!host.is_null());
        // SAFETY: `host` is live until the free below.
        unsafe {
            let mut buf = vec![0u8; sb_host_frame_len(host)];
            let frame = sb_host_render(host, buf.as_mut_ptr(), buf.len());
            assert_eq!((frame.failed, frame.redrawn), (0, 1));
            sb_host_free(host);
        }
    }

    #[test]
    fn short_buffer_fails_with_a_message() {
        let host = sb_demo_new(WIDTH, HEIGHT, 1.0);
        // SAFETY: `host` is live until the free below.
        unsafe {
            let mut buf = vec![0u8; 1];
            let frame = sb_host_render(host, buf.as_mut_ptr(), buf.len());
            assert_eq!(frame.failed, 1);
            assert!(!sb_last_error().is_null());
            sb_host_free(host);
        }
    }

    #[test]
    fn null_host_is_refused_not_dereferenced() {
        // SAFETY: null is part of every entry point's contract.
        unsafe {
            assert_eq!(sb_host_frame_len(ptr::null()), 0);
            assert!(!sb_host_pointer_moved(ptr::null(), 0.0, 0.0));
        }
    }
}
