// Headless e2e of the macOS host: the same hit targets as `ui/demo.slint`
// (name field center 160×64, Continue center 80×112, logical points).

import AppKit
@testable import SlintBindings
import Testing

@MainActor
struct HostE2E {
    private let field = CGPoint(x: 160, y: 64)
    private let button = CGPoint(x: 80, y: 112)

    @Test func firstFrameIsAnImageAndTheNextIsNot() throws {
        let host = try SlintHost(pixelWidth: 320, pixelHeight: 200, scale: 1)
        let first = try host.renderIfNeeded()
        #expect(first.image != nil)
        let second = try host.renderIfNeeded()
        #expect(second.image == nil)
    }

    @Test func typeAsciiThenContinueSubmitsTheName() throws {
        let host = try SlintHost(pixelWidth: 320, pixelHeight: 200, scale: 1)
        _ = try host.renderIfNeeded()
        host.focusChanged(true)
        click(host, field)
        for character in ["A", "d", "a"] {
            host.keyPressed(character)
            host.keyReleased(character)
        }
        var submitted: [String] = []
        host.onSubmitted { submitted.append($0) }
        click(host, button)
        #expect(submitted == ["Ada"])
    }

    @Test func sizedViewPresentsAFrame() {
        let view = SlintNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        #expect(view.lastError == nil)
        #expect(view.layer?.contents != nil)
        #expect(view.host?.pixelWidth == Int((320 * (window.backingScaleFactor)).rounded()))
    }

    private func click(_ host: SlintHost, _ point: CGPoint) {
        host.pointerMoved(x: point.x, y: point.y)
        host.pointerPressed(x: point.x, y: point.y, button: .left)
        host.pointerReleased(x: point.x, y: point.y, button: .left)
    }
}

@MainActor
struct KeyMapTests {
    @Test func typedCharactersAreRemapped() throws {
        #expect(try text("\r", ignoring: "\r") == "\n")
        #expect(try text("\u{7F}", ignoring: "\u{7F}") == "\u{08}")
        #expect(try text("\u{F728}", ignoring: "\u{F728}") == "\u{7F}")
        // Shift-Tab arrives as BACKTAB. That is Slint's Backtab, not Tab.
        #expect(try text("\u{19}", ignoring: "\t") == "\u{19}")
        #expect(try text("a", ignoring: "a") == "a")
    }

    @Test func commandShortcutUsesTheUnmodifiedKey() throws {
        let event = try #require(keyEvent(characters: "c", ignoring: "c", flags: .command))
        #expect(SlintKeys.text(for: event) == "c")
    }

    @Test func homeAndModifiersUseTheVirtualKeyCode() throws {
        let home = try #require(keyEvent(characters: "", ignoring: "", flags: [], keyCode: 0x73))
        #expect(SlintKeys.text(for: home) == "\u{F729}")
        let shift = try #require(keyEvent(characters: "", ignoring: "", flags: .shift, keyCode: 0x38))
        #expect(SlintKeys.text(for: shift) == "\u{10}")
    }

    private func text(_ characters: String, ignoring: String) throws -> String? {
        let event = try #require(keyEvent(characters: characters, ignoring: ignoring, flags: []))
        return SlintKeys.text(for: event)
    }

    private func keyEvent(
        characters: String,
        ignoring: String,
        flags: NSEvent.ModifierFlags,
        keyCode: UInt16 = 0
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: ignoring,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
