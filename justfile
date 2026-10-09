# Recipes for slint-bindings. Run inside the mise environment (`mise install` first).

header_path := "swift/Sources/CSlintBindings/slint_bindings.h"

default: check

# Everything CI runs on macOS. Cleanup is last so it does not invalidate the Swift link.
check: fmt-check clippy nextest header-check swift-build swift-test tidy

fmt-check:
    cargo fmt --check

clippy:
    cargo clippy --all-targets -- -D warnings

nextest:
    cargo nextest run

# Tests, then shrink `target/` once nothing still has to link against it.
test: nextest tidy

tidy:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v dunnage >/dev/null || exit 0
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

# The static library both SwiftPM products link. Built once per `just` invocation.
swift-lib:
    cargo rustc -p slint-bindings-ffi --crate-type staticlib

swift-build: swift-lib
    cd swift && swift build

swift-test: swift-lib
    cd swift && swift test

# Opens the SwiftUI demo window.
swift-run: swift-build
    cd swift && swift run SlintDemo

# On Windows: the DLL the WinUI projects load.
windows-dll:
    cargo rustc -p slint-bindings-ffi --crate-type cdylib --target x86_64-pc-windows-msvc
