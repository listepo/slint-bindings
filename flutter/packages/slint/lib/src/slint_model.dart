import 'dart:collection';

/// Incremental list model backed by the JSON property bridge.
///
/// Each mutation reads the current snapshot from Slint, updates it in Dart,
/// and writes the whole list back — the public API apps use for array
/// properties without calling [SlintComponent.getProperty] by name.
class SlintListModel<T> extends IterableBase<T> {
  SlintListModel(
    Object? Function() getSnapshot,
    void Function(Object? snapshot) setSnapshot,
    T Function(Object? wire) fromWire,
    Object? Function(T value) toWire,
  ) : _getSnapshot = getSnapshot,
      _setSnapshot = setSnapshot,
      _fromWire = fromWire,
      _toWire = toWire;

  final Object? Function() _getSnapshot;
  final void Function(Object? snapshot) _setSnapshot;
  final T Function(Object? wire) _fromWire;
  final Object? Function(T value) _toWire;

  List<T> _read() => [
    for (final e in _getSnapshot() as List<Object?>) _fromWire(e),
  ];

  void _write(List<T> items) =>
      _setSnapshot([for (final e in items) _toWire(e)]);

  @override
  int get length => _read().length;

  @override
  Iterator<T> get iterator => _read().iterator;

  T operator [](int i) => _read()[i];

  void operator []=(int i, T value) {
    final list = _read();
    list[i] = value;
    _write(list);
  }

  void add(T value) {
    final list = _read();
    list.add(value);
    _write(list);
  }

  void insert(int index, T value) {
    final list = _read();
    list.insert(index, value);
    _write(list);
  }

  T removeAt(int index) {
    final list = _read();
    final removed = list.removeAt(index);
    _write(list);
    return removed;
  }

  void clear() => _write([]);

  void replaceAll(List<T> items) => _write(List<T>.from(items));

  @override
  List<T> toList({bool growable = true}) =>
      growable ? _read() : List<T>.unmodifiable(_read());

  @override
  bool operator ==(Object other) {
    if (other is SlintListModel<T>) {
      return _listEquals(toList(), other.toList());
    }
    if (other is List<T>) {
      return _listEquals(toList(), other);
    }
    return false;
  }

  @override
  int get hashCode => Object.hashAll(toList());
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
