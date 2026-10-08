// Swift owner of one embedded Slint component (the `sb_*` C ABI).
// Main-actor only: Slint objects are single-threaded and the Rust side refuses
// nothing on its own, so the isolation is what keeps calls on one thread.

import CSlintBindings
import CoreGraphics
import Foundation

/// A failure reported by the Rust side.
public struct SlintError: Error, CustomStringConvertible {
    public let description: String

    static func last() -> SlintError {
        SlintError(description: sb_last_error().map { String(cString: $0) } ?? "unknown error")
    }
}

/// Mouse buttons, in the order the C ABI expects.
public enum SlintPointerButton: UInt8 {
    case left = 0
    case right = 1
    case middle = 2
}

@MainActor
private final class SubmittedBox {
    let handler: @MainActor (String) -> Void
    init(_ handler: @escaping @MainActor (String) -> Void) { self.handler = handler }
}

/// The demo form, rendered on the CPU into a buffer this object owns.
@MainActor
public final class SlintHost {
    private let handle: OpaquePointer
    private var buffer: [UInt8] = []
    private var submitted: Unmanaged<SubmittedBox>?
    public private(set) var pixelWidth = 1
    public private(set) var pixelHeight = 1

    /// Creates the component at `width`×`height` physical pixels.
    public init(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) throws {
        guard let handle = sb_demo_new(UInt32(max(pixelWidth, 1)), UInt32(max(pixelHeight, 1)), Float(scale)) else {
            throw SlintError.last()
        }
        self.handle = handle
        self.pixelWidth = max(pixelWidth, 1)
        self.pixelHeight = max(pixelHeight, 1)
    }

    isolated deinit {
        // Clear the callback first so Rust never calls into a released box.
        sb_demo_on_submitted(handle, nil, nil)
        submitted?.release()
        sb_host_free(handle)
    }

    /// Advances Slint timers and animations for every host in the process.
    public static func tick() {
        sb_tick()
    }

    public func resize(pixelWidth: Int, pixelHeight: Int, scale: CGFloat) throws {
        let (w, h) = (max(pixelWidth, 1), max(pixelHeight, 1))
        guard sb_host_resize(handle, UInt32(w), UInt32(h), Float(scale)) else { throw SlintError.last() }
        self.pixelWidth = w
        self.pixelHeight = h
    }

    /// Renders if the scene changed. `image` is nil when the previous frame is still current.
    public func renderIfNeeded() throws -> (image: CGImage?, animating: Bool) {
        let len = sb_host_frame_len(handle)
        if buffer.count != len {
            buffer = [UInt8](repeating: 0, count: len)
        }
        let frame = buffer.withUnsafeMutableBufferPointer { sb_host_render(handle, $0.baseAddress, $0.count) }
        if frame.failed != 0 { throw SlintError.last() }
        guard frame.redrawn != 0 else { return (nil, frame.animating != 0) }
        return (makeImage(), frame.animating != 0)
    }

    private func makeImage() -> CGImage? {
        // Copy: CoreAnimation may read the image after the next render reuses `buffer`.
        guard let provider = CGDataProvider(data: Data(buffer) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerPixel = 4
        return CGImage(
            width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bitsPerPixel: 8 * bytesPerPixel, bytesPerRow: pixelWidth * bytesPerPixel,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    // Input. Positions are logical points from the top-left corner, as AppKit
    // reports them in a flipped view.

    public func pointerMoved(x: CGFloat, y: CGFloat) {
        _ = sb_host_pointer_moved(handle, Float(x), Float(y))
    }

    public func pointerPressed(x: CGFloat, y: CGFloat, button: SlintPointerButton) {
        _ = sb_host_pointer_pressed(handle, Float(x), Float(y), button.rawValue)
    }

    public func pointerReleased(x: CGFloat, y: CGFloat, button: SlintPointerButton) {
        _ = sb_host_pointer_released(handle, Float(x), Float(y), button.rawValue)
    }

    public func pointerExited() {
        _ = sb_host_pointer_exited(handle)
    }

    public func pointerScrolled(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
        _ = sb_host_pointer_scrolled(handle, Float(x), Float(y), Float(dx), Float(dy))
    }

    public func keyPressed(_ text: String) {
        _ = sb_host_key_pressed(handle, text)
    }

    public func keyReleased(_ text: String) {
        _ = sb_host_key_released(handle, text)
    }

    public func keyRepeated(_ text: String) {
        _ = sb_host_key_repeated(handle, text)
    }

    public func focusChanged(_ focused: Bool) {
        _ = sb_host_focus_changed(handle, focused)
    }

    // Demo component properties and callbacks. The Weft milestone replaces these
    // with a generic property bridge.

    public func setName(_ name: String) {
        sb_demo_set_name(handle, name)
    }

    public func onSubmitted(_ handler: @escaping @MainActor (String) -> Void) {
        let box = Unmanaged.passRetained(SubmittedBox(handler))
        sb_demo_on_submitted(handle, { userData, name in
            guard let userData, let name else { return }
            let text = String(cString: name)
            // Slint invokes callbacks synchronously while dispatching input, which
            // only ever happens from the main-actor methods above.
            MainActor.assumeIsolated {
                Unmanaged<SubmittedBox>.fromOpaque(userData).takeUnretainedValue().handler(text)
            }
        }, box.toOpaque())
        submitted?.release()
        submitted = box
    }
}
