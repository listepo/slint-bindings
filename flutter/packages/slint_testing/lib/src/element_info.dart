/// One element of a Slint component's accessibility tree.
///
/// This is the plain description — no way to act on it. Both hosts that
/// produce elements build on it: [SlintElement] in this package adds actions
/// that go through the testing backend, and `slint_patrol` adds ones that go
/// through real Flutter gestures against the live app. The descriptors come
/// from a single Rust implementation shared by both backends, so the same
/// element reads the same either way.
class SlintElementInfo {
  const SlintElementInfo({
    required this.index,
    required this.id,
    required this.typeName,
    required this.role,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.description,
    required this.checked,
    required this.checkable,
    required this.enabled,
    required this.itemIndex,
    required this.itemCount,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  SlintElementInfo.fromJson(Map<String, Object?> json)
    : index = json['index'] as int,
      id = json['id'] as String?,
      typeName = json['typeName'] as String?,
      role = json['role'] as String?,
      label = json['label'] as String?,
      value = json['value'] as String?,
      placeholder = json['placeholder'] as String?,
      description = json['description'] as String?,
      checked = json['checked'] as bool?,
      checkable = json['checkable'] as bool?,
      enabled = json['enabled'] as bool?,
      itemIndex = json['itemIndex'] as int?,
      itemCount = json['itemCount'] as int?,
      x = (json['x'] as num).toDouble(),
      y = (json['y'] as num).toDouble(),
      width = (json['width'] as num).toDouble(),
      height = (json['height'] as num).toDouble();

  /// Position in the query that produced this element.
  final int index;

  /// Element id qualified by its component, e.g. `TodoView::edit`.
  final String? id;

  /// The element's type, e.g. `Button` or `LineEdit`.
  final String? typeName;

  /// Accessible role, e.g. `Button`, `Checkbox`, `TextInput`.
  final String? role;

  final String? label;
  final String? value;
  final String? placeholder;
  final String? description;
  final bool? checked;
  final bool? checkable;
  final bool? enabled;
  final int? itemIndex;
  final int? itemCount;

  /// Geometry in Slint logical pixels, positioned relative to the window.
  final double x;
  final double y;
  final double width;
  final double height;

  /// Whether the element occupies any space — a zero-sized element cannot be
  /// clicked, and usually means it is not laid out or not shown.
  bool get hasSize => width > 0 && height > 0;

  @override
  String toString() {
    final parts = [
      if (typeName != null) typeName,
      if (id != null) '#$id',
      if (label != null) '"$label"',
      if (value != null) 'value: "$value"',
      if (checked != null) 'checked: $checked',
    ];
    return '$runtimeType(${parts.join(' ')})';
  }
}
