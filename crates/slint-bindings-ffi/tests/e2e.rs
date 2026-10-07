//! Drives the demo form through the C ABI the hosts call.
//!
//! The rectangles in `ui/demo.slint` are the hit targets (logical px, origin
//! top-left): the name field at (160, 64) and Continue at (80, 112). Headless,
//! so `just check` does not need a window server.

use std::ffi::{CStr, CString, c_char, c_void};

use slint_bindings_ffi::{
    SbFrame, SbHost, SbPointerButton, sb_demo_new, sb_demo_on_submitted, sb_demo_set_name,
    sb_host_focus_changed, sb_host_frame_len, sb_host_free, sb_host_key_pressed,
    sb_host_key_released, sb_host_pointer_moved, sb_host_pointer_pressed, sb_host_pointer_released,
    sb_host_render, sb_host_resize, sb_tick,
};

const FORM_WIDTH: u32 = 320;
const FORM_HEIGHT: u32 = 200;
const FIELD_X: f32 = 160.0;
const FIELD_Y: f32 = 64.0;
const BUTTON_X: f32 = 80.0;
const BUTTON_Y: f32 = 112.0;
/// 800×600 pt at 2×, the M1 checkpoint size.
const RETINA_PIXEL_WIDTH: u32 = 1600;
const RETINA_PIXEL_HEIGHT: u32 = 1200;
const RETINA_SCALE: f32 = 2.0;

struct Host(*mut SbHost);

impl Drop for Host {
    fn drop(&mut self) {
        // SAFETY: the pointer came from `sb_demo_new` and is freed once.
        unsafe { sb_host_free(self.0) }
    }
}

fn open(width: u32, height: u32, scale: f32) -> Host {
    let host = sb_demo_new(width, height, scale);
    assert!(!host.is_null(), "sb_demo_new failed");
    Host(host)
}

fn render(host: &Host) -> (SbFrame, Vec<u8>) {
    // SAFETY: `host` is live until `Host` drops.
    unsafe {
        let mut buf = vec![0u8; sb_host_frame_len(host.0)];
        let frame = sb_host_render(host.0, buf.as_mut_ptr(), buf.len());
        assert_eq!(frame.failed, 0, "render failed");
        (frame, buf)
    }
}

fn click(host: &Host, x: f32, y: f32) {
    // SAFETY: `host` is live until `Host` drops.
    unsafe {
        assert!(sb_host_pointer_moved(host.0, x, y));
        assert!(sb_host_pointer_pressed(host.0, x, y, SbPointerButton::Left));
        assert!(sb_host_pointer_released(
            host.0,
            x,
            y,
            SbPointerButton::Left
        ));
    }
}

fn type_ascii(host: &Host, text: &str) {
    for ch in text.chars() {
        let mut buf = [0u8; 4];
        let encoded = ch.encode_utf8(&mut buf);
        let c = CString::new(&*encoded).unwrap_or_default();
        assert!(!c.to_bytes().is_empty());
        // SAFETY: `host` is live; `c` is NUL-terminated and outlives the calls.
        unsafe {
            assert!(sb_host_key_pressed(host.0, c.as_ptr()));
            assert!(sb_host_key_released(host.0, c.as_ptr()));
        }
    }
}

extern "C" fn on_submitted(user_data: *mut c_void, name: *const c_char) {
    if user_data.is_null() || name.is_null() {
        return;
    }
    // SAFETY: the test passes a live `Vec<String>`, and the FFI passes a CString that is valid for this call.
    let text = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("")
        .to_owned();
    let slot = unsafe { &mut *user_data.cast::<Vec<String>>() };
    slot.push(text);
}

fn listen(host: &Host, slot: *mut Vec<String>) {
    // SAFETY: `host` is live; `slot` stays live for every callback this test fires.
    unsafe { sb_demo_on_submitted(host.0, Some(on_submitted), slot.cast()) }
}

