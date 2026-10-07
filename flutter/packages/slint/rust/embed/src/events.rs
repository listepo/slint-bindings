//! FFI event bytes from Dart, mapped onto `slint::platform::WindowEvent`.
//!
//! The numbers are the contract mirrored in `slint/lib/src/events.dart`.
//! The native C ABI uses a different button numbering and does not call this.

use slint::platform::PointerEventButton;
use slint::platform::WindowEvent;
use slint::LogicalPosition;

/// Create a pointer event from raw parameters.
/// kind: 0=move, 1=down, 2=up, 3=scroll, 4=exit
/// button: 0=none, 1=left, 2=right, 3=middle
/// dx/dy: delta for scroll, movement for move
pub fn pointer_event(
    kind: u8,
    x: f32,
    y: f32,
    button: u8,
    dx: f32,
    dy: f32,
) -> Option<WindowEvent> {
    let position = LogicalPosition::new(x, y);

    match kind {
        0 => Some(WindowEvent::PointerMoved { position }),
        1 => {
            let btn = match button {
                1 => PointerEventButton::Left,
                2 => PointerEventButton::Right,
                3 => PointerEventButton::Middle,
                _ => return None,
            };
            Some(WindowEvent::PointerPressed {
                position,
                button: btn,
            })
        }
        2 => {
            let btn = match button {
                1 => PointerEventButton::Left,
                2 => PointerEventButton::Right,
                3 => PointerEventButton::Middle,
                _ => return None,
            };
            Some(WindowEvent::PointerReleased {
                position,
                button: btn,
            })
        }
        3 => Some(WindowEvent::PointerScrolled {
            position,
            delta_x: dx,
            delta_y: dy,
        }),
        4 => Some(WindowEvent::PointerExited),
        _ => None,
    }
}

/// Slint named-key codes (`i-slint-common` key_codes). Dart mirrors these
/// in `slint/lib/src/slint_view.dart` (`slintKeyText`).
pub mod key_codes {
    pub const TAB: &str = "\u{0009}";
    pub const ESCAPE: &str = "\u{001b}";
    pub const SHIFT: &str = "\u{0010}";
    pub const CONTROL: &str = "\u{0011}";
    pub const ALT: &str = "\u{0012}";
    pub const SHIFT_R: &str = "\u{0015}";
    pub const CONTROL_R: &str = "\u{0016}";
    pub const META: &str = "\u{0017}";
    pub const META_R: &str = "\u{0018}";
    pub const UP_ARROW: &str = "\u{F700}";
    pub const DOWN_ARROW: &str = "\u{F701}";
    pub const LEFT_ARROW: &str = "\u{F702}";
    pub const RIGHT_ARROW: &str = "\u{F703}";
}

/// Create a keyboard event.
pub fn key_event(text: &str, pressed: bool) -> WindowEvent {
    if pressed {
        WindowEvent::KeyPressed { text: text.into() }
    } else {
        WindowEvent::KeyReleased { text: text.into() }
    }
}

#[cfg(test)]
mod tests {
    use super::{key_event, pointer_event};
    use slint::platform::WindowEvent;

    #[test]
    fn pointer_bytes_match_the_dart_encoding() {
        assert!(matches!(
            pointer_event(0, 3.0, 4.0, 0, 0.0, 0.0),
            Some(WindowEvent::PointerMoved { .. })
        ));
        assert!(matches!(
            pointer_event(1, 1.0, 2.0, 1, 0.0, 0.0),
            Some(WindowEvent::PointerPressed { .. })
        ));
        assert!(pointer_event(1, 0.0, 0.0, 0, 0.0, 0.0).is_none());
        assert!(matches!(
            pointer_event(4, 0.0, 0.0, 0, 0.0, 0.0),
            Some(WindowEvent::PointerExited)
        ));
        assert!(pointer_event(9, 0.0, 0.0, 0, 0.0, 0.0).is_none());
    }

    #[test]
    fn key_bytes_become_press_and_release() {
        assert!(matches!(
            key_event("a", true),
            WindowEvent::KeyPressed { .. }
        ));
        assert!(matches!(
            key_event("a", false),
            WindowEvent::KeyReleased { .. }
        ));
    }
}
