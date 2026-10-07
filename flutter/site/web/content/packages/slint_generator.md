Turns `.slint` files into typed Dart wrappers (`*.g.dart`) that run on **any**
Slint backend. Shared by both paths: the interpreter (`slint_interpreter`) and
the AOT-compiled one (`slint_compiler`).

## How it works

```
foo.slint ──▶ slint-introspect (rust/) ──▶ schema ──▶ build_runner ──▶ foo.g.dart
```

- `rust/` holds `slint-introspect`: compiles the `.slint` with
  `i-slint-compiler` and dumps the full typed public interface (struct fields,
  array element types, callback signatures) as JSON, plus every file the
  `.slint` reads besides itself.
- The build_runner builder emits one class per exported component — typed
  property accessors, `onX`/`invokeX` per callback, `renderTarget`, `dispose`
  — plus one class per named struct, plus the `.slint` source and the files
  it reads, embedded so runtime backends can compile it.
- Instances come from a `SlintComponentFactory`, so the generated API is
  backend-agnostic:

```dart
final app = TodoApp.create();                                            // default backend
final app = TodoApp.create(SlintInterpreterFactory(                      // interpreter
    TodoApp.slintSource, files: TodoApp.slintFiles));
final app = TodoApp.create(todoAppFactory);                              // AOT backend
final app = TodoApp(component);                   // any backend's SlintComponent
```

Everything is synchronous: compiling with the interpreter and creating an AOT
instance are each a single FFI call, so there is nothing to await and the
instance is renderable on return.

`defaultFactory` is generated from the backends the package depends on: with
both, it follows the build mode (`dart.vm.product`/`dart.vm.profile` — the
same condition as Flutter's `kDebugMode`, so it matches the dylib the build
hooks bundle); with one, it is that one; with neither, `create` requires an
explicit factory. It is created once and shared.

### `load` — naming the UI by its `.slint` path

An app names a UI by its `.slint` path in every build mode; what backs that
path is the build's business:

```dart
TodoApp.register();                                        // once, at startup
final TodoApp app = SlintComponent.load('ui/todo.slint');  // or TodoApp.assetPath
final app2 = TodoApp.load('ui/todo.slint');                // same, no registry
```

`register()` is generated per component and puts `create` into
`SlintComponent`'s path registry; `SlintComponent.load` returns whatever was
registered for the path, typed by its type argument (inferred from the
assignment). It is per component, never per file: a `registerTodoSlint()`
would reference every component's AOT factory and defeat tree-shaking.

The mode split is generated, not resolved at runtime: `defaultFactory` is
`_useCompiled ? aot.todoAppFactory : SlintInterpreterFactory(_source, files: _files)`, and
`_useCompiled` is a `const`. A release build initializes it to the AOT
factory and the interpreter branch is dead code the tree shaker drops; a
debug build does the reverse. `load` reuses that one cached factory rather
than building one per call.

**The source ships only with the interpreter.** `_source` — the `.slint`
text the builder embedded — and `_files` are handed to the interpreter
factory's constructor inside that dead branch and nowhere else (`instantiate`
takes only a component name), so a release snapshot carries no copy of them: the UI
source exists in the product only as slint-build compiled code. An emitter
test counts the mentions.

**Nothing is bundled, ever.** `.slint` files live under `ui/`, outside
`lib/`, and the generated wrapper has no asset access at all: the source it
compiles is the one the builder captured into `lib/*.g.dart`, and release
compiles it into the binary. That keeps the `.slint` out of the shipped app
— Flutter declares assets per package, not per build mode, so an asset
declared for debug convenience would ride along into release and put the UI
source in the product.

**Imports and images travel with the source.** The schema tool reports every
file the `.slint` reads besides itself — `import`ed `.slint` files and
`@image-url` resources — and the builder embeds them as `_files`, base64 by
path relative to the entry (`../../todo_shared/ui/todo_view.slint`), exposed
as `static const slintFiles`. The Slint compiler resolves both from disk, so
`SlintInterpreterFactory` writes source and files into a temporary tree with
`writeSlintTree` (`package:slint/slint_core.dart`) and compiles the entry
there; a backend without a factory does the same by hand
(`examples/todo_skia`). The AOT build compiles the `.slint` at its absolute
path and lists the same files as hook dependencies. The copies are taken at
generation time: after editing an imported file, rerun build_runner —
`examples/todo_shared`'s `testWrapperEmbedsCurrentSlint` catches a stale
one.

