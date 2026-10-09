// SwiftUI wrapper: SwiftUI state in, Slint callbacks out.

import SwiftUI

/// The demo form as a SwiftUI view. `name` flows SwiftUI → Slint; submissions
/// flow back through `onSubmit`. Two-way binding of edits needs a Slint
/// `changed` callback per property, which the generic bridge (M5) generates.
public struct SlintDemoView: NSViewRepresentable {
    public var name: String
    public var onSubmit: @MainActor (String) -> Void

    public init(name: String, onSubmit: @escaping @MainActor (String) -> Void) {
        self.name = name
        self.onSubmit = onSubmit
    }

    public final class Coordinator {
        // Push only real changes, so a SwiftUI re-render does not overwrite
        // what the user just typed inside Slint.
        var lastPushedName: String?
        var onSubmit: (@MainActor (String) -> Void)?
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> SlintNSView {
        let view = SlintNSView(frame: .zero)
        view.host?.onSubmitted { name in
            context.coordinator.onSubmit?(name)
        }
        updateNSView(view, context: context)
        return view
    }

    public func updateNSView(_ view: SlintNSView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        if context.coordinator.lastPushedName != name {
            view.host?.setName(name)
            context.coordinator.lastPushedName = name
        }
    }
}
