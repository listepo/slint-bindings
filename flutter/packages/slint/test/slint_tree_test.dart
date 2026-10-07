import 'dart:convert';
import 'dart:io';

import 'package:slint/slint_core.dart';
import 'package:test/test.dart';

String _b64(String s) => base64Encode(utf8.encode(s));

void main() {
  test('lays files out relative to the entry, ../ included', () {
    // The compiler resolves imports and images relative to the file it
    // compiles; a shared UI one package over is `../../shared/...`.
    final tree = writeSlintTree('main', {
      'lib/a.slint': _b64('a'),
      '../../shared/b.slint': _b64('b'),
    }, name: 'todo.slint');

    expect(tree.path, endsWith('todo.slint'));
    expect(File(tree.path).readAsStringSync(), 'main');
    final dir = File(tree.path).parent.uri;
    expect(File.fromUri(dir.resolve('lib/a.slint')).readAsStringSync(), 'a');
    expect(
      File.fromUri(dir.resolve('../../shared/b.slint')).readAsStringSync(),
      'b',
    );
    tree.dispose();
    expect(Directory.fromUri(dir.resolve('../../')).existsSync(), isFalse);
  });

  test('binary files survive the round trip', () {
    final bytes = [0x89, 0x50, 0x4e, 0x47, 0, 255];
    final tree = writeSlintTree('', {'img.png': base64Encode(bytes)});
    final dir = File(tree.path).parent;
    expect(File('${dir.path}/img.png').readAsBytesSync(), bytes);
    tree.dispose();
    expect(dir.existsSync(), isFalse);
  });

  test('refuses a path that would leave the tree', () {
    expect(
      () => writeSlintTree('', {'x/../../y.slint': _b64('')}),
      throwsArgumentError,
    );
  });
}
