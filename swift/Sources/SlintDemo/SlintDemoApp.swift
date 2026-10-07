// Demo app: a SwiftUI pane and an embedded Slint pane sharing one model.

import AppKit
import SlintBindings
import SwiftUI

@MainActor
@Observable
final class DemoModel {
    var name = "Ivan"
    var submissions: [String] = []
}

@main
struct SlintDemoApp: App {
    @State private var model = DemoModel()

    init() {
        // `swift run` starts a bare process; make it a regular app with a Dock icon and focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("Slint Bindings demo") {
            ContentView(model: model)
        }
    }
}

struct ContentView: View {
    @Bindable var model: DemoModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SwiftUI").font(.headline)
                TextField("Name pushed into Slint", text: $model.name)
                Text("Submitted from Slint").font(.subheadline)
                List(Array(model.submissions.enumerated()), id: \.offset) { _, name in
                    Text(name)
                }
            }
            .padding()
            .frame(width: 240)

            Divider()

            SlintDemoView(name: model.name) { submitted in
                model.submissions.append(submitted)
            }
            .frame(minWidth: 320, minHeight: 220)
        }
    }
}
