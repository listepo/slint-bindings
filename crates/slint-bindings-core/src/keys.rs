//! Host key events to the text [`slint::platform::Key`] uses.
//!
//! Slint names a key by a single Unicode scalar (control characters for
//! modifiers and editing keys, the Cocoa private-use range for arrows and
//! function keys, the typed character otherwise). Neither AppKit nor WinUI
//! hands those scalars over unchanged. AppKit reports Backspace as DEL and
//! Shift-Tab as BACKTAB; WinUI reports a `VirtualKey` plus, for printable
//! keys, the character the layout produced. The maps below cover both.

/// `NSEventModifierFlagShift`.
pub const MOD_SHIFT: u32 = 1 << 17;
/// `NSEventModifierFlagControl`.
pub const MOD_CONTROL: u32 = 1 << 18;
/// `NSEventModifierFlagOption`.
pub const MOD_OPTION: u32 = 1 << 19;
/// `NSEventModifierFlagCommand`.
pub const MOD_COMMAND: u32 = 1 << 20;

/// One AppKit `keyDown`, `keyUp` or `flagsChanged` event.
#[derive(Debug, Clone, Copy)]
pub struct AppKitKey<'a> {
    /// `NSEvent.keyCode` (Carbon virtual key code). `0` when the event only
    /// carries characters, which is how F21–F24 and the PC keys without an
    /// Apple code arrive.
    pub key_code: u16,
    /// `NSEvent.characters`.
    pub characters: &'a str,
    /// `NSEvent.charactersIgnoringModifiers`.
    pub characters_ignoring_modifiers: &'a str,
    /// `NSEvent.modifierFlags.rawValue`. Only the device-independent bits above are read.
    pub modifiers: u32,
}

/// The Slint key text for `key`, or `None` when AppKit reported something
/// Slint has no key for (volume, fn, an empty event).
pub fn appkit_key_text(key: AppKitKey<'_>) -> Option<String> {
    if let Some(mapped) = from_key_code(key.key_code, key.modifiers) {
        return Some(mapped.to_string());
    }
    // ⌘ shortcuts name the physical key, not the glyph Shift or Option produced.
    let produced =
        if key.modifiers & MOD_COMMAND != 0 && !key.characters_ignoring_modifiers.is_empty() {
            key.characters_ignoring_modifiers
        } else if !key.characters.is_empty() {
            key.characters
        } else {
            key.characters_ignoring_modifiers
        };
    let mut chars = produced.chars();
    let first = chars.next()?;
    // A key event is one scalar. A longer string is an IME commit, which
    // travels through the composition calls rather than this map.
    if chars.next().is_some() {
        return None;
    }
    Some(remap_character(first).to_string())
}

/// Carbon virtual key codes (`Events.h`) that name a Slint key on their own.
fn from_key_code(key_code: u16, modifiers: u32) -> Option<char> {
    Some(match key_code {
        0x24 | 0x4C => '\n', // Return, keypad Enter
        0x30 => {
            if modifiers & MOD_SHIFT != 0 {
                '\u{19}' // Backtab
            } else {
                '\t'
            }
        }
        0x31 => ' ',
        0x33 => '\u{8}',    // Delete (Backspace). AppKit's character for it is DEL.
        0x35 => '\u{1b}',   // Escape
        0x36 => '\u{18}',   // Right Command
        0x37 => '\u{17}',   // Command
        0x38 => '\u{10}',   // Shift
        0x39 => '\u{14}',   // Caps Lock
        0x3A => '\u{12}',   // Option
        0x3B => '\u{11}',   // Control
        0x3C => '\u{15}',   // Right Shift
        0x3D => '\u{13}',   // Right Option. Slint calls that key AltGr.
        0x3E => '\u{16}',   // Right Control
        0x40 => '\u{F714}', // F17
        0x4F => '\u{F715}', // F18
        0x50 => '\u{F716}', // F19
        0x5A => '\u{F717}', // F20
        0x60 => '\u{F708}', // F5
        0x61 => '\u{F709}', // F6
        0x62 => '\u{F70A}', // F7
        0x63 => '\u{F706}', // F3
        0x64 => '\u{F70B}', // F8
        0x65 => '\u{F70C}', // F9
        0x67 => '\u{F70E}', // F11
        0x69 => '\u{F710}', // F13
        0x6A => '\u{F713}', // F16
        0x6B => '\u{F711}', // F14
        0x6D => '\u{F70D}', // F10
        0x6F => '\u{F70F}', // F12
        0x71 => '\u{F712}', // F15
        0x72 => '\u{F727}', // Help, which PC keyboards report as Insert
        0x73 => '\u{F729}', // Home
        0x74 => '\u{F72C}', // Page Up
        0x75 => '\u{7f}',   // Forward Delete
        0x76 => '\u{F707}', // F4
        0x77 => '\u{F72B}', // End
        0x78 => '\u{F705}', // F2
        0x79 => '\u{F72D}', // Page Down
        0x7A => '\u{F704}', // F1
        0x7B => '\u{F702}', // Left
        0x7C => '\u{F703}', // Right
        0x7D => '\u{F701}', // Down
        0x7E => '\u{F700}', // Up
        _ => return None,
    })
}