`path` is one `.slint` file — anything else is an `ArgumentError` before the
path is even compared — and it must be [assetPath], the file this wrapper was
generated from.
Passing another one throws rather than quietly rendering the wrong UI; every
other `.slint` gets a wrapper of its own, and nothing compiles a `.slint` no
wrapper was generated from.

`create()` is the same thing without a path, for code that already knows
which component it wants. `load`, `register` and `assetPath` are only
generated when there is a `defaultFactory` to run them on.

Generated wrappers implement `SlintSoftwareComponent` and hold the backing
instance as `final SlintComponent component`, from any backend:
`TodoApp(component)` wraps a Skia component or a `slint_patrol` test's
`$.slintComponent()` just the same. `renderTarget` forwards to a
software-rendering component and throws `StateError` for any other (Skia
renders to a texture). App code uses the typed members; the untyped
`getProperty`/`setProperty`/`setCallbackHandler`/`invokeCallback` the wrapper
also implements are the bridge the backends provide for generated code, not
an API to call by Slint name.

## Two entry points

- `package:slint_generator/runtime.dart` — the `SlintComponentFactory` base
  class. Generated wrappers and apps import this.
- `package:slint_generator/slint_generator.dart` — the build-time API
  (`introspectSlint`, `generateWrapperLibrary`, the schema). Only the builder
  and `slint_compiler` need it.

`SlintComponentFactory` is an `abstract base class`, so a backend must
`extend` it rather than structurally match it — see `SlintInterpreterFactory`
(`slint_interpreter`) and `SlintCompilerFactory` (`slint_compiler`).

## Usage

The generated wrapper imports `runtime.dart`, so this is a regular dependency,
not a dev one:

```yaml
# pubspec.yaml of the app
dependencies:
  slint: ^0.0.1
  slint_generator: ^0.0.1
  slint_interpreter: ^0.0.1   # or slint_compiler for the AOT backend

dev_dependencies:
  build_runner: ^2.16.0
```

Put `.slint` files under `ui/` — build_runner does not scan that directory
on its own, so list it in the app's `build.yaml`:

```yaml
# build.yaml of the app
targets:
  $default:
    sources: [lib/**, test/**, ui/**, pubspec.yaml, $package$]
```

```bash
dart run build_runner build   # ui/todo.slint → lib/todo.g.dart
```

```dart
import 'todo.g.dart';

final app = TodoApp.load('ui/todo.slint');
app.todoModel = [
  const TodoItem(title: 'Learn Slint', checked: false),
];
app.onAddTodo((title) => print(title));
```

## Generated types

Nothing in the generated API is `Object?`. Slint types map to Dart as:

| Slint                                    | Dart                    |
| ---------------------------------------- | ----------------------- |
| `int`                                    | `int`                   |
| `float`, `length`, `duration`, `angle`, `percent` | `double`       |
| `string`                                 | `String`                |
| `bool`                                   | `bool`                  |
| `[T]`                                    | `List<T>`               |
| `struct Foo { … }`                       | generated `class Foo`   |

Each named struct becomes a value class with a const constructor, final
fields, `copyWith`, `==`/`hashCode`, and `toString`. `fromSlint`/`toSlint`
convert to and from the representation the backends speak, and the wrappers
call them for you — a `[TodoItem]` property is a `List<TodoItem>` on both
sides of the accessor, and app code never needs the map form.

Callbacks become typed function signatures, using the argument names from the
`.slint` where they are declared:

```slint
callback toggle-todo(index: int, checked: bool);
```

```dart
void onToggleTodo(void Function(int index, bool checked) handler);
void invokeToggleTodo(int index, bool checked);
```

Undeclared argument names fall back to `arg1`, `arg2`, … A callback with a
return type gets it too, converted the same way.

## Limits

- Supported property/callback types: numbers, string, bool, named structs,
  arrays. Color/brush/image/enum properties fail generation with a clear
  error.
- Generated identifiers are not checked against Dart keywords: a Slint field
  or callback argument named `class` or `default` produces a file that does
  not compile. Rename it in the `.slint`.
- A Rust toolchain is required at generation time (the schema tool is compiled
  with cargo).
