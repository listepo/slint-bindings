//! Drives the demo form through the C ABI the hosts call.
//!
//! The rectangles in `ui/demo.slint` are the hit targets (logical px, origin
//! top-left): the name field at (160, 64) and Continue at (80, 112). Headless,
//! so `just check` does not need a window server.

use std::ffi::{CStr, CString, c_char, c_void};

use slint_bindings_ffi::{
    SbFrame, SbHost, SbPointerButton, run_on_test_ui_thread, sb_demo_new, sb_demo_on_submitted,
    sb_demo_set_name, sb_host_composition_commit, sb_host_composition_update,
    sb_host_focus_changed, sb_host_frame_len, sb_host_free, sb_host_key_pressed,
    sb_host_key_released, sb_host_key_repeated, sb_host_pointer_moved, sb_host_pointer_pressed,
    sb_host_pointer_released, sb_host_render, sb_host_resize, sb_last_error, sb_tick,
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
        assert!(sb_host_pointer_pressed(
            host.0,
            x,
            y,
            SbPointerButton::Left as u8
        ));
        assert!(sb_host_pointer_released(
            host.0,
            x,
            y,
            SbPointerButton::Left as u8
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
    run_on_test_ui_thread(|| {
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
    });
}

#[test]
fn japanese_preedit_commits_into_the_field() {
    run_on_test_ui_thread(|| {
        let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
        let _ = render(&host);
        // SAFETY: `host` is live until the end of this test.
        unsafe { assert!(sb_host_focus_changed(host.0, true)) }
        click(&host, FIELD_X, FIELD_Y);

        let preedit = CString::new("あ").unwrap_or_default();
        let committed = CString::new("日本語").unwrap_or_default();
        // SAFETY: `host` is live; both strings are NUL-terminated.
        unsafe {
            assert!(sb_host_composition_update(host.0, preedit.as_ptr(), 0, 1));
        }
        let mut submitted = Vec::new();
        listen(&host, &raw mut submitted);
        click(&host, BUTTON_X, BUTTON_Y);
        // The reading is still a preedit, so Continue submits an empty name.
        assert_eq!(submitted, [""]);

        click(&host, FIELD_X, FIELD_Y);
        // SAFETY: `host` is live; `committed` is NUL-terminated.
        unsafe {
            assert!(sb_host_composition_commit(host.0, committed.as_ptr()));
        }
        submitted.clear();
        click(&host, BUTTON_X, BUTTON_Y);
        assert_eq!(submitted, ["日本語"]);
    });
}

#[test]
fn tab_past_the_last_control_is_not_accepted() {
    run_on_test_ui_thread(|| {
        let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
        let _ = render(&host);
        // SAFETY: `host` is live until the end of this test.
        unsafe { assert!(sb_host_focus_changed(host.0, true)) }
        click(&host, FIELD_X, FIELD_Y);
        let tab = CString::new("\t").unwrap_or_default();
        // SAFETY: `host` is live; `tab` is NUL-terminated.
        unsafe {
            // Field → button: the view keeps the key.
            assert!(sb_host_key_pressed(host.0, tab.as_ptr()));
            assert!(sb_host_key_released(host.0, tab.as_ptr()));
            // Button → wrap: the host should move focus out, and that is not an error.
            assert!(!sb_host_key_pressed(host.0, tab.as_ptr()));
            assert!(sb_last_error().is_null());
        }
    });
}

#[test]
fn enter_in_the_field_submits() {
    run_on_test_ui_thread(|| {
        let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
        let _ = render(&host);
        unsafe { assert!(sb_host_focus_changed(host.0, true)) }
        click(&host, FIELD_X, FIELD_Y);
        type_ascii(&host, "Bea");

        let mut submitted = Vec::new();
        listen(&host, &raw mut submitted);
        type_ascii(&host, "\n");
        assert_eq!(submitted, ["Bea"]);
    });
}

#[test]
fn host_set_name_reaches_the_submitted_callback() {
    run_on_test_ui_thread(|| {
        let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
        let _ = render(&host);
        let name = CString::new("Ivan").unwrap_or_default();
        // SAFETY: `host` is live; `name` is NUL-terminated.
        unsafe { sb_demo_set_name(host.0, name.as_ptr()) }
        let mut submitted = Vec::new();
        listen(&host, &raw mut submitted);
        click(&host, BUTTON_X, BUTTON_Y);
        assert_eq!(submitted, ["Ivan"]);
    });
}

#[test]
fn resize_changes_the_frame_and_a_repeat_does_not_repaint() {
    run_on_test_ui_thread(|| {
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
    });
}

#[test]
fn retina_demo_frame_paints() {
    run_on_test_ui_thread(|| {
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
            let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../target/demo-frame.rgba");
            let mut bytes = Vec::with_capacity(buf.len() + 32);
            bytes.extend(format!("{RETINA_PIXEL_WIDTH} {RETINA_PIXEL_HEIGHT}\n").into_bytes());
            bytes.extend_from_slice(&buf);
            let _ = std::fs::write(path, bytes);
        }
    });
}

/// The caret blinks, so these frames are taken with nothing focused. A person
/// can open the PNG; the test compares pixels. `SB_UPDATE_SNAPSHOTS=1`
/// rewrites the files when that picture is meant to change.
fn snapshot_path(name: &str) -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("tests/snapshots/{name}.png"))
}