/// Characters AppKit and WinUI produce that are not the scalar Slint stores for that key.
fn remap_character(ch: char) -> char {
    match ch {
        '\r' | '\u{3}' => '\n', // Return, Enter
        '\u{7F}' => '\u{8}',    // Backspace
        '\u{F728}' => '\u{7F}', // Forward Delete
        other => other,
    }
}

/// One WinUI `KeyRoutedEventArgs`, optionally with the character
/// `CharacterReceived` reported for the same press.
#[derive(Debug, Clone, Copy)]
pub struct VirtualKeyEvent<'a> {
    /// `Windows.System.VirtualKey` as `u16`. The numbers match Win32 `VK_*`.
    pub virtual_key: u16,
    /// Layout-produced character, or empty when the event is only a virtual key.
    pub character: &'a str,
    /// Shift is down. Distinguishes Tab from Backtab.
    pub shift: bool,
    /// Control is down. Shortcuts name the virtual key, not the control character.
    pub control: bool,
}

/// The Slint key text for a WinUI virtual key that has no character of its own
/// (arrows, editing keys, modifiers, function keys), or `None` when the host
/// should wait for [`virtual_key_text`] and a character.
pub fn virtual_key_command(virtual_key: u16, shift: bool) -> Option<char> {
    named_virtual_key(virtual_key, shift)
}

/// The Slint key text for one WinUI key event, or `None` when it is not a
/// Slint key (a mouse button, an empty event, a multi-scalar IME commit).
pub fn virtual_key_text(key: VirtualKeyEvent<'_>) -> Option<char> {
    if let Some(named) = named_virtual_key(key.virtual_key, key.shift) {
        return Some(named);
    }
    // Ctrl+C arrives as a control character. The shortcut names the key.
    if key.control
        && let Some(named) = unshifted_key(key.virtual_key)
    {
        return Some(named);
    }
    if let Some(ch) = one_scalar(key.character) {
        return Some(remap_character(ch));
    }
    unshifted_key(key.virtual_key)
}

