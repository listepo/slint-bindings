# Recipes for slint-bindings. Run inside the mise environment (`mise install` first).

header_path := "swift/Sources/CSlintBindings/slint_bindings.h"

default: check

# Everything CI runs on macOS.
check: fmt-check clippy test header-check swift-build

fmt-check:
    cargo fmt --check

clippy:
    cargo clippy --all-targets -- -D warnings

test:
    cargo nextest run
    dunnage run target || test $? -eq 2

# Regenerate the C header both hosts consume.
header:
    cbindgen --config crates/slint-bindings-ffi/cbindgen.toml --crate slint-bindings-ffi --output {{header_path}} crates/slint-bindings-ffi

# Fail when the committed header no longer matches the Rust source.
header-check:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    cbindgen --config crates/slint-bindings-ffi/cbindgen.toml --crate slint-bindings-ffi --output "$tmp" crates/slint-bindings-ffi
    diff -u {{header_path}} "$tmp"

swift-build:
    cargo build -p slint-bindings-ffi
    cd swift && swift build

# Opens the SwiftUI demo window.
swift-run: swift-build
    cd swift && swift run SlintDemo

# On Windows: the DLL the WinUI projects load.
windows-dll:
    cargo build -p slint-bindings-ffi --target x86_64-pc-windows-msvc
