Test Slint UIs from Dart, through the accessibility tree.

A component is compiled and instantiated on Slint's testing backend
(`i-slint-backend-testing`) — no window, no renderer, no event loop — and
exposed as elements you can find, click, fill in, and assert on. Tests
describe what a user can perceive and do, not which pixels changed.

```dart
import 'package:slint_testing/slint_testing.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

void main() {
  test('adding a todo reaches the typed handler', () {
    final ui = SlintTestApp.compile(TodoApp.slintSource,
        component: TodoApp.componentName, files: TodoApp.slintFiles);
    final app = TodoApp(ui);
    addTearDown(app.dispose);

    final added = <String>[];
    app.onAddTodo(added.add);
    ui.findById('TodoView::edit').single.setValue('buy milk');
    ui.findByLabel('Add').single.click();

    expect(added, ['buy milk']);
  });
}
```

`SlintTestApp` is a `SlintComponent`, so the wrapper `slint_generator`
generated from the `.slint` wraps it like any backend's instance. Elements
are found and acted on through the test app; properties and callbacks go
through the wrapper's typed members, and nothing in the test names a Slint
property or callback. The wrapper embeds the source and everything it
imports, so the test reads no file.

No device, no window, no golden files. The package itself needs no Flutter
and its own tests run under plain `dart test`; a test that imports an app's
wrapper runs under `flutter test`, like the app's other tests. The native
library is built by the package's own build hook.

## Finding elements

| Method | Matches |
| --- | --- |
| `findByLabel(label)` | the accessible label — a button's text, a checkbox's caption |
| `findById(id)` | an element id qualified by the component that declares it, `TodoView::edit` |
| `findByType(name)` | the element's type, `Button`, `LineEdit` |
| `findByRole(role)` | the accessible role, `Button`, `Checkbox`, `TextInput` |
| `findAll()` | every element in the tree |

Each returns a `List<SlintElement>` carrying `id`, `typeName`, `role`,
`label`, `value`, `placeholder`, `description`, `checked`, `checkable`,
`enabled`, `itemIndex`, `itemCount`, and the element's `x`, `y`, `width`,
`height` in Slint logical pixels relative to the window.

Those fields come from `SlintElementInfo`, the element model this package
owns. `slint_patrol` reuses it for the live app, and both are filled in by one
Rust implementation in `slint-dart-interpreter`, so the same element reads the
same headlessly and on screen. Geometry is only meaningful once the component
has been laid out, which headless tests never trigger — it is there for
`slint_patrol`, which needs it to know where to click.

The tree is the *whole* tree: it descends into the widgets' own
implementation, so a `LineEdit` is followed by the `Rectangle`, `TextInput`,
and `Text` that make it up, and a widget repeats its role on the inner
elements implementing it. Prefer `findByLabel` and `findById` — they name
what the test is actually about; `findAll` is for exploring an unfamiliar
component.

Results are a snapshot, and each query replaces the previous one. An element
therefore belongs to the query that produced it: acting on one from an
earlier query throws, rather than silently acting on whatever now sits at
that position. Query, act, and query again.

## Interacting

`click()` invokes the element's accessible **default action** — pressing a
button, toggling a checkbox. `setValue(String)` sets its accessible value —
typing into an input, moving a slider. Both are synchronous: the testing
backend runs without an event loop, so the async pointer-event helpers that
need one are deliberately not exposed.

Using a component or element after `dispose()` throws (`SlintTestException`)
— the Dart side never sends a freed handle back into native code.

`elapse(Duration)` advances the backend's mock clock, driving animations and
timers without waiting in real time.

## Properties and callbacks

`SlintTestApp` implements `SlintComponent`: `getProperty`, `setProperty`,
`setCallbackHandler` and `invokeCallback` cross the same JSON bridge the
interpreter uses, so Dart maps and lists map onto Slint structs and models.
They are the layer a generated wrapper calls. A test uses the wrapper's
members instead (`app.todoModel`, `app.onAddTodo(...)`), because only
generated code spells Slint names.

A handler runs synchronously, inside the `click()` or `invokeCallback` that
fired it. Its return value becomes the callback's, and `null` reads as the
declared type's default. A handler that throws is reported to the current
zone, which fails the test, and Slint gets the default. Disposing the app
from inside a handler is safe: the native side is freed once the call that
ran the handler returns.

Nothing here renders, so the wrapper's `renderTarget` throws over this
backend.

## Choosing the component

`component:` may be omitted only when the source exports exactly one.
The compiler returns components unordered, so with several exports there is
no meaningful "first" to fall back on; `compile` throws and names what it
found instead of picking one arbitrarily. Pass the wrapper's
`componentName` rather than spelling it.

`files:` takes what the source reads besides itself, `import`ed `.slint`
files and `@image-url` resources, as a wrapper's `slintFiles` holds them.
They are written to a temporary tree, so imports and images resolve without
the test knowing where the app's `ui/` lives.

## Layout

```
lib/slint_testing.dart      public API
lib/src/testing.dart        SlintTestApp, SlintElement
lib/src/bindings.g.dart     generated ffigen bindings — do not hand-edit
hook/build.dart             builds the Rust crate as a native asset
rust/                       slint-testing-ffi: the C ABI over the testing backend
```

The Rust crate links its own copy of Slint, so its testing platform is
independent of the software platform `slint_interpreter` installs. Reuses
`slint-dart-interpreter` for compilation, the JSON property bridge, and the
element query itself.

## Testing the running app instead

This package tests a component headlessly — fast, but not the app a user
touches. [`slint_patrol`](/packages/slint_patrol) covers that: Patrol finders over
the live component in a real widget tree, tapping and typing through real
Flutter gestures.
