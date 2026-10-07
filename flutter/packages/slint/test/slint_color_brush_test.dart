import 'package:slint/slint_core.dart';
import 'package:test/test.dart';

void main() {
  group('SlintColor', () {
    test('roundtrips opaque and alpha hex', () {
      final c = SlintColor.fromHex('#0a1b2c');
      expect(c.argb, 0xFF0A1B2C);
      expect(c.toHex(), '#0a1b2c');
      expect(SlintColor.fromSlint('#0a1b2cff').argb, 0x0A1B2CFF);
    });
  });

  group('SlintBrush', () {
    test('roundtrips solid and gradient DSL', () {
      final solid = SlintBrush.fromSlint('#ff0000');
      expect(solid, isA<SlintSolidBrush>());
      expect(solid.toSlint(), '#ff0000');

      const gradient = '@linear-gradient(90deg, #ff0000ff 0%, #00ff00ff 100%)';
      final g = SlintBrush.fromSlint(gradient);
      expect(g, isA<SlintGradientBrush>());
      expect(g.toSlint(), gradient);
    });
  });
}
