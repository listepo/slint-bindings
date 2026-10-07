One typed API, two independent backends behind it. The generated wrapper's
`defaultFactory` follows the Flutter build mode, exactly like the hooks that
decide which dylib ships — interpreter in debug, AOT in release/profile.

## Interpreter (debug)

Compiles the source embedded in `foo.g.dart` at runtime and renders via
`slint_interpreter`. What the source imports or loads through `@image-url` is
embedded next to it (`slintFiles`); `SlintInterpreterFactory` writes both
into a temporary tree (`writeSlintTree`) so the compiler resolves them at a
real path. No runtime asset. The bundle ships only `slint_interpreter_ffi`.

```bash
cd examples/todo && mise exec -- flutter run
```

There is no runtime path for a `.slint` without a generated wrapper: loading
a `.slint` in code always gives back its wrapper, in every build mode. See
the [interpreter package](/packages/slint_interpreter).

## AOT (release/profile)

Binds straight to the AOT-compiled component, no interpreter. The bundle
ships only `slint_dart_aot`.

```bash
cd examples/todo && mise exec -- flutter run --release
```

The app's `hook/build.dart` calls `buildSlintAot`: slint-build codegen of
every `ui/**.slint` plus generated C ABI glue, built as a staticlib. Each
`.slint` compiles at its absolute path, so its imports resolve, and files it
reads from outside `ui/` are hook dependencies. The
app's `hook/link.dart` calls `linkSlintAot`: relinks the final dylib from
that staticlib, keeping only the components the app uses. See the
[AOT package](/packages/slint_compiler) for the pipeline,
the release-size table, and the tree-shaking mechanism.

Component tree-shaking works behind Flutter's record-use flag:

```bash
FLUTTER_RECORD_USE=true flutter build macos --release
```

Without recordings every component is kept — the deliberate keep-all
fallback. The example's `UnusedGadget` component exists to prove the
mechanism: exported and compiled like any other, referenced by no Dart code,
and absent from the shipped dylib when the flag is on.

## Adding a backend

A backend extends `SlintComponentFactory` (see the
[codegen package](/packages/slint_generator)) and is passed
to the wrapper's `create()` — `defaultFactory` just picks one from the
package's dependencies at codegen time. The two backends never meet: the
pick is a `const` branch, so a release binary carries no interpreter path and
a debug run never loads the AOT dylib.

A backend with no factory (`slint_skia`) still ends in the wrapper: the app
compiles through that engine and passes the component to the generated
constructor, `TodoApp(component)`.
