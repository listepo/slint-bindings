/// Framework-free todo-list state shared by the examples.
///
/// Both `examples/todo` and `examples/todo_skia` drive the same `.slint`
/// UI (`todo-model`, `add-todo`, `toggle-todo`, `remove-done`) on different
/// backends. Each app keeps its generated `TodoItem` at the Slint boundary
/// and owns the list here, so the rules — trim-on-add, ignore-empty,
/// bounds-checked toggle, drop-checked-on-remove — are implemented once.
///
/// Nothing here speaks Slint's wire format: each app converts to its
/// generated `TodoItem` and reaches Slint only through the generated wrapper.
library;

/// One todo row: the same fields as the `TodoItem` struct in `todo.slint`.
class TodoEntry {
  const TodoEntry({required this.title, required this.checked});

  final String title;
  final bool checked;

  TodoEntry copyWith({String? title, bool? checked}) =>
      TodoEntry(title: title ?? this.title, checked: checked ?? this.checked);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodoEntry && title == other.title && checked == other.checked;

  @override
  int get hashCode => Object.hash(title, checked);

  @override
  String toString() => 'TodoEntry(title: $title, checked: $checked)';
}

/// The seed list both example apps start from, mirroring the `todo-model`
/// default in `ui/todo.slint`.
const initialTodoEntries = [
  TodoEntry(title: 'Wire Slint into Flutter', checked: true),
  TodoEntry(title: 'Render this list', checked: false),
];

/// `'$open open / $total total — $backend'`, the AppBar title both example
/// apps show; each passes its own backend label.
String todoCountTitle({
  required int open,
  required int total,
  required String backend,
}) => '$open open / $total total — $backend';

/// Owns the todo list for an example app. Plain Dart, no Flutter import,
/// so it is unit-testable without a widget tree and usable from any backend.
class TodoStore {
  TodoStore([List<TodoEntry>? initial])
    : _items = List.of(initial ?? initialTodoEntries);

  final List<TodoEntry> _items;

  /// Current rows, in order. Read-only view — mutate through [addTodo],
  /// [toggleTodo], and [removeDone].
  List<TodoEntry> get items => List.unmodifiable(_items);

  int get total => _items.length;

  int get openCount => _items.where((t) => !t.checked).length;

  String countTitle(String backendLabel) =>
      todoCountTitle(open: openCount, total: total, backend: backendLabel);

  /// Appends [title] trimmed; ignores blank input. Returns whether a row
  /// was added.
  bool addTodo(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    _items.add(TodoEntry(title: trimmed, checked: false));
    return true;
  }

  /// Sets row [index] to [checked]. Out-of-range indexes are ignored and
  /// reported as `false`.
  bool toggleTodo(int index, bool checked) {
    if (index < 0 || index >= _items.length) return false;
    _items[index] = _items[index].copyWith(checked: checked);
    return true;
  }

  /// Drops every checked row.
  void removeDone() {
    _items.removeWhere((t) => t.checked);
  }
}
