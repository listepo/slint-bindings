/// An Slint [color] value, stored as 0xAARRGGBB.
final class SlintColor {
  const SlintColor(this.argb);

  /// Packed ARGB (`0xAARRGGBB`), matching Slint's wire encoding.
  final int argb;

  /// Parses `#rrggbb` or `#rrggbbaa`, as Slint's JSON bridge uses.
  factory SlintColor.fromHex(String hex) {
    var h = hex;
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) {
      return SlintColor(0xFF000000 | int.parse(h, radix: 16));
    }
    if (h.length == 8) {
      return SlintColor(int.parse(h, radix: 16));
    }
    throw ArgumentError.value(hex, 'hex', 'expected #rrggbb or #rrggbbaa');
  }

  /// Writes `#rrggbb` when alpha is opaque, otherwise `#rrggbbaa`.
  String toHex() {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String byte(int v) => v.toRadixString(16).padLeft(2, '0');
    if (a == 0xFF) return '#${byte(r)}${byte(g)}${byte(b)}';
    return '#${byte(r)}${byte(g)}${byte(b)}${byte(a)}';
  }

  factory SlintColor.fromSlint(String wire) => SlintColor.fromHex(wire);

  String toSlint() => toHex();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SlintColor && argb == other.argb;

  @override
  int get hashCode => argb.hashCode;

  @override
  String toString() => 'SlintColor($toHex())';
}