/// Virtual keys Slint names without help from the keyboard layout.
fn named_virtual_key(virtual_key: u16, shift: bool) -> Option<char> {
    Some(match virtual_key {
        0x08 => '\u{8}', // Back
        0x09 => {
            if shift {
                '\u{19}' // Backtab
            } else {
                '\t'
            }
        }
        0x0D => '\n',            // Enter
        0x10 | 0xA0 => '\u{10}', // Shift, Left Shift
        0xA1 => '\u{15}',        // Right Shift
        0x11 | 0xA2 => '\u{11}', // Control, Left Control
        0xA3 => '\u{16}',        // Right Control
        0x12 | 0xA4 => '\u{12}', // Alt, Left Alt
        0xA5 => '\u{13}',        // Right Alt (AltGr)
        0x13 => '\u{F730}',      // Pause
        0x14 => '\u{14}',        // Caps Lock
        0x1B => '\u{1b}',
        0x20 => ' ',
        0x21 => '\u{F72C}', // Page Up
        0x22 => '\u{F72D}', // Page Down
        0x23 => '\u{F72B}', // End
        0x24 => '\u{F729}', // Home
        0x25 => '\u{F702}', // Left
        0x26 => '\u{F700}', // Up
        0x27 => '\u{F703}', // Right
        0x28 => '\u{F701}', // Down
        0x2C => '\u{F731}', // Print Screen, which Slint calls SysReq
        0x2D => '\u{F727}', // Insert
        0x2E => '\u{7f}',   // Delete
        0x5B => '\u{17}',   // Left Windows
        0x5C => '\u{18}',   // Right Windows
        0x5D => '\u{F735}', // Application (Menu)
        0x70..=0x87 => return function_key(virtual_key),
        0x91 => '\u{F72F}', // Scroll Lock
        0xA6 => '\u{F748}', // Browser Back
        0xB2 => '\u{F734}', // Media Stop
        _ => return None,
    })
}

/// F1 is U+F704 and the following function keys are the next scalars.
fn function_key(virtual_key: u16) -> Option<char> {
    let index = virtual_key.checked_sub(0x70)?;
    if index > 23 {
        return None;
    }
    char::from_u32(0xF704 + u32::from(index))
}

/// Unshifted US glyph for a virtual key, used when the event has no character
/// (a key-up, a test) or Control is naming the physical key.
fn unshifted_key(virtual_key: u16) -> Option<char> {
    Some(match virtual_key {
        0x30..=0x39 => char::from_u32(u32::from(b'0') + u32::from(virtual_key - 0x30))?,
        0x41..=0x5A => char::from_u32(u32::from(b'a') + u32::from(virtual_key - 0x41))?,
        0x60..=0x69 => char::from_u32(u32::from(b'0') + u32::from(virtual_key - 0x60))?,
        0x6A => '*',
        0x6B => '+',
        0x6D => '-',
        0x6E => '.',
        0x6F => '/',
        0xBA => ';',
        0xBB => '=',
        0xBC => ',',
        0xBD => '-',
        0xBE => '.',
        0xBF => '/',
        0xC0 => '`',
        0xDB => '[',
        0xDC => '\\',
        0xDD => ']',
        0xDE => '\'',
        _ => return None,
    })
}

fn one_scalar(text: &str) -> Option<char> {
    let mut chars = text.chars();
    let first = chars.next()?;
    if chars.next().is_some() {
        return None;
    }
    Some(first)
}

/// `range` is a UTF-16 selection inside `text`, the unit `NSRange` uses.
/// Slint's preedit selection is a UTF-8 byte range. `None` when `start` is
/// negative (AppKit's `NSNotFound`, passed as `-1`) or the offsets fall
/// outside `text`.
pub fn utf16_selection_to_utf8(text: &str, start: i32, end: i32) -> Option<std::ops::Range<i32>> {
    if start < 0 || end < start {
        return None;
    }
    let start_byte = utf16_to_utf8_offset(text, start)?;
    let end_byte = utf16_to_utf8_offset(text, end)?;
    Some(start_byte..end_byte)
}

