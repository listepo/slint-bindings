# Toolchain

| Program | How to install | Why here | Source |
| --- | --- | --- | --- |
| rust (rustc, cargo, rustfmt, clippy) | mise (`mise.toml`, 1.99.0) | Builds the core and the C ABI | https://github.com/rust-lang/rust |
| cargo-nextest | mise (`cargo:cargo-nextest`) | Test runner (`just test`) | https://github.com/nextest-rs/nextest |
| just | mise | Recipes (`justfile`) | https://github.com/casey/just |
| cbindgen | global (`cargo install cbindgen`) | Generates the C header from the FFI crate (`just header`) | https://github.com/mozilla/cbindgen |
| Xcode (swift, SwiftPM) | Mac App Store | Builds the Swift package and the macOS demo | https://developer.apple.com/xcode/ |
| .NET SDK 10 | mise (`dotnet`, global) | Builds the WinUI projects (Windows only) | https://github.com/dotnet/sdk |
| dunnage | ketch | Post-test `target/` cleanup in `just test`; a no-op when missing | https://github.com/listepo/dunnage |

## cargo

| Package | Where | Source | Why here |
| --- | --- | --- | --- |
| slint | local | https://github.com/slint-ui/slint | UI runtime; software renderer and custom platform API |
| slint-build | local (build-dependency) | https://github.com/slint-ui/slint | Compiles the demo `.slint` ahead of time |
| i-slint-core | local | https://github.com/slint-ui/slint | Feature unification only: image and SVG decoding without a backend |
| thiserror | local | https://github.com/dtolnay/thiserror | Core error enum |

## NuGet

| Package | Where | Source | Why here |
| --- | --- | --- | --- |
| Microsoft.WindowsAppSDK | local (`windows/*.csproj`) | https://github.com/microsoft/WindowsAppSDK | WinUI 3 |

## SwiftPM

No external packages.