fn encode_png(width: u32, height: u32, rgba: &[u8]) -> Result<Vec<u8>, png::EncodingError> {
    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    // The samples are already sRGB. The chunk stops a viewer from converting them.
    encoder.set_source_srgb(png::SrgbRenderingIntent::Perceptual);
    let mut writer = encoder.write_header()?;
    writer.write_image_data(rgba)?;
    writer.finish()?;
    Ok(out)
}

fn decode_png(bytes: &[u8]) -> Result<(u32, u32, Vec<u8>), png::DecodingError> {
    let decoder = png::Decoder::new(std::io::Cursor::new(bytes));
    let mut reader = decoder.read_info()?;
    let mut buf = vec![0; reader.output_buffer_size().unwrap_or(0)];
    let info = reader.next_frame(&mut buf)?;
    buf.truncate(info.line_size * info.height as usize);
    Ok((info.width, info.height, buf))
}

fn must<T, E: std::fmt::Display>(result: Result<T, E>) -> T {
    match result {
        Ok(value) => value,
        Err(err) => {
            let message = err.to_string();
            assert!(message.is_empty(), "{message}");
            std::process::abort();
        }
    }
}

fn differing_pixels(left: &[u8], right: &[u8]) -> usize {
    left.chunks(4)
        .zip(right.chunks(4))
        .filter(|(a, b)| a != b)
        .count()
}

fn assert_snapshot(name: &str, width: u32, height: u32, rgba: &[u8]) {
    let path = snapshot_path(name);
    let encoded = must(encode_png(width, height, rgba));
    if std::env::var_os("SB_UPDATE_SNAPSHOTS").is_some() {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(&path, &encoded);
        return;
    }
    assert!(
        path.is_file(),
        "missing snapshot {}; set SB_UPDATE_SNAPSHOTS=1 to write it",
        path.display()
    );
    let saved = std::fs::read(&path).unwrap_or_else(|err| {
        let message = err.to_string();
        assert!(message.is_empty(), "read {}: {message}", path.display());
        std::process::abort();
    });
    let (got_width, got_height, pixels) = must(decode_png(&saved));
    assert_eq!(
        (got_width, got_height, pixels.len()),
        (width, height, rgba.len()),
        "{name} snapshot size"
    );
    let diffs = differing_pixels(&pixels, rgba);
    if diffs == 0 {
        return;
    }
    let actual = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join(format!("../../target/snapshot-mismatches/{name}.png"));
    if let Some(parent) = actual.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(&actual, encoded);
    assert_eq!(
        diffs,
        0,
        "{name}: {diffs} pixels differ from {}; wrote {}",
        path.display(),
        actual.display()
    );
}

fn paint(width: u32, height: u32, scale: f32, name: Option<&str>) -> Vec<u8> {
    let host = open(width, height, scale);
    let (frame, mut buf) = render(&host);
    assert_eq!(frame.redrawn, 1);
    if let Some(name) = name {
        let c = CString::new(name).unwrap_or_default();
        assert!(!c.to_bytes().is_empty());
        // SAFETY: `host` is live; `c` is NUL-terminated.
        unsafe { sb_demo_set_name(host.0, c.as_ptr()) }
        let (frame, named) = render(&host);
        assert_eq!(frame.redrawn, 1);
        buf = named;
    }
    // A blinking caret or a running animation would repaint immediately.
    let (again, _) = render(&host);
    assert_eq!(again.redrawn, 0, "frame is still changing");
    buf
}

#[test]
fn sign_in_frame_matches_the_snapshot() {
    run_on_test_ui_thread(|| {
        let first = paint(FORM_WIDTH, FORM_HEIGHT, 1.0, None);
        let second = paint(FORM_WIDTH, FORM_HEIGHT, 1.0, None);
        assert_eq!(
            differing_pixels(&first, &second),
            0,
            "the sign-in frame is not stable across two hosts"
        );
        // Goldens are rasterised on macOS. Other OSes use different fonts.
        if !cfg!(target_os = "macos") {
            return;
        }
        assert_snapshot("sign-in", FORM_WIDTH, FORM_HEIGHT, &first);

        let retina = paint(FORM_WIDTH * 2, FORM_HEIGHT * 2, RETINA_SCALE, None);
        assert_snapshot("sign-in@2x", FORM_WIDTH * 2, FORM_HEIGHT * 2, &retina);
    });
}

#[test]
fn named_field_frame_matches_the_snapshot() {
    run_on_test_ui_thread(|| {
        let buf = paint(FORM_WIDTH, FORM_HEIGHT, 1.0, Some("Ada"));
        if !cfg!(target_os = "macos") {
            return;
        }
        assert_snapshot("sign-in-ada", FORM_WIDTH, FORM_HEIGHT, &buf);
    });
}

#[test]
fn key_repeat_is_accepted() {
    run_on_test_ui_thread(|| {
        let host = open(FORM_WIDTH, FORM_HEIGHT, 1.0);
        let _ = render(&host);
        unsafe { assert!(sb_host_focus_changed(host.0, true)) }
        click(&host, FIELD_X, FIELD_Y);
        let a = CString::new("a").unwrap_or_default();
        // SAFETY: `host` is live; `a` is NUL-terminated.
        unsafe {
            assert!(sb_host_key_pressed(host.0, a.as_ptr()));
            assert!(sb_host_key_repeated(host.0, a.as_ptr()));
            assert!(sb_host_key_released(host.0, a.as_ptr()));
        }
    });
}
