# Agent notes for slint_dart

Slint ↔ Flutter integration: a melos monorepo on top of a pub workspace
(root `pubspec.yaml`) plus a Cargo workspace (root `Cargo.toml`). Packages
live under `packages/`, apps under `examples/`. Read the root `README.md`
for the package/crate layout and architecture, `CONTRIBUTING.md` for the
workflow, and each package's `README.md` for its details. **Every package
has its own `AGENTS.md`** with the invariants and traps local to it — read
`packages/<pkg>/AGENTS.md` before editing that package. This file holds what
is cross-cutting: commands, the invariants that span packages, and the
conventions.

## Product requirements

Product rules, not implementation details: a change that breaks one is
wrong even when every test passes.

- **Loading a `.slint` in code always gives back its generated Dart
  wrapper.** `SlintComponent.load(path)` returns the typed class
  build_runner generated from that file (`TodoApp`), as do a generated
  `load`/`create`. Nothing compiles a `.slint` no wrapper was generated
  from, and nothing hands back an untyped handle — `SlintComponent.loadAsset`
  was removed for exactly that. A backend without a factory (`slint_skia`)
  still ends in the wrapper: the app passes its component to the generated
  constructor, `TodoApp(component)`.
- **Hand-written code never calls Slint by name.** No `getProperty('x')`,
  `setProperty`, `invoke`, `component['prop']`, or a callback registered by
  its string name — in apps, examples, their tests, or code samples in the
  docs. Properties and callbacks go through generated members
  (`app.todoModel`, `app.onAddTodo(...)`); only generated code (`*.g.dart`,
  `*.aot.g.dart`) spells Slint names. The dynamic layer under those members
  exists for the generated code: the backends implement it and test it in
  their own packages, nobody else calls it. Element *queries* in
  `slint_patrol`/`slint_testing` (`$.slint('Add')`, `slintById`) look up
  accessibility-tree nodes by label or id; they are not property access and
  stay.
- **The interpreter and AOT never intersect.** The build mode picks exactly
  one backend at codegen (`_useCompiled`): a release binary carries no
  interpreter path and no `.slint` text, a debug run never loads the AOT
  dylib, and neither backend calls into the other. They may share code and
  packages (`slint` core, the generator's schema, `slint-dart-core`,
  `slint_build`) as long as the sharing leaves that intact; a shared piece
  that makes one backend need the other at runtime is the wrong piece to
  share.

Where the name rule stops:

- **Backend packages test their dynamic layer by name** with inline
  sources (`slint_interpreter`, `slint_patrol`, `slint_testing`). That is the
  layer under test, so it is allowed there and only there; app-level
  behaviour is tested in an example through its generated wrapper — live
  with `slint_patrol` (`examples/todo/test/todo_patrol_test.dart`) and
  headless with `slint_testing`, whose `SlintTestApp` is a `SlintComponent`
  the wrapper wraps (`examples/todo/test/todo_headless_test.dart`).

## Toolchain and commands

Flutter and Dart run through mise; Rust is a plain rustup install. The
root `justfile` is the short form (`just` lists recipes: `analyze`, `test`,
`check`, `codegen`, `clippy`, `unused`, `bindings <pkg>`, ...);
`examples/todo/justfile` adds `build-macos`/`build-ios`/`build-android` and
`verify-treeshake`, `examples/todo_skia/justfile` the local `codegen` +
`analyze`. Underneath, melos is a root dev dependency, so nothing is
globally activated — run it as `mise exec -- dart run melos run <script>`:

| Script | What it does |
|---|---|
| `analyze` | `dart analyze .` in every package and example, one at a time. `slint_skia`'s ffigen bindings (unused, ~80 warnings over system headers) are excluded in its `analysis_options.yaml` and its `.pubignore`. Per package is the rule. |
| `format`, `format:fix` | `dart format --output=none --set-exit-if-changed .` (check only) and `dart format .` (rewrite). `format` is part of `check`. |
| `test` | `test:dart` then `test:flutter`. |
| `test:dart` | `dart test` in the pure-Dart packages with a `test/` dir (`slint_build`, `slint_compiler`, `slint_generator`, `slint_testing` — the last builds its crate through its hook). |
| `test:flutter` | `flutter test` in the Flutter packages with tests (`slint`, `slint_interpreter`, `slint_patrol`, `examples/todo`, `examples/todo_shared`). `examples/todo_skia` is excluded: its hook compiles all of Skia (not in default CI). |
| `codegen` | `dart run build_runner build --delete-conflicting-outputs` in every package that depends on `build_runner` (the examples): regenerates `lib/*.g.dart` from `ui/*.slint`. |
| `deps:unused`, `dart:unused` | `cargo machete` (unused Rust deps; no crate needs ignores) and `dart_code_linter check-unused-code` per package (advisory: builder/hook entry points show up as unused). Both need the tool installed — see `CONTRIBUTING.md`. |
| `rust:fmt`, `rust:clippy`, `rust:test` | `cargo fmt --all`; `cargo clippy --workspace --exclude slint-skia-ffi --all-targets`; `cargo test --workspace --exclude slint-skia-ffi`. |
| `check` | analyze, Dart format, `cargo fmt --check`, clippy, Rust tests, tests — what CI should run. |

