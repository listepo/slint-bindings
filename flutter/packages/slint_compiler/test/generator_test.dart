import 'dart:io';

import 'package:slint_compiler/slint_compiler.dart';
import 'package:slint_compiler/src/rust_glue.dart';
import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

/// Mirrors the shape `slint-introspect` reports for the example's todo.slint —
/// arrays always carry their element type, and struct elements drive the
/// generated Rust conversion helpers.
final _todoItem = TypeRef(
  'struct',
  structName: 'TodoItem',
  fields: [
    PropertySchema('title', TypeRef('string')),
    PropertySchema('checked', TypeRef('bool')),
  ],
);

final _schema = SlintSchema([
  ComponentSchema(
    'TodoApp',
    [
      PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
      PropertySchema('title', TypeRef('string')),
    ],
    [
      CallbackSchema('add-todo', [
        PropertySchema('text', TypeRef('string')),
      ], null),
    ],
  ),
]);

String _dart(SlintSchema schema) => generateDartFromSchema(
  schema,
  packageName: 'todo_example',
  assetLibraryPath: 'todo.aot.g.dart',
  sourceName: 'todo.slint',
);

/// Every `slint_aot_*` symbol a generated library binds or a crate exports.
Set<String> _symbols(String source, RegExp pattern) =>
    pattern.allMatches(source).map((m) => m.group(1)!).toSet();

void main() {
  group('generated Dart backend', () {
    test('binds to the code asset the build hook emits', () {
      expect(
        _dart(_schema),
        contains("@ffi.DefaultAsset('package:todo_example/todo.aot.g.dart')"),
      );
    });

    test('declares a factory naming its single component', () {
      final out = _dart(_schema);
      expect(out, contains('final todoAppFactory = SlintCompilerFactory('));
      expect(out, contains("componentName: 'TodoApp'"));
    });

    test('delegates the plumbing instead of regenerating it', () {
      final out = _dart(_schema);
      expect(out, contains("import 'package:slint_compiler/runtime.dart';"));
      // These live in runtime.dart now; regenerating them per file was the
      // duplication that split was meant to remove.
      expect(out, isNot(contains('class _AotComponent')));
      expect(out, isNot(contains('class _AotRenderTarget')));
      expect(out, isNot(contains('jsonDecode')));
    });

    test('wires every op the runtime needs', () {
      final out = _dart(_schema);
      for (final op in [
        'lastError',
        'stringFree',
        'create',
        'free',
        'setSize',
        'render',
        'pointerEvent',
        'keyEvent',
        'getProperty',
        'setProperty',
        'invoke',
        'setCallback',
      ]) {
        expect(out, contains('$op: _'), reason: 'ops bundle is missing $op');
      }
    });

    test('anchors component liveness with @RecordUse on the _new extern', () {
      final out = _dart(_schema);
      // The link hook drops a component's native code when no reachable code
      // records a tear-off of this extern — so the annotation must sit
      // directly on it, and the manifest must predict its exact Dart name.
      expect(
        out,
        contains(
          '@RecordUse()\n'
          '@ffi.Native<ffi.Pointer<ffi.Void> Function()>'
          "(symbol: 'slint_aot_todo_app_new')",
        ),
      );
      expect(
        out,
        contains(
          'external ffi.Pointer<ffi.Void> '
          '${aotNewExternName('TodoApp')}();',
        ),
      );
      expect(out, contains("import 'package:meta/meta.dart' show RecordUse;"));
    });

    test('emits one factory per component', () {
      final out = _dart(
        SlintSchema([
          ComponentSchema('TodoApp', const [], const []),
          ComponentSchema('SettingsPane', const [], const []),
        ]),
      );
      expect(out, contains('final todoAppFactory ='));
      expect(out, contains('final settingsPaneFactory ='));
      expect(out, contains("symbol: 'slint_aot_todo_app_new'"));
      expect(out, contains("symbol: 'slint_aot_settings_pane_new'"));
    });
  });

  group('C ABI agreement', () {
    late String libRs;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('slint_aot_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      emitAotCrate(
        dir,
        files: [
          SlintAotFile(
            stem: 'todo',
            path: '/abs/ui/todo.slint',
            schema: _schema,
          ),
        ],
        slintCoreCratePath: '/nonexistent/slint-dart-core',
      );
      libRs = File('${dir.path}/src/lib.rs').readAsStringSync();
    });

    test('the Rust crate exports exactly the symbols Dart binds', () {
      // A mismatch here is a link failure during the app build — slow, opaque
      // feedback for what is really a naming drift between two emitters.
      final bound = _symbols(
        _dart(_schema),
        RegExp(r"symbol: '(slint_aot_\w+)'"),
      );
      final exported = _symbols(
        libRs,
        RegExp(r'pub extern "C" fn (slint_aot_\w+)'),
      );

      expect(bound, isNotEmpty);
      expect(
        bound.difference(exported),
        isEmpty,
        reason: 'Dart binds symbols the crate does not export',
      );
    });

    test('both sides derive the component prefix the same way', () {
      final prefix = 'slint_aot_${snakeFromPascal('TodoApp')}';
      expect(_dart(_schema), contains("symbol: '${prefix}_new'"));
      expect(libRs, contains('pub extern "C" fn ${prefix}_new'));
    });

    test('the link manifest predicts exactly the exported symbols', () {
      // The link hook keeps only manifest-listed symbols: a symbol the glue
      // exports but the manifest misses would be tree-shaken away (runtime
      // lookup failure); one the manifest predicts but the glue lacks is a
      // -u flag on a missing symbol (link failure).
      final exported = _symbols(
        libRs,
        RegExp(r'pub extern "C" fn (slint_aot_\w+)'),
      );
      final manifest = {...aotSharedSymbols, ...aotComponentSymbols('TodoApp')};
      expect(exported, manifest);
    });
  });
}
