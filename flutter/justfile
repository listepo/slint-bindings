# Workspace recipes. `just` lists them; `just <recipe>` runs one.
# Dart/Flutter go through mise; melos is a root dev dependency (no global
# install). Per-app recipes live in examples/*/justfile.

set shell := ["zsh", "-cu"]

dart := "mise exec -- dart"
melos := dart + " run melos run"

# List recipes.
default:
    @just --list --unsorted

# Resolve the whole pub workspace.
bootstrap:
    {{dart}} pub get

# dart analyze, per package.
analyze:
    {{melos}} analyze

# Dart formatting check (no writes).
format:
    {{melos}} format

# Rewrite every Dart file with dart format.
format-fix:
    {{melos}} format:fix

# All tests that run locally: Dart packages, then Flutter packages and examples/todo.
test:
    {{melos}} test

# dart test in the pure-Dart packages.
test-dart:
    {{melos}} test:dart

# flutter test in slint, slint_patrol, examples/todo (todo_skia excluded — compiles Skia).
test-flutter:
    {{melos}} test:flutter

# ui/*.slint → lib/*.g.dart in the examples.
codegen:
    {{melos}} codegen

# rustfmt every crate.
fmt:
    cargo fmt --all

# clippy every crate except slint-skia-ffi (it builds all of Skia).
clippy:
    cargo clippy --workspace --exclude slint-skia-ffi --all-targets

# Unused Rust dependencies (cargo-machete) and unused Dart declarations (dart_code_linter, advisory).
unused:
    {{melos}} deps:unused
    {{melos}} dart:unused

# What CI runs: analyze, cargo fmt --check, clippy, tests.
check:
    {{melos}} check

# Regenerate an FFI package's C header (cbindgen) and Dart bindings (ffigen) after a C ABI change.
# pkg: slint_interpreter | slint_testing | slint_skia
bindings pkg:
    cd packages/{{pkg}}/rust && cbindgen --output include/{{pkg}}_ffi.h
    cd packages/{{pkg}} && {{dart}} run ffigen --config ffigen.yaml

# Serve the docs site locally (http://localhost:1313).
docs-serve:
    mise exec -- hugo serve --source site

# Build the docs site into site/public (what the Pages workflow deploys).
docs-build:
    mise exec -- hugo --source site --minify