#[test]
fn type_ascii_then_continue_submits_the_name() {
    let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
    let (frame, buf) = render(&host);
    assert_eq!(frame.redrawn, 1);
    assert!(buf.chunks(4).any(|px| px.len() == 4 && px[3] > 0));

    // SAFETY: `host` is live until the end of this test.
    unsafe { assert!(sb_host_focus_changed(host.0, true)) }
    click(&host, FIELD_X, FIELD_Y);
    type_ascii(&host, "Ada");

    let mut submitted = Vec::new();
    listen(&host, &raw mut submitted);
    click(&host, BUTTON_X, BUTTON_Y);
    assert_eq!(submitted, ["Ada"]);

    let (frame, _) = render(&host);
    assert_eq!(frame.redrawn, 1);
}

#[test]
fn enter_in_the_field_submits() {
    let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
    let _ = render(&host);
    unsafe { assert!(sb_host_focus_changed(host.0, true)) }
    click(&host, FIELD_X, FIELD_Y);
    type_ascii(&host, "Bea");

    let mut submitted = Vec::new();
    listen(&host, &raw mut submitted);
    type_ascii(&host, "\n");
    assert_eq!(submitted, ["Bea"]);
}

#[test]
fn host_set_name_reaches_the_submitted_callback() {
    let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
    let _ = render(&host);
    let name = CString::new("Ivan").unwrap_or_default();
    // SAFETY: `host` is live; `name` is NUL-terminated.
    unsafe { sb_demo_set_name(host.0, name.as_ptr()) }
    let mut submitted = Vec::new();
    listen(&host, &raw mut submitted);
    click(&host, BUTTON_X, BUTTON_Y);
    assert_eq!(submitted, ["Ivan"]);
}

#[test]
fn resize_changes_the_frame_and_a_repeat_does_not_repaint() {
    let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
    let _ = render(&host);
    // SAFETY: `host` is live.
    unsafe {
        assert!(sb_host_resize(host.0, FORM_WIDTH, FORM_HEIGHT, 1.0));
    }
    let (frame, _) = render(&host);
    assert_eq!(frame.redrawn, 0);

    unsafe {
        assert!(sb_host_resize(
            host.0,
            FORM_WIDTH * 2,
            FORM_HEIGHT * 2,
            RETINA_SCALE
        ));
        assert_eq!(
            sb_host_frame_len(host.0),
            (FORM_WIDTH * 2) as usize * (FORM_HEIGHT * 2) as usize * 4
        );
    }
    let (frame, buf) = render(&host);
    assert_eq!(frame.redrawn, 1);
    assert!(buf.chunks(4).any(|px| px.len() == 4 && px[3] > 0));
}

#[test]
fn retina_demo_frame_paints() {
    let host = open(RETINA_PIXEL_WIDTH, RETINA_PIXEL_HEIGHT, RETINA_SCALE);
    let started = std::time::Instant::now();
    let (frame, buf) = render(&host);
    let first = started.elapsed();
    assert_eq!(frame.redrawn, 1);
    assert!(buf.chunks(4).any(|px| px.len() == 4 && px[3] > 0));

    let name = CString::new("Ada").unwrap_or_default();
    // SAFETY: `host` is live; `name` is NUL-terminated.
    unsafe { sb_demo_set_name(host.0, name.as_ptr()) }
    sb_tick();
    let started = std::time::Instant::now();
    let (frame, buf) = render(&host);
    let dirty = started.elapsed();
    assert_eq!(frame.failed, 0);
    assert_eq!(frame.redrawn, 1);

    if std::env::var_os("SB_FRAME_TIME").is_some() {
        eprintln!(
            "retina_first_frame_us={} retina_dirty_frame_us={}",
            first.as_micros(),
            dirty.as_micros()
        );
        let path =
            std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target/demo-frame.rgba");
        let mut bytes = Vec::with_capacity(buf.len() + 32);
        bytes.extend(format!("{RETINA_PIXEL_WIDTH} {RETINA_PIXEL_HEIGHT}\n").into_bytes());
        bytes.extend_from_slice(&buf);
        let _ = std::fs::write(path, bytes);
    }
}
