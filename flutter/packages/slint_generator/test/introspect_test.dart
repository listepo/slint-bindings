import 'dart:convert';
import 'dart:io';

import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

/// A 1×1 PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  test('reports what a .slint reads besides itself', () async {
    final root = Directory.systemTemp
        .createTempSync('slint_introspect_')
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    File('$root/shared/ui/view.slint')
      ..createSync(recursive: true)
      ..writeAsStringSync('export component View { Text { text: "shared"; } }');
    File('$root/app/ui/img/px.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(base64Decode(_png));
    final main = File('$root/app/ui/main.slint')
      ..writeAsStringSync('''
import { View } from "../../shared/ui/view.slint";
export component Main inherits Window {
    Image { source: @image-url("img/px.png"); }
    View {}
}
''');

    final schema = await introspectSlint(main.path);

    expect(schema.components.single.name, 'Main');
    expect(schema.files, [
      '$root/app/ui/img/px.png',
      '$root/shared/ui/view.slint',
    ]);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('reports color, brush, image, and enum property types', () async {
    final root = Directory.systemTemp
        .createTempSync('slint_introspect_types_')
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    final main = File('$root/app/ui/types.slint')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
export enum Status { active, done }
export component Types inherits Window {
    in-out property <color> accent: #ff0000;
    in-out property <brush> fill: #00ff00;
    in-out property <image> thumb;
    in-out property <Status> state: active;
}
''');

    final schema = await introspectSlint(main.path);
    final props = {
      for (final p in schema.components.single.properties) p.name: p.type,
    };

    expect(props['accent']!.kind, 'color');
    expect(props['fill']!.kind, 'brush');
    expect(props['thumb']!.kind, 'image');
    expect(props['state']!.kind, 'enum');
    expect(props['state']!.enumName, 'Status');
    expect(props['state']!.variants, ['active', 'done']);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