The scripts are `dart run melos exec` invocations with filter flags rather
than `exec:`/`packageFilters:` — the former needs no global `melos`, the
latter prompts for a package unless `--no-select` is passed. Melos is pinned
to 7.x: 8.x wants `cli_util ^0.5` while `ffigen ^21` (a dev dependency of
the FFI packages, resolved workspace-wide) pins `^0.4`.

Direct commands, when you want one thing:

```bash
cd examples/todo && mise exec -- flutter test           # both backends' tests
cd examples/todo && mise exec -- flutter build macos --release   # e2e: codegen + cargo + link hook
cd examples/todo && mise exec -- flutter build ios --release --no-codesign
cd examples/todo && mise exec -- flutter build apk --release --target-platform android-arm64
cd packages/<pkg> && mise exec -- dart test              # a package's unit tests
cd packages/slint_patrol && mise exec -- flutter test    # live-component E2E tests
cd examples/todo && mise exec -- dart run build_runner build   # regenerate *.g.dart after editing a .slint
cd examples/todo_skia && mise exec -- dart run build_runner build && mise exec -- dart analyze .  # all that runs locally there
cargo fmt --all
cargo clippy --workspace --exclude slint-skia-ffi --all-targets
```

Keep `cargo fmt --all --check` and that clippy invocation clean. Lint levels
live in the root `Cargo.toml` `[workspace.lints.*]` tables; members opt in
with `[lints] workspace = true`. `slint-skia-ffi` is always excluded from
clippy/test/build — compiling it builds all of Skia (excluded from default
CI; only CI's `skia-*` jobs build it). `flutter run/build/test` in `examples/todo_skia` compiles Skia through
`slint_skia`'s hook — optional and expensive, not part of `melos run check`.
Local checks there are `build_runner` and `dart analyze`. FFI crates
allow `clippy::not_unsafe_ptr_arg_deref` at crate level: C ABI entry points
are never called from Rust, and each dereference is an explicit unsafe
block.

Regenerate FFI bindings only after changing a Rust C ABI:

```bash
cd packages/<pkg>/rust && cbindgen --output include/$(basename $PWD).h && cd .. && dart run ffigen --config ffigen.yaml
```

Generated files (`*.g.dart`, `*.aot.g.dart`, `bindings.g.dart`) are
committed. Regenerate them; never hand-edit.

Cargo builds happen inside the native-assets hooks during any
`flutter run/build/test` — no manual `cargo build`. First builds and
release builds (fat LTO) take minutes; run them in the background.

## Repo shape

- `packages/` — the eight Dart packages, each with its Rust crate(s) inside
  (`rust/`; `slint_build` carries `interpreter/`, the crate the interpreter,
  testing and Skia FFI crates share). Hooks find other packages through the
  package config (`packageRootFromConfig`), never by `../`. Crates reach
  each other by relative path (`../../slint/rust`) and inherit from a
  workspace, which only holds in the Cargo workspace `slint_build` stages
  under `.dart_tool/slint_cargo/` — a link `packages/<name>` per package
  root, so it works the same from the pub cache (`slint-0.0.1/`) as from
  here. So a crate may path-depend only on crates of packages its Dart
  package depends on. The root `Cargo.toml` lists the same crates for
  `cargo fmt`/`clippy`/`test` in the checkout.
- `examples/` — apps. Not packages: they consume the packages through the
  pub workspace (`resolution: workspace`, no path deps).
- Root `pubspec.yaml` is the pub workspace *and* the melos config
  (`melos:` key). Root `Cargo.toml` is the Cargo workspace.

## Architecture invariants

- **Backend follows build mode.** Debug (incl. `flutter test`) uses the
  interpreter; release/profile uses the AOT dylib. The hooks branch on
  `linkingEnabled`. AOT tests in `examples/todo/test` self-skip under
  `flutter test`; the release build is their e2e check.
- **The AOT ABI contract lives in one place**:
  `packages/slint_compiler/lib/src/generator.dart` (`aotComponentOps`,
  `aotSharedSymbols`, `aotComponentSymbols`, `aotNewExternName`, manifest
  name). The Dart codegen, the Rust glue emitter (`rust_glue.dart`), and
  both hooks all derive from it. A generator test asserts the manifest
  predicts exactly the symbols the glue exports — keep it passing.
- **Tree-shaking pipeline** (release): build hook emits a cargo *staticlib*
  plus `slint_aot_link.json`, routed `ToLinkHook`; the app's `hook/link.dart`
  (`linkSlintAot`) keeps only components whose generated `_new` extern has a
  recorded use and relinks with `CLinker` treeshake. Flutter records uses
  only behind `FLUTTER_RECORD_USE=true` (or
  `flutter config --enable-record-use`); without it, or when recordings hit
  zero externs, the hook deliberately keeps every component — never "fix"
  those keep-all fallbacks away.
- **`UnusedGadget` in `examples/todo/ui/todo.slint` is a deliberate canary**,
  not dead code: it proves tree-shaking by being absent
  (`slint_aot_unused_gadget_*`) from the shipped dylib when the flag is on.
  Do not remove it. (`examples/todo_skia` has no canary on purpose: no AOT
  there.)
- **`panic = "unwind"` is load-bearing** in the generated AOT crate and the
  FFI crates: every FFI entry point wraps in `catch_unwind`. Switching to
  `abort` to save size turns Rust panics into process aborts.
- **Symbols strip at the final link, not in cargo.** The staticlib must keep
  its symbols for the link hook's `-u`/exported-list tree-shaking; the hook
  strips the final dylib (`-S`, `-x`). Don't add `strip = "symbols"` back to
  the generated Cargo.toml.
- **`CLinker` emits `-framework` flags only with `language:
  Language.objectiveC`** (native_toolchain_c gate). Removing that argument
  breaks the macOS link with undefined CoreText/CoreFoundation symbols.
- **The linker line comes from rustc**, not guesswork: the build hook runs
  cargo with `RUSTFLAGS=--print=native-static-libs` and persists the note
  per target triple next to the generated crate
  (`native-link-flags.<triple>.txt`). rustc only prints it when it actually
  recompiles — if the persisted file is missing and stale, delete the
  crate's `target/` to force a rebuild.
- **Interpreter component definitions are selected by name** —
  `defs.firstWhere((d) => d.name == ...)`. `slint_interpreter`'s `compile`
  collects `CompilationResult::components()`, which iterates a `HashMap`:
  the order is arbitrary and not the order of the file, so `defs.first` is
  a coin flip whenever a `.slint` exports more than one component.
- **`opt-level = "z"` is rejected** for the AOT crate: measured 2.7× slower
  full-frame renders for ~1 MB/arch. Size-tune with fat LTO +
  `codegen-units = 1` only (see slint_compiler README's table).
- **No `.slint` is ever bundled as a Flutter asset, and the generated `load()`
  must stay that way.** Flutter declares assets per package, not per build
  mode (`dartDataAssets`, which could do it from a build hook, is
  `available: false` off master and cannot be forced on by env var or
  config) — so anything listed under `flutter: assets:` for debug convenience
  also ships in release, putting the UI source in the product. The wrapper
  therefore reads the bundle *only* when handed an explicit `path`;
  `load()` with no argument uses the source the builder embedded. An emitter
  test asserts no `loadString(assetPath)` slips back in. `examples/todo`'s
  assetless `flutter:` section and its "nothing reads the bundle unless a path
  says so" test are the regression guards — don't "fix" either.
- **`.slint` files live in `ui/`, generated Dart in `lib/`.** Both builders
  match `^ui/{{}}.slint` and write `lib/{{}}.g.dart` / `.aot.g.dart`; the
  AOT build hook compiles `ui/**.slint`; the code asset id stays
  `package:<app>/<stem>.aot.g.dart`. build_runner does not scan `ui/` by
  default — an app must list it under `targets.$default.sources` in its
  `build.yaml` (`examples/todo/build.yaml`), or the builders silently see no
  input. Nothing under `lib/` is ever a `.slint` again: the point is that
  the UI source is plainly not Dart and plainly not an asset.
- **The build mode is baked in at codegen, not resolved at runtime.** A
  generated wrapper's `load(path)` goes through `defaultFactory`, which is
  `_useCompiled ? aot.<x>Factory : SlintInterpreterFactory(_source, files:
  _files)` — and
  `_useCompiled` is a `const`, so the branch that build does not take is dead
  code the tree shaker drops. Don't turn that into a runtime lookup: the
  point is that a release binary contains no interpreter path at all.
- **The embedded source reaches the interpreter only through its factory's
  constructor**, inside that dead branch. `SlintComponentFactory.instantiate`
  takes a component name and nothing else, so the AOT path never mentions
  `_source` and a release snapshot carries no copy of the `.slint` text. An
  emitter test counts the mentions of `_source` (declaration, `slintSource`
  alias, one factory construction). Don't add a `source` parameter back to
  `instantiate` "for symmetry" — it would put the UI source in every release
  binary.
- **Everything from `.slint` to instance is synchronous.** `SlintEngine.compile`
  and `SlintComponentFactory.instantiate` are single FFI calls and return
  plain values; `SlintComponent.load` and a generated `load`/`create` return
  the wrapper, not a Future. There is no async entry point. Don't
  reintroduce `Future`: an app relies on
  `SlintComponent.load(...)` being usable in `initState` with no loading
  state.
- **`SlintComponent.load(path)` is a registry, and registration is per
  component.** The core class knows no generated code and Dart has no static
  initializers, so the app calls the generated `TodoApp.register()` once at
  startup (`examples/todo/lib/main.dart`); `load` then builds through the
  wrapper's `defaultFactory`. There is deliberately no per-file
  `registerTodoSlint()`: it would reference every component's AOT factory,
  give `UnusedGadget` a recorded use, and defeat tree-shaking — an emitter
  test asserts no such function is emitted. Both `load`s accept exactly one
  `.slint` path; `component:` or the type argument disambiguates a file that
  registered several.
- **A generated `load` never reads its `.slint`, in either mode.** `path` is
  the UI's name, checked against `assetPath`; the source comes from the
  `.g.dart` in debug and from the AOT dylib in release. Nothing reads a
  `.slint` at runtime, and there is no fallback for a file no wrapper was
  generated from (see Product requirements).
- **Imports and images travel with the embedded source.** The introspect
  tool reports every file a `.slint` reads besides itself (`import`ed
  `.slint`, `@image-url`); the builder embeds them in the wrapper as
  `_files`, keyed by path relative to the entry; `SlintInterpreterFactory`
  writes source and files into a temp tree (`writeSlintTree`) so the
  interpreter compiles at a real path. The AOT build compiles the `.slint`
  at its absolute path and lists the same files as hook dependencies. That
  is what lets a UI shared one package over
  (`examples/todo_shared/ui/todo_view.slint`) work in both modes.
- **Element queries live in `slint-dart-interpreter`** (`elements.rs`), not in
  either FFI crate: `slint-testing-ffi` and `slint-interpreter-ffi` both call
  `query_elements`/`describe_all`, so a headless test and a `slint_patrol`
  test driving the live app read the same fields for the same element. The
  crate depends on `i-slint-backend-testing` for `search_api` only — walking
  the item tree and reading geometry needs no platform, and `elements.rs`
  never installs the testing one.
- **`slint_patrol` maps Slint geometry to Flutter coordinates by dividing by
  the device pixel ratio**, because `SlintView` multiplies by it on the way in
  and Slint's scale factor is never set (so Slint logical == physical). If
  someone wires up `set_scale_factor`, that mapping has to change with it.
- **`pumpAndSettle` never returns with a `SlintView` on screen** — its
  `Ticker` renders every frame, so the tree is never quiescent. `slint_patrol`
  pumps a bounded number of frames (`slintSettle`); don't "fix" it back to
  settling.
- **`slint_testing` sets its own Slint platform.** It calls
  `init_no_event_loop()`, which panics if a platform already exists — safe
  only because `slint-testing-ffi` is a separate dylib with its own
  statically linked copy of Slint, independent of the
  software platform `slint-interpreter-ffi` installs from `slint-embed`. Do not merge the two
  crates. Its clicks go through the accessible *default action*: the
  `single_click`/`double_click` helpers are async and need an event loop.
- **Every FFI entry point runs on the thread that first called in.**
  `slint-dart-core::thread::check()` pins it; the interpreter crate, the
  generated AOT glue and their frees check it before touching Slint (which
  is `!Send`) or the thread-local error slot, and report instead of
  corrupting. Drive a component only from the isolate that created it.
- **One Slint version, pinned exactly**: `[workspace.dependencies]` in
  the root `Cargo.toml` (`=1.18.1`); the crates inherit with `workspace =
  true`. The staged workspace repeats that tail verbatim
  (`cargoWorkspaceShared` in `slint_build`, test-compared with the root
  file) because a pub consumer has no repo root. The generated AOT crate is
  outside both and pins the same version through `slintVersion` in
  `slint_compiler`'s `rust_glue.dart` — bump all three — and is seeded with
  the staged workspace's `Cargo.lock` (itself seeded from the repo's) so it
  resolves the same dependency tree. Dependabot (`.github/dependabot.yml`)
  groups the Slint crates into one PR that bumps only the root file; finish
  it by bumping the other two — `slint_build`'s and `slint_compiler`'s pins
  tests fail CI until you do.
- **`slint_skia` has no `SlintComponentFactory`**, so its wrappers have no
  `load`/`register`/`defaultFactory`: the app compiles through the Skia
  engine and passes the component to the generated constructor, which takes
  any backend's `SlintComponent`. Skia renders to a texture, so the
  wrapper's `renderTarget` throws for it. Its ceilings are explicit
  `UnimplementedError`s and
  documented sentinels; `examples/todo_skia` shows them on screen rather
  than faking a frame.
- **The example apps share everything but the backend through
  `examples/todo_shared`.** `ui/todo_view.slint` is the list UI, imported
  by each app's `ui/todo.slint` and embedded by each app's wrapper (it is
  not a build_runner source of `todo_shared`); `TodoStore`/`TodoEntry` own
  the add/toggle/remove-done rules once; `TodoExampleApp` and
  `TodoPageStateMixin` own the MaterialApp, the callbacks, sync + rebuild
  and the Scaffold; `package:todo_shared/testing.dart` owns the
  codegen-up-to-date tests, which also fail when an app's embedded copy of
  `todo_view.slint` goes stale. Each app only loads its backend and implements
  `pushTodos`, its mapping to the generated `TodoItem` at the Slint
  boundary. `todo_shared` depends on no app and no generated code. Don't
  re-duplicate any of it in either `main.dart`, and don't import one
  example's generated wrapper from the other — the wrappers differ by
  backend on purpose (AOT `defaultFactory` vs Skia's factory-less shape).

## Conventions

- Commit messages: conventional-commit style (`feat:`, `test:`, `fix:`),
  imperative subject, body explains the why. Commit only when asked.
- **Mandatory, for every agent: the human is the only author.** No agent
  adds a `Co-Authored-By` trailer, a "Generated with …" line or itself as
  author to a commit, merge or PR — whatever its harness defaults to.
- Full docs live under `site/content/` (Hugo/Hextra). Package/example
  `README.md` files are short pub.dev overviews — update the site page for
  substance, and the README only when the blurb changes. Root README for
  cross-cutting layout. A new invariant goes into the owning package's
  `AGENTS.md`; one that spans packages goes here.
- Rust debug/release profile for the crates is a pubspec user-define
  (`hooks.user_defines.<pkg>.profile`) read from the workspace root
  pubspec — independent of Flutter's `--debug`/`--release`.
- Adding a package: create it under `packages/`, add it to the root
  `pubspec.yaml` `workspace:` list (and its crate to `Cargo.toml`
  `members`), give it a short `README.md`, a `site/content/packages/` page,
  and an `AGENTS.md`, and add a row to the root README's layout table.

## Host agents

Save tokens. If anything is unclear, ask the creator first. Write a short execution plan into that task's card in `plan.md`, then claim and work. Default cap: **5** parallel agents per project unless the creator says otherwise. Never use max effort or fast mode without permission. Cheapest model for scripts, commands, repo scans, web, file moves, tests. On Cursor: **grok 4.6** (no fast) for planning, refactoring, bug hunts; **composer 2.5** (no fast) for file moves, tests, commands, scans, web. Before writing code, decide whether a ready library or framework should be used. A new dependency is allowed only if it is current (not abandoned) and the creator approved it. Packages already in `toolchain.md` may be reused without asking again. Prefer the latest versions of tools and packages, but bump already-installed ones only with the creator’s permission. Rust: reuse crates already used by sibling projects in this workspace (workspace-root `rust.md`). If this repo lacks one it should use, add a `plan.md` task — do not add the dependency silently. Extract duplicated helpers into `packages/` and depend via local `{ path = "..." }`. No version bumps without permission.

If a directory above this repository contains an `AGENTS.md` or `CLAUDE.md`, follow it too. If it conflicts with this file, ask the creator.