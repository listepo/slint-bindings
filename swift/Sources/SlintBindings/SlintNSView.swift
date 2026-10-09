// AppKit view that presents a SlintHost's frames and feeds it input.
// M1 path: CPU frames as CGImage layer contents. M3 swaps the layer for a
// CAMetalLayer the GPU renderer draws into; the input half stays.

import AppKit
import QuartzCore

@MainActor
public final class SlintNSView: NSView {
    public private(set) var host: SlintHost?
    public private(set) var lastError: SlintError?
    private var displayLink: CADisplayLink?
    private var trackingArea: NSTrackingArea?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Top-left keeps a frame that is one size behind the bounds where it is,
        // instead of stretching it across the view until the new pixels arrive.
        layer?.contentsGravity = .topLeft
        layer?.magnificationFilter = .nearest
        do {
            host = try SlintHost(pixelWidth: 1, pixelHeight: 1, scale: 1)
        } catch let error as SlintError {
            lastError = error
        } catch {
            lastError = SlintError(description: "\(error)")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // Slint's origin is the top-left corner, so a flipped view needs no y conversion.
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        // Frames follow the display this view is on, including ProMotion rates.
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        syncSize()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSize()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSize()
    }

    private func syncSize() {
        let scale = window?.backingScaleFactor ?? 1
        layer?.contentsScale = scale
        let w = Int((bounds.width * scale).rounded())
        let h = Int((bounds.height * scale).rounded())
        do {
            try host?.resize(pixelWidth: w, pixelHeight: h, scale: scale)
        } catch let error as SlintError {
            lastError = error
            return
        } catch {
            lastError = SlintError(description: "\(error)")
            return
        }
        // The layer adopts the new bounds in this call. Present before returning so
        // the displayed image matches them; the display link only has to catch animations.
        present()
    }

    @objc private func step(_ link: CADisplayLink) {
        SlintHost.tick()
        present()
    }

    private func present() {
        guard let host else { return }
        do {
            if let image = try host.renderIfNeeded().image {
                layer?.contents = image
            }
        } catch let error as SlintError {
            lastError = error
        } catch {
            lastError = SlintError(description: "\(error)")
        }
    }

    // MARK: Pointer

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func point(_ event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }

    public override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        host?.pointerMoved(x: p.x, y: p.y)
    }

    public override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    public override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    public override func otherMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        press(event, .left)
    }

    public override func mouseUp(with event: NSEvent) { release(event, .left) }
    public override func rightMouseDown(with event: NSEvent) { press(event, .right) }
    public override func rightMouseUp(with event: NSEvent) { release(event, .right) }
    public override func otherMouseDown(with event: NSEvent) { press(event, .middle) }
    public override func otherMouseUp(with event: NSEvent) { release(event, .middle) }

    public override func mouseExited(with event: NSEvent) {
        host?.pointerExited()
    }

    public override func scrollWheel(with event: NSEvent) {
        let p = point(event)
        // Precise devices report points. A mouse wheel reports lines; Slint wants points.
        let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        host?.pointerScrolled(
            x: p.x, y: p.y,
            dx: event.scrollingDeltaX * unit,
            dy: event.scrollingDeltaY * unit
        )
    }

    private func press(_ event: NSEvent, _ button: SlintPointerButton) {
        let p = point(event)
        host?.pointerPressed(x: p.x, y: p.y, button: button)
    }

    private func release(_ event: NSEvent, _ button: SlintPointerButton) {
        let p = point(event)
        host?.pointerReleased(x: p.x, y: p.y, button: button)
    }

    // MARK: Keyboard
    // TODO(M2): adopt NSTextInputClient so IME composition (CJK, dead keys,
    // the emoji picker) reaches Slint as preedit text instead of raw keys.

    public override func keyDown(with event: NSEvent) {
        guard let text = SlintKeys.text(for: event) else { return super.keyDown(with: event) }
        if event.isARepeat {
            host?.keyRepeated(text)
        } else {
            host?.keyPressed(text)
        }
    }

    public override func keyUp(with event: NSEvent) {
        guard let text = SlintKeys.text(for: event) else { return super.keyUp(with: event) }
        host?.keyReleased(text)
    }

    public override func becomeFirstResponder() -> Bool {
        host?.focusChanged(true)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        host?.focusChanged(false)
        return true
    }

    isolated deinit {
        displayLink?.invalidate()
    }
}

/// AppKit key events to Slint key text. Slint's special keys share AppKit's
/// function-key code points (arrows are U+F700…), so most characters pass
/// through; only the few that differ are remapped.
enum SlintKeys {
    private static let remap: [Character: String] = [
        "\r": "\n",          // Return
        "\u{7F}": "\u{08}",  // AppKit's Backspace is DEL; Slint's is BS
        "\u{F728}": "\u{7F}", // Forward delete
        "\u{19}": "\t",      // Shift-Tab arrives as BACKTAB
    ]

    static func text(for event: NSEvent) -> String? {
        let produced = event.characters
        let unmodified = event.charactersIgnoringModifiers
        // Remap the characters that were typed. Shift-Tab arrives as BACKTAB in
        // `characters`, while `charactersIgnoringModifiers` is a plain Tab, so
        // looking there first never sees the entry.
        if let produced, let first = produced.first, let mapped = remap[first] { return mapped }
        // Modified shortcuts (⌘C) need the unmodified key; plain typing needs the produced character.
        if event.modifierFlags.contains(.command) { return unmodified }
        return produced ?? unmodified
    }
}
