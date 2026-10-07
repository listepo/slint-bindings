/// Shared code for the `examples/todo` and `examples/todo_skia` apps: the
/// framework-free store, so the add/toggle/remove-done rules live in exactly
/// one place, plus the Flutter page scaffolding around it. Each app only
/// loads its backend and maps to its generated `TodoItem` at the Slint
/// boundary. Test helpers live in `testing.dart`.
library;

export 'src/todo_page.dart';
export 'src/todo_store.dart';
