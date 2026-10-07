import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slint_interpreter/slint_interpreter.dart';

/// A 1×1 PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

const _source = '''
import { Label } from "../../shared/ui/label.slint";
export component T inherits Window {
    property <image> pic: @image-url("img/px.png");
    out property <int> icon-width: pic.width;
    out property <string> label: l.text;
    l := Label {}
}
''';

void main() {
  test('compiles against the imports and images it is handed', () {
    // What a generated wrapper passes as `files`: a UI shared one package
    // over and an image, by path relative to the entry. The interpreter used
    // to compile the embedded source at a made-up path, so neither resolved.
    final factory = SlintInterpreterFactory(
      _source,
      files: {
        '../../shared/ui/label.slint': base64Encode(
          utf8.encode(
            'export component Label inherits Text { text: "shared"; }',
          ),
        ),
        'img/px.png': _png,
      },
    );
    addTearDown(factory.dispose);
    final component = factory.instantiate('T');
    addTearDown(component.dispose);

    expect(component.getProperty('label'), 'shared');
    expect(
      component.getProperty('icon-width'),
      1,
      reason: 'the image was found and decoded',
    );
  });

  test('without the files, the import has nothing to resolve against', () {
    final factory = SlintInterpreterFactory(_source);
    addTearDown(factory.dispose);
    expect(() => factory.instantiate('T'), throwsStateError);
  });
}
