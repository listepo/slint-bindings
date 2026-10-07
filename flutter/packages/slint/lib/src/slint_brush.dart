import 'slint_color.dart';

/// An Slint [brush] value — a solid color or a gradient DSL string.
sealed class SlintBrush {
  const SlintBrush();

  factory SlintBrush.fromSlint(String wire) {
    if (wire.startsWith('@linear-gradient(') ||
        wire.startsWith('@radial-gradient(')) {
      return SlintGradientBrush(wire);
    }
    return SlintSolidBrush(SlintColor.fromHex(wire));
  }

  String toSlint();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlintBrush &&
          runtimeType == other.runtimeType &&
          toSlint() == other.toSlint();

  @override
  int get hashCode => toSlint().hashCode;

  @override
  String toString() => 'SlintBrush(${toSlint()})';
}

/// A solid-color brush (`#rrggbb` / `#rrggbbaa` on the wire).
final class SlintSolidBrush extends SlintBrush {
  const SlintSolidBrush(this.color);

  final SlintColor color;

  @override
  String toSlint() => color.toSlint();
}

/// A linear or radial gradient, kept as the Slint DSL string on the wire.
final class SlintGradientBrush extends SlintBrush {
  const SlintGradientBrush(this.dsl);

  final String dsl;

  @override
  String toSlint() => dsl;
}
