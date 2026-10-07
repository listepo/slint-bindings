// swift-tools-version: 6.0
// SwiftPM package for the macOS host: a C module over the Rust static library,
// an AppKit/SwiftUI wrapper, and a demo app.

import Foundation
import PackageDescription

// M1 links Cargo's debug output directly (`just swift-build` builds it first).
// M4 replaces this with an XCFramework binary target, which SwiftPM consumers
// outside this repository need anyway: unsafe flags are refused in dependencies.
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let rustStaticLib = packageDir
    .appendingPathComponent("../target/debug/libslint_bindings_ffi.a")
    .standardizedFileURL.path

let package = Package(
    name: "SlintBindings",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SlintBindings", targets: ["SlintBindings"]),
        .executable(name: "SlintDemo", targets: ["SlintDemo"]),
    ],
    targets: [
        .systemLibrary(name: "CSlintBindings", path: "Sources/CSlintBindings"),
        .target(
            name: "SlintBindings",
            dependencies: ["CSlintBindings"],
            linkerSettings: [
                .unsafeFlags([rustStaticLib]),
                // What the Rust side (fontique, Slint's image and text stack) links against.
                .linkedFramework("AppKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(name: "SlintDemo", dependencies: ["SlintBindings"]),
    ]
)
