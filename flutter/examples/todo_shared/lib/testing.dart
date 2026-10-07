/// Test helpers shared by the `examples/todo` and `examples/todo_skia` test
/// suites. Not exported from `todo_shared.dart`: apps import it from tests
/// only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _stale = 'lib/todo.g.dart is stale — run `dart run build_runner build`';

/// Registers tests that the generated wrapper's embedded UI —
/// `TodoApp.slintSource` as [embeddedSource], `TodoApp.slintFiles` as
/// [embeddedFiles] — still equals `ui/todo.slint` and everything it imports
/// on disk.
///
/// The wrapper embeds copies, so an edit without a rebuild leaves the app
/// silently running the old UI. Nothing else catches that — the stale copy
/// still compiles. The shared list UI is the easy one to miss: it lives in
/// another package, so editing it rebuilds neither app.
void testWrapperEmbedsCurrentSlint(
  String embeddedSource,
  Map<String, String> embeddedFiles,
) {
  test('the generated wrapper embeds the current todo.slint', () {
    expect(
      embeddedSource,
      File('ui/todo.slint').readAsStringSync(),
      reason: _stale,
    );
  });

  test('... and the current copy of the shared list UI it imports', () {
    expect(
      embeddedFiles.keys,
      contains('../../todo_shared/ui/todo_view.slint'),
    );
    for (final MapEntry(key: path, value: bytes) in embeddedFiles.entries) {
      expect(
        base64Decode(bytes),
        File('ui/$path').readAsBytesSync(),
        reason: '$path: $_stale',
      );
    }
  });
}
