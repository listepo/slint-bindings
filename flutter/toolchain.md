# Toolchain

Программы проекта и прямые пакеты из манифестов.

## Программы

| Программа | Как ставить | Зачем здесь | Источник |
| --- | --- | --- | --- |
| mise | brew / curl, затем `mise install` | Пины версий инструментов | https://github.com/jdx/mise |
| flutter | mise | UI / тесты | https://github.com/flutter/flutter |
| just | mise | Рецепты команд | https://github.com/casey/just |
| hugo | mise | Сайт документации | https://github.com/gohugoio/hugo |
| rustc | rustup / системный | Компилятор Rust | https://github.com/rust-lang/rust |
| cargo | вместе с rustc | Сборка и зависимости Rust | https://github.com/rust-lang/cargo |

## cargo

Slint crates pinned exactly at **1.18.1** in the root `Cargo.toml` `[workspace.dependencies]` (and mirrored in `slint_build` / `slint_compiler` — see AGENTS.md).


| Пакет | Где | Источник | Зачем здесь |
| --- | --- | --- | --- |
| i-slint-backend-testing | локально | https://crates.io/crates/i-slint-backend-testing | Зависимость Rust |
| i-slint-compiler | локально | https://crates.io/crates/i-slint-compiler | Зависимость Rust |
| i-slint-core | локально | https://crates.io/crates/i-slint-core | Зависимость Rust |
| i-slint-renderer-skia | локально | https://crates.io/crates/i-slint-renderer-skia | Зависимость Rust |
| raw-window-handle | локально | https://github.com/rust-windowing/raw-window-handle | `slint-skia-ffi`: the window-handle traits in Skia's `Surface` API (0.6, `std`; approved by the creator) |
| serde_json | локально | https://crates.io/crates/serde_json | JSON |
| slint | локально | https://crates.io/crates/slint | Зависимость Rust |
| slint-interpreter | локально | https://crates.io/crates/slint-interpreter | Зависимость Rust |
| spin_on | локально | https://crates.io/crates/spin_on | Зависимость Rust |
| windows | локально | https://github.com/microsoft/windows-rs | `slint-skia-ffi`, Windows only: D3D12 device, queue and shared texture + NT handle (0.62; approved by the creator) |

## pub

| Пакет | Где | Источник | Зачем здесь |
| --- | --- | --- | --- |
| bazel_worker | локально | https://pub.dev/packages/bazel_worker | Пакет Dart/Flutter |
| build | локально | https://pub.dev/packages/build | Пакет Dart/Flutter |
| build_runner | локально | https://pub.dev/packages/build_runner | Пакет Dart/Flutter |
| code_assets | локально | https://pub.dev/packages/code_assets | Пакет Dart/Flutter |
| dart_style | локально | https://pub.dev/packages/dart_style | Пакет Dart/Flutter |
| ffi | локально | https://pub.dev/packages/ffi | Пакет Dart/Flutter |
| ffigen | локально | https://pub.dev/packages/ffigen | Пакет Dart/Flutter |
| flutter | локально | https://pub.dev/packages/flutter | Пакет Dart/Flutter |
| flutter_lints | локально | https://pub.dev/packages/flutter_lints | Пакет Dart/Flutter |
| flutter_test | локально | https://pub.dev/packages/flutter_test | Пакет Dart/Flutter |
| hooks | локально | https://pub.dev/packages/hooks | Пакет Dart/Flutter |
| lints | локально | https://pub.dev/packages/lints | Пакет Dart/Flutter |
| melos | локально | https://pub.dev/packages/melos | Пакет Dart/Flutter |
| meta | локально | https://pub.dev/packages/meta | Пакет Dart/Flutter |
| native_toolchain_c | локально | https://pub.dev/packages/native_toolchain_c | Пакет Dart/Flutter |
| path | локально | https://pub.dev/packages/path | Пакет Dart/Flutter |
| patrol_finders | локально | https://pub.dev/packages/patrol_finders | Пакет Dart/Flutter |
| pub_semver | локально | https://pub.dev/packages/pub_semver | Пакет Dart/Flutter |
| record_use | локально | https://pub.dev/packages/record_use | Пакет Dart/Flutter |
| slint | локально | https://pub.dev/packages/slint | Пакет Dart/Flutter |
| slint_build | локально | https://pub.dev/packages/slint_build | Пакет Dart/Flutter |
| slint_compiler | локально | https://pub.dev/packages/slint_compiler | Пакет Dart/Flutter |
| slint_generator | локально | https://pub.dev/packages/slint_generator | Пакет Dart/Flutter |
| slint_interpreter | локально | https://pub.dev/packages/slint_interpreter | Пакет Dart/Flutter |
| slint_patrol | локально | https://pub.dev/packages/slint_patrol | Пакет Dart/Flutter |
| slint_skia | локально | https://pub.dev/packages/slint_skia | Пакет Dart/Flutter |
| slint_testing | локально | https://pub.dev/packages/slint_testing | Пакет Dart/Flutter |
| test | локально | https://pub.dev/packages/test | Пакет Dart/Flutter |
| todo_shared | локально | https://pub.dev/packages/todo_shared | Пакет Dart/Flutter |
| yaml | локально | https://pub.dev/packages/yaml | Пакет Dart/Flutter |