fn utf16_to_utf8_offset(text: &str, utf16_offset: i32) -> Option<i32> {
    let target = utf16_offset as usize;
    let mut units = 0usize;
    for (byte, ch) in text.char_indices() {
        if units == target {
            return Some(byte as i32);
        }
        if units > target {
            return None;
        }
        units += ch.len_utf16();
    }
    if units == target {
        Some(text.len() as i32)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use slint::SharedString;
    use slint::platform::Key;

    use super::*;

    struct Case {
        key: Key,
        key_code: u16,
        characters: &'static str,
        ignoring: &'static str,
        modifiers: u32,
    }

    fn event(case: &Case) -> AppKitKey<'static> {
        AppKitKey {
            key_code: case.key_code,
            characters: case.characters,
            characters_ignoring_modifiers: case.ignoring,
            modifiers: case.modifiers,
        }
    }

    /// One AppKit source for every [`Key`] variant in Slint 1.18.1
    /// (`internal/common/key_codes.rs`, 123 variants). A new variant fails
    /// the length check below.
    fn cases() -> Vec<Case> {
        let typed = |key, characters| Case {
            key,
            key_code: 0,
            characters,
            ignoring: characters,
            modifiers: 0,
        };
        vec![
            Case {
                key: Key::Backspace,
                key_code: 0x33,
                characters: "\u{7F}",
                ignoring: "\u{7F}",
                modifiers: 0,
            },
            Case {
                key: Key::Tab,
                key_code: 0x30,
                characters: "\t",
                ignoring: "\t",
                modifiers: 0,
            },
            Case {
                key: Key::Return,
                key_code: 0x24,
                characters: "\r",
                ignoring: "\r",
                modifiers: 0,
            },
            Case {
                key: Key::Escape,
                key_code: 0x35,
                characters: "\u{1b}",
                ignoring: "\u{1b}",
                modifiers: 0,
            },
            Case {
                key: Key::Backtab,
                key_code: 0x30,
                characters: "\u{19}",
                ignoring: "\t",
                modifiers: MOD_SHIFT,
            },
            Case {
                key: Key::Delete,
                key_code: 0x75,
                characters: "\u{F728}",
                ignoring: "\u{F728}",
                modifiers: 0,
            },
            Case {
                key: Key::Shift,
                key_code: 0x38,
                characters: "",
                ignoring: "",
                modifiers: MOD_SHIFT,
            },
            Case {
                key: Key::Control,
                key_code: 0x3B,
                characters: "",
                ignoring: "",
                modifiers: MOD_CONTROL,
            },
            Case {
                key: Key::Alt,
                key_code: 0x3A,
                characters: "",
                ignoring: "",
                modifiers: MOD_OPTION,
            },
            Case {
                key: Key::AltGr,
                key_code: 0x3D,
                characters: "",
                ignoring: "",
                modifiers: MOD_OPTION,
            },
            Case {
                key: Key::CapsLock,
                key_code: 0x39,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::ShiftR,
                key_code: 0x3C,
                characters: "",
                ignoring: "",
                modifiers: MOD_SHIFT,
            },
            Case {
                key: Key::ControlR,
                key_code: 0x3E,
                characters: "",
                ignoring: "",
                modifiers: MOD_CONTROL,
            },
            Case {
                key: Key::Meta,
                key_code: 0x37,
                characters: "",
                ignoring: "",
                modifiers: MOD_COMMAND,
            },
            Case {
                key: Key::MetaR,
                key_code: 0x36,
                characters: "",
                ignoring: "",
                modifiers: MOD_COMMAND,
            },
            Case {
                key: Key::Space,
                key_code: 0x31,
                characters: " ",
                ignoring: " ",
                modifiers: 0,
            },
            Case {
                key: Key::UpArrow,
                key_code: 0x7E,
                characters: "\u{F700}",
                ignoring: "\u{F700}",
                modifiers: 0,
            },
            Case {
                key: Key::DownArrow,
                key_code: 0x7D,
                characters: "\u{F701}",
                ignoring: "\u{F701}",
                modifiers: 0,
            },
            Case {
                key: Key::LeftArrow,
                key_code: 0x7B,
                characters: "\u{F702}",
                ignoring: "\u{F702}",
                modifiers: 0,
            },
            Case {
                key: Key::RightArrow,
                key_code: 0x7C,
                characters: "\u{F703}",
                ignoring: "\u{F703}",
                modifiers: 0,
            },
            Case {
                key: Key::F1,
                key_code: 0x7A,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F2,
                key_code: 0x78,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F3,
                key_code: 0x63,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F4,
                key_code: 0x76,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F5,
                key_code: 0x60,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F6,
                key_code: 0x61,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F7,
                key_code: 0x62,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F8,
                key_code: 0x64,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F9,
                key_code: 0x65,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F10,
                key_code: 0x6D,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F11,
                key_code: 0x67,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F12,
                key_code: 0x6F,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F13,
                key_code: 0x69,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F14,
                key_code: 0x6B,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F15,
                key_code: 0x71,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F16,
                key_code: 0x6A,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F17,
                key_code: 0x40,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F18,
                key_code: 0x4F,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F19,
                key_code: 0x50,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::F20,
                key_code: 0x5A,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            // F21–F24, and the PC keys below, have no Apple virtual key code.
            // A PC keyboard surfaces them as Cocoa function-key characters.
            typed(Key::F21, "\u{F718}"),
            typed(Key::F22, "\u{F719}"),
            typed(Key::F23, "\u{F71A}"),
            typed(Key::F24, "\u{F71B}"),
            Case {
                key: Key::Insert,
                key_code: 0x72,
                characters: "\u{F727}",
                ignoring: "\u{F727}",
                modifiers: 0,
            },
            Case {
                key: Key::Home,
                key_code: 0x73,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::End,
                key_code: 0x77,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::PageUp,
                key_code: 0x74,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            Case {
                key: Key::PageDown,
                key_code: 0x79,
                characters: "",
                ignoring: "",
                modifiers: 0,
            },
            typed(Key::ScrollLock, "\u{F72F}"),
            typed(Key::Pause, "\u{F730}"),
            typed(Key::SysReq, "\u{F731}"),
            typed(Key::Stop, "\u{F734}"),
            typed(Key::Menu, "\u{F735}"),
            typed(Key::Back, "\u{F748}"),
            typed(Key::A, "a"),
            typed(Key::B, "b"),
            typed(Key::C, "c"),
            typed(Key::D, "d"),
            typed(Key::E, "e"),
            typed(Key::F, "f"),
            typed(Key::G, "g"),
            typed(Key::H, "h"),
            typed(Key::I, "i"),
            typed(Key::J, "j"),
            typed(Key::K, "k"),
            typed(Key::L, "l"),
            typed(Key::M, "m"),
            typed(Key::N, "n"),
            typed(Key::O, "o"),
            typed(Key::P, "p"),
            typed(Key::Q, "q"),
            typed(Key::R, "r"),
            typed(Key::S, "s"),
            typed(Key::T, "t"),
            typed(Key::U, "u"),
            typed(Key::V, "v"),
            typed(Key::W, "w"),
            typed(Key::X, "x"),
            typed(Key::Y, "y"),
            typed(Key::Z, "z"),
            typed(Key::Digit0, "0"),
            typed(Key::Digit1, "1"),
            typed(Key::Digit2, "2"),
            typed(Key::Digit3, "3"),
            typed(Key::Digit4, "4"),
            typed(Key::Digit5, "5"),
            typed(Key::Digit6, "6"),
            typed(Key::Digit7, "7"),
            typed(Key::Digit8, "8"),
            typed(Key::Digit9, "9"),
            typed(Key::Circumflex, "^"),
            typed(Key::Exclamation, "!"),
            typed(Key::DoubleQuote, "\""),
            typed(Key::Hash, "#"),
            typed(Key::Dollar, "$"),
            typed(Key::Percent, "%"),
            typed(Key::Ampersand, "&"),
            typed(Key::Underscore, "_"),
            typed(Key::OpenParen, "("),
            typed(Key::CloseParen, ")"),
            typed(Key::Asterisk, "*"),
            typed(Key::Plus, "+"),
            typed(Key::Pipe, "|"),
            typed(Key::HyphenMinus, "-"),
            typed(Key::OpenCurlyBracket, "{"),
            typed(Key::CloseCurlyBracket, "}"),
            typed(Key::Tilde, "~"),
            typed(Key::Colon, ":"),
            typed(Key::Semicolon, ";"),
            typed(Key::LessThan, "<"),
            typed(Key::Equals, "="),
            typed(Key::GreaterThan, ">"),
            typed(Key::QuestionMark, "?"),
            typed(Key::At, "@"),
            typed(Key::Comma, ","),
            typed(Key::Period, "."),
            typed(Key::Slash, "/"),
            typed(Key::BackQuote, "`"),
            typed(Key::OpenBracket, "["),
            typed(Key::BackSlash, "\\"),
            typed(Key::CloseBracket, "]"),
            typed(Key::Quote, "'"),
        ]
    }

    #[test]
    fn every_slint_key_has_an_appkit_source() {
        // Slint 1.18.1 publishes 123 `Key` variants. Adding one without a row
        // fails here; the rows themselves are checked against `Key`'s scalar.
        let cases = cases();
        assert_eq!(cases.len(), 123);
        let mut seen = std::collections::BTreeSet::new();
        for case in &cases {
            let expected: SharedString = case.key.into();
            let got = appkit_key_text(event(case));
            assert_eq!(got.as_deref(), Some(expected.as_str()), "{}", expected);
            assert!(
                seen.insert(expected.to_string()),
                "two sources produce {expected}"
            );
        }
        assert_eq!(seen.len(), 123);
    }

    #[test]
    fn command_shortcut_uses_the_unmodified_key() {
        let text = appkit_key_text(AppKitKey {
            key_code: 0x08, // kVK_ANSI_C
            characters: "c",
            characters_ignoring_modifiers: "c",
            modifiers: MOD_COMMAND,
        });
        assert_eq!(text.as_deref(), Some("c"));

        // ⌘⇧C still names the key `c`, not the shifted glyph.
        let text = appkit_key_text(AppKitKey {
            key_code: 0x08,
            characters: "C",
            characters_ignoring_modifiers: "c",
            modifiers: MOD_COMMAND | MOD_SHIFT,
        });
        assert_eq!(text.as_deref(), Some("c"));
    }

    #[test]
    fn shift_tab_is_backtab_and_return_is_line_feed() {
        let text = appkit_key_text(AppKitKey {
            key_code: 0,
            characters: "\u{19}",
            characters_ignoring_modifiers: "\t",
            modifiers: 0,
        });
        assert_eq!(text.as_deref(), Some("\u{19}"));

        let text = appkit_key_text(AppKitKey {
            key_code: 0x4C, // keypad Enter
            characters: "\r",
            characters_ignoring_modifiers: "\r",
            modifiers: 0,
        });
        assert_eq!(text.as_deref(), Some("\n"));
    }

    #[test]
    fn volume_and_empty_events_are_not_keys() {
        assert!(
            appkit_key_text(AppKitKey {
                key_code: 0x48, // Volume Up
                characters: "",
                characters_ignoring_modifiers: "",
                modifiers: 0,
            })
            .is_none()
        );
        assert!(
            appkit_key_text(AppKitKey {
                key_code: 0,
                characters: "",
                characters_ignoring_modifiers: "",
                modifiers: 0,
            })
            .is_none()
        );
    }

    #[test]
    fn utf16_selection_becomes_a_byte_range() {
        // U+1F600 is one scalar, two UTF-16 units, four UTF-8 bytes.
        assert_eq!(utf16_selection_to_utf8("😀a", 0, 2), Some(0..4));
        assert_eq!(utf16_selection_to_utf8("😀a", 2, 3), Some(4..5));
        assert_eq!(utf16_selection_to_utf8("あ", 0, 1), Some(0..3));
        assert_eq!(utf16_selection_to_utf8("あ", -1, -1), None);
        assert_eq!(utf16_selection_to_utf8("a", 0, 4), None);
    }

    struct WinCase {
        key: Key,
        virtual_key: u16,
        character: &'static str,
        shift: bool,
        control: bool,
    }

    fn win_event(case: &WinCase) -> VirtualKeyEvent<'static> {
        VirtualKeyEvent {
            virtual_key: case.virtual_key,
            character: case.character,
            shift: case.shift,
            control: case.control,
        }
    }

    fn vk(key: Key, virtual_key: u16) -> WinCase {
        WinCase {
            key,
            virtual_key,
            character: "",
            shift: false,
            control: false,
        }
    }

    fn vk_shift(key: Key, virtual_key: u16) -> WinCase {
        WinCase {
            key,
            virtual_key,
            character: "",
            shift: true,
            control: false,
        }
    }

    fn glyph(key: Key, character: &'static str) -> WinCase {
        WinCase {
            key,
            virtual_key: 0,
            character,
            shift: false,
            control: false,
        }
    }

    /// One WinUI source for every [`Key`] variant in Slint 1.18.1.
    fn win_cases() -> Vec<WinCase> {
        vec![
            vk(Key::Backspace, 0x08),
            vk(Key::Tab, 0x09),
            vk(Key::Return, 0x0D),
            vk(Key::Escape, 0x1B),
            vk_shift(Key::Backtab, 0x09),
            vk(Key::Delete, 0x2E),
            vk(Key::Shift, 0xA0),
            vk(Key::Control, 0xA2),
            vk(Key::Alt, 0xA4),
            vk(Key::AltGr, 0xA5),
            vk(Key::CapsLock, 0x14),
            vk(Key::ShiftR, 0xA1),
            vk(Key::ControlR, 0xA3),
            vk(Key::Meta, 0x5B),
            vk(Key::MetaR, 0x5C),
            vk(Key::Space, 0x20),
            vk(Key::UpArrow, 0x26),
            vk(Key::DownArrow, 0x28),
            vk(Key::LeftArrow, 0x25),
            vk(Key::RightArrow, 0x27),
            vk(Key::F1, 0x70),
            vk(Key::F2, 0x71),
            vk(Key::F3, 0x72),
            vk(Key::F4, 0x73),
            vk(Key::F5, 0x74),
            vk(Key::F6, 0x75),
            vk(Key::F7, 0x76),
            vk(Key::F8, 0x77),
            vk(Key::F9, 0x78),
            vk(Key::F10, 0x79),
            vk(Key::F11, 0x7A),
            vk(Key::F12, 0x7B),
            vk(Key::F13, 0x7C),
            vk(Key::F14, 0x7D),
            vk(Key::F15, 0x7E),
            vk(Key::F16, 0x7F),
            vk(Key::F17, 0x80),
            vk(Key::F18, 0x81),
            vk(Key::F19, 0x82),
            vk(Key::F20, 0x83),
            vk(Key::F21, 0x84),
            vk(Key::F22, 0x85),
            vk(Key::F23, 0x86),
            vk(Key::F24, 0x87),
            vk(Key::Insert, 0x2D),
            vk(Key::Home, 0x24),
            vk(Key::End, 0x23),
            vk(Key::PageUp, 0x21),
            vk(Key::PageDown, 0x22),
            vk(Key::ScrollLock, 0x91),
            vk(Key::Pause, 0x13),
            vk(Key::SysReq, 0x2C),
            vk(Key::Stop, 0xB2),
            vk(Key::Menu, 0x5D),
            vk(Key::Back, 0xA6),
            vk(Key::A, 0x41),
            vk(Key::B, 0x42),
            vk(Key::C, 0x43),
            vk(Key::D, 0x44),
            vk(Key::E, 0x45),
            vk(Key::F, 0x46),
            vk(Key::G, 0x47),
            vk(Key::H, 0x48),
            vk(Key::I, 0x49),
            vk(Key::J, 0x4A),
            vk(Key::K, 0x4B),
            vk(Key::L, 0x4C),
            vk(Key::M, 0x4D),
            vk(Key::N, 0x4E),
            vk(Key::O, 0x4F),
            vk(Key::P, 0x50),
            vk(Key::Q, 0x51),
            vk(Key::R, 0x52),
            vk(Key::S, 0x53),
            vk(Key::T, 0x54),
            vk(Key::U, 0x55),
            vk(Key::V, 0x56),
            vk(Key::W, 0x57),
            vk(Key::X, 0x58),
            vk(Key::Y, 0x59),
            vk(Key::Z, 0x5A),
            vk(Key::Digit0, 0x30),
            vk(Key::Digit1, 0x31),
            vk(Key::Digit2, 0x32),
            vk(Key::Digit3, 0x33),
            vk(Key::Digit4, 0x34),
            vk(Key::Digit5, 0x35),
            vk(Key::Digit6, 0x36),
            vk(Key::Digit7, 0x37),
            vk(Key::Digit8, 0x38),
            vk(Key::Digit9, 0x39),
            glyph(Key::Circumflex, "^"),
            glyph(Key::Exclamation, "!"),
            glyph(Key::DoubleQuote, "\""),
            glyph(Key::Hash, "#"),
            glyph(Key::Dollar, "$"),
            glyph(Key::Percent, "%"),
            glyph(Key::Ampersand, "&"),
            glyph(Key::Underscore, "_"),
            glyph(Key::OpenParen, "("),
            glyph(Key::CloseParen, ")"),
            vk(Key::Asterisk, 0x6A),
            vk(Key::Plus, 0x6B),
            glyph(Key::Pipe, "|"),
            vk(Key::HyphenMinus, 0xBD),
            glyph(Key::OpenCurlyBracket, "{"),
            glyph(Key::CloseCurlyBracket, "}"),
            glyph(Key::Tilde, "~"),
            glyph(Key::Colon, ":"),
            vk(Key::Semicolon, 0xBA),
            glyph(Key::LessThan, "<"),
            vk(Key::Equals, 0xBB),
            glyph(Key::GreaterThan, ">"),
            glyph(Key::QuestionMark, "?"),
            glyph(Key::At, "@"),
            vk(Key::Comma, 0xBC),
            vk(Key::Period, 0xBE),
            vk(Key::Slash, 0xBF),
            vk(Key::BackQuote, 0xC0),
            vk(Key::OpenBracket, 0xDB),
            vk(Key::BackSlash, 0xDC),
            vk(Key::CloseBracket, 0xDD),
            vk(Key::Quote, 0xDE),
        ]
    }

    #[test]
    fn every_slint_key_has_a_virtual_key_source() {
        let cases = win_cases();
        assert_eq!(cases.len(), 123);
        let mut seen = std::collections::BTreeSet::new();
        for case in &cases {
            let expected: SharedString = case.key.into();
            let got = virtual_key_text(win_event(case)).map(|ch| ch.to_string());
            assert_eq!(got.as_deref(), Some(expected.as_str()), "{expected}");
            assert!(
                seen.insert(expected.to_string()),
                "two sources produce {expected}"
            );
        }
        assert_eq!(seen.len(), 123);
    }

    #[test]
    fn virtual_key_command_skips_printable_keys() {
        assert_eq!(virtual_key_command(0x09, true), Some('\u{19}'));
        assert_eq!(virtual_key_command(0x70, false), Some('\u{F704}'));
        assert!(virtual_key_command(0x41, false).is_none());
        assert!(virtual_key_command(0x01, false).is_none());
    }

    #[test]
    fn control_shortcut_and_shifted_digit_use_the_right_glyph() {
        let text = virtual_key_text(VirtualKeyEvent {
            virtual_key: 0x43, // C
            character: "\u{3}",
            shift: false,
            control: true,
        });
        assert_eq!(text, Some('c'));

        // The layout's character wins over the unshifted digit.
        let text = virtual_key_text(VirtualKeyEvent {
            virtual_key: 0x31,
            character: "!",
            shift: true,
            control: false,
        });
        assert_eq!(text, Some('!'));

        assert!(
            virtual_key_text(VirtualKeyEvent {
                virtual_key: 0,
                character: "あいう",
                shift: false,
                control: false,
            })
            .is_none()
        );
    }
}
