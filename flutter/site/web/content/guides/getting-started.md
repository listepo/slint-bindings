This guide is for a **new Flutter app** that pulls the packages from
[pub.dev](https://pub.dev). You do not need to clone the `slint_dart`
monorepo. The [todo example](/examples/todo) in this
repository is the full reference implementation — same layout, more moving
parts — but the steps below are enough to ship a first screen.

## Prerequisites

- Flutter (stable channel) and Dart 3.13+.
- Rust through [rustup](https://rustup.rs) — the native-assets hooks compile
  Rust crates during `flutter run`, `flutter build`, and `flutter test`.
- A platform C toolchain (Xcode command line tools on macOS, NDK on Android)
  for the final app link step.

## 1. Add dependencies

In your app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  meta: ^1.19.0          # generated *.aot.g.dart imports @RecordUse
  slint: ^0.0.1
  slint_interpreter: ^0.0.1
  slint_compiler: ^0.0.1
  slint_generator: ^0.0.1
  hooks: ^2.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.16.0
```

| Package | Role |
|---|---|
| `slint` | Core API and the `SlintView` widget |
| `slint_interpreter` | Debug backend (software renderer) |
| `slint_compiler` | Release/profile AOT backend + link hook helpers |
| `slint_generator` | `build_runner` codegen → typed `*.g.dart` wrappers |
| `hooks` | Native-assets hook entry points |

Then `flutter pub get`.

## 2. Opt `ui/` into build_runner

`build_runner` scans `lib/` by default. Slint source lives in `ui/` (not Dart,
not a Flutter asset), so list it explicitly in `build.yaml` at the app root:

```yaml
# build_runner reads lib/, test/, etc. by default; .slint files live in ui/.
targets:
  $default:
    sources:
      - lib/**
      - test/**
      - ui/**
      - pubspec.yaml
      - $package$
```

The `slint_generator` and `slint_compiler` builders (they `auto_apply` to
dependents) then map `ui/<name>.slint` → `lib/<name>.g.dart` and
`lib/<name>.aot.g.dart`.

## 3. Native hooks (AOT for release)

Create two files beside `pubspec.yaml`. They are thin wrappers around
`slint_compiler` — copy the pattern from
[`examples/todo`](https://github.com/listepo/slint_dart/tree/main/examples/todo):

`hook/build.dart`:

```dart
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_build.dart';

void main(List<String> args) => build(args, buildSlintAot);
```

`hook/link.dart`:

```dart
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_link.dart';

void main(List<String> args) => link(args, linkSlintAot);
```

During `flutter build` / `flutter run --release`, the build hook AOT-compiles
every `ui/**/*.slint` into a static library; the link hook tree-shakes unused
components into the one code asset the generated `@Native` externs bind to.
Debug builds skip linking and ship only the interpreter dylib. See
[Backends](/guides/backends).

## 4. Write a `.slint` file

Put UI source under `ui/`, never under `lib/`:

`ui/hello.slint`:

```slint
export component HelloApp inherits Window {
    preferred-width: 400px;
    preferred-height: 300px;
    title: "Hello Slint";

    in property <string> message: "Hello from Slint";

    VerticalLayout {
        padding: 16px;
        Text { text: root.message; font-size: 24px; }
    }
}
```

## 5. Generate Dart wrappers

```bash
dart run build_runner build --delete-conflicting-outputs
```

This writes `lib/hello.g.dart` (typed `HelloApp` class, embedded source) and
`lib/hello.aot.g.dart` (AOT factory + `@RecordUse` externs). Commit both;
regenerate after every `.slint` edit.

## 6. Load the component and show `SlintView`

Register each component once at startup, then load by `.slint` path. Loading is
**synchronous** — safe in `initState` with no `Future`.

```dart
import 'package:flutter/material.dart';
import 'package:slint/slint.dart';

import 'hello.g.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HelloApp.register(); // once per component
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  HelloApp? _app;

  @override
  void initState() {
    super.initState();
    _app = SlintComponent.load('ui/hello.slint')
      ..message = 'Hello from Flutter';
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return MaterialApp(
      home: Scaffold(
        body: app == null
            ? const Center(child: CircularProgressIndicator())
            : SlintView(target: app.renderTarget),
      ),
    );
  }
}
```

Use generated members (`app.message`, `app.onSomeCallback(...)`) for properties and
callbacks — never `getProperty` / `setProperty` / `invoke` by Slint name in app
code.

`SlintComponent.load('ui/hello.slint')` returns the typed `HelloApp` wrapper.
`defaultFactory` inside the generated code follows the build mode: interpreter
in debug, AOT in release/profile. App code names neither backend.

## 7. Do not bundle `.slint` as Flutter assets

Leave `flutter: assets:` **empty** of `.slint` files. Flutter has no
per-build-mode asset list — anything declared ships in release too. The builder
embeds the source in `lib/*.g.dart` for debug; release compiles it into the
AOT dylib. Bundling the file again would put UI source in the shipped app for
nothing.

The todo example's `pubspec.yaml` deliberately lists no `ui/` assets; a
regression test guards that invariant.

## Debug vs release

| Build mode | Backend | What runs your UI |
|---|---|---|
| Debug, profile tests (`flutter test`) | `slint_interpreter` | Embedded `.slint` text compiled at runtime |
| Release, profile app builds | `slint_compiler` AOT | Precompiled dylib from the hooks |

First `flutter run` / `flutter test` builds native code through the hooks
(minutes on a cold cache). Nothing needs a manual `cargo build`.

## Next steps

- [Backends](/guides/backends) — how the split is generated, not
  looked up at runtime.
- [Testing](/guides/testing) — headless (`slint_testing`) and live
  (`slint_patrol`) UI tests.
- [todo example](/examples/todo) — registry per component,
  shared UI imports, tree-shaking canary, release size notes.
- [Contributing](/contributing) — if you are hacking the
  `slint_dart` monorepo itself (`just check`, melos, Jaspr docs site).
