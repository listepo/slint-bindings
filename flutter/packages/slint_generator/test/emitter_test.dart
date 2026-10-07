import 'dart:convert';
import 'dart:io';

import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

/// Matches generated source by content, ignoring how the formatter wrapped
/// it — the tests are about what is emitted, not where the line breaks fall.
Matcher containsCode(String snippet) => predicate<String>(
  (out) => _flat(out).contains(_flat(snippet)),
  'contains code `$snippet`',
);

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// A realistic named struct — `slint-introspect` never reports an anonymous
/// one, and never an array without an element type.
final _todoItem = TypeRef(
  'struct',
  structName: 'TodoItem',
  fields: [
    PropertySchema('title', TypeRef('string')),
    PropertySchema('checked', TypeRef('bool')),
  ],
);

SlintSchema _schema({
  List<PropertySchema> properties = const [],
  List<CallbackSchema> callbacks = const [],
}) => SlintSchema([ComponentSchema('TodoApp', properties, callbacks)]);

String _wrapper(
  SlintSchema schema, {
  String? aotLibrary,
  bool interpreter = false,
  String? assetPath = 'ui/todo.slint',
  String slintSource = 'export component TodoApp {}',
}) => generateWrapperLibrary(
  schema,
  sourceName: 'todo.slint',
  slintSource: slintSource,
  assetPath: assetPath,
  aotLibrary: aotLibrary,
  interpreter: interpreter,
);

void main() {
  group('dartStringLiteral', () {
    // The whole .slint source is embedded through this. A miss here produces a
    // generated file that does not parse, or one that silently interpolates.
    test(r'escapes $ so Dart does not interpolate it', () {
      expect(dartStringLiteral(r'cost: $5'), r'"cost: \$5"');
      expect(dartStringLiteral(r'${expr}'), r'"\${expr}"');
    });

    test('escapes quotes and backslashes', () {
      expect(dartStringLiteral('say "hi"'), r'"say \"hi\""');
      expect(dartStringLiteral(r'a\b'), r'"a\\b"');
    });

    test('escapes a backslash followed by a dollar independently', () {
      // Source chars \ then $ must survive as an escaped backslash and an
      // escaped dollar, not as one escape swallowing the other.
      expect(dartStringLiteral(r'\$'), r'"\\\$"');
    });

    test('escapes newlines rather than emitting a multi-line literal', () {
      expect(dartStringLiteral('a\nb'), r'"a\nb"');
    });

    test('wraps the result in quotes', () {
      final out = dartStringLiteral('plain');
      expect(out.startsWith('"'), isTrue);
      expect(out.endsWith('"'), isTrue);
    });
  });

  group('backend defaulting', () {
    test('with neither backend, create requires an explicit factory', () {
      final out = _wrapper(_schema());
      expect(
        out,
        containsCode('static TodoApp create(SlintComponentFactory factory)'),
      );
      expect(out, isNot(containsCode('defaultFactory')));
      expect(out, isNot(containsCode('_useCompiled')));
      expect(out, isNot(containsCode('slint_interpreter')));
      expect(out, isNot(containsCode('aot.')));
    });

    test('with only the interpreter, it is the default', () {
      final out = _wrapper(_schema(), interpreter: true);
      expect(
        out,
        containsCode(
          "import 'package:slint_interpreter/slint_interpreter.dart';",
        ),
      );
      // (the formatter may wrap the argument with a trailing comma)
      expect(
        out,
        containsCode('defaultFactory = SlintInterpreterFactory(_source'),
      );
      expect(
        out,
        containsCode('static TodoApp create([SlintComponentFactory? factory])'),
      );
      expect(out, isNot(containsCode('_useCompiled')));
    });

    test('with only the AOT backend, it is the default', () {
      final out = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(out, containsCode("import 'todo.aot.g.dart' as aot;"));
      expect(out, containsCode('defaultFactory = aot.todoAppFactory'));
      expect(out, isNot(containsCode('_useCompiled')));
      expect(out, isNot(containsCode('SlintInterpreterFactory')));
    });

    test('with both, the default follows the build mode', () {
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(out, containsCode("bool.fromEnvironment('dart.vm.product')"));
      expect(out, containsCode("bool.fromEnvironment('dart.vm.profile')"));
      expect(
        out,
        containsCode(
          'defaultFactory = _useCompiled ? aot.todoAppFactory : SlintInterpreterFactory(_source, files: _files)',
        ),
      );
    });

    test('a wrapper with a default backend can be loaded by path', () {
      final out = _wrapper(_schema(), interpreter: true);
      expect(out, containsCode("static const assetPath = 'ui/todo.slint'"));
      // Synchronous: no Future, no await — the instance is usable on return.
      expect(out, containsCode('static TodoApp load(String path) {'));
      expect(out, isNot(containsCode('Future<')));
      expect(out, isNot(containsCode('await ')));
    });

    test('load goes through the mode-split defaultFactory', () {
      // `_useCompiled` is a const, so a release build initializes
      // defaultFactory to the AOT factory and the interpreter branch is dead
      // code. load must reuse it rather than building a factory per call —
      // a fresh SlintInterpreterFactory(_source) would own a fresh engine
      // each time.
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(
        out,
        containsCode(
          'defaultFactory = _useCompiled ? aot.todoAppFactory : SlintInterpreterFactory(_source, files: _files)',
        ),
      );
      expect(
        out,
        containsCode(
          'return TodoApp(defaultFactory.instantiate(componentName));',
        ),
      );
      expect(
        out,
        isNot(containsCode('SlintInterpreterFactory(_source).instantiate')),
      );
    });

    test('the source is mentioned only where the interpreter is built', () {
      // What keeps the `.slint` text out of a release binary: `_source` must
      // reach the interpreter through its factory's constructor inside the
      // dead `_useCompiled` branch, never through `instantiate`, which both
      // modes call. The declaration, the public `slintSource` alias, and the
      // one factory construction are the whole budget.
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(out, isNot(containsCode('instantiate(_source')));
      expect(RegExp(r'\b_source\b').allMatches(out).length, 3);
    });

    test('imports and images travel with the source, the same way', () {
      // The interpreter compiles the embedded source, not the file, so what
      // it imports or references has to be embedded too — and, like the
      // source, reach it only through the dead-in-release factory branch.
      final out = generateWrapperLibrary(
        _schema(),
        sourceName: 'todo.slint',
        slintSource: 'x',
        assetPath: 'ui/todo.slint',
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
        slintFiles: {
          '../shared/view.slint': utf8.encode('export component V {}'),
          'img/a.png': [0x89, 0x50],
        },
      );
      expect(
        out,
        containsCode(
          '"../shared/view.slint": '
          '"${base64Encode(utf8.encode('export component V {}'))}"',
        ),
      );
      expect(out, containsCode('"img/a.png": "iVA="'));
      expect(out, containsCode('static const slintFiles = _files;'));
      expect(RegExp(r'\b_files\b').allMatches(out).length, 3);
    });

    test('load refuses a path this wrapper was not generated from', () {
      // Silently ignoring it would make `load('other.slint')` quietly render
      // the wrong UI.
      final out = _wrapper(_schema(), interpreter: true);
      expect(out, containsCode('if (path != assetPath)'));
      expect(out, containsCode('ArgumentError.value('));
    });

    test('load takes exactly one .slint file', () {
      // One String, checked for the extension before anything else, so a
      // `.txt` or an empty path fails with its own message rather than the
      // generic "generated from" one.
      final out = _wrapper(_schema(), interpreter: true);
      expect(out, containsCode('static TodoApp load(String path) {'));
      expect(out, isNot(containsCode('load(List<String>')));
      expect(out, containsCode("if (!path.endsWith('.slint'))"));
      expect(
        out,
        containsCode("ArgumentError.value(path, 'path', 'not a .slint file')"),
      );
    });

    test('register makes SlintComponent.load answer the wrapper\'s path', () {
      // Per component, never per file: a file-level registration would
      // reference every component's AOT factory and defeat tree-shaking.
      final out = _wrapper(
        _schema(),
        aotLibrary: 'todo.aot.g.dart',
        interpreter: true,
      );
      expect(out, containsCode('static void register() =>'));
      expect(
        out,
        containsCode(
          'SlintComponent.register<TodoApp>(assetPath, componentName, create)',
        ),
      );
      expect(out, isNot(containsCode('registerTodo')));
    });

    test('without a backend there is nothing to register', () {
      expect(_wrapper(_schema()), isNot(containsCode('register(')));
    });

    test('generated code never reads the asset bundle', () {
      // A wrapper that read its own `assetPath` would force every app to
      // bundle its `.slint`, which then ships the UI source in release for
      // nothing. Reading an asset is SlintComponent.load's job, for a file
      // no wrapper was generated from.
      for (final wrapper in [
        _wrapper(_schema(), interpreter: true),
        _wrapper(_schema(), interpreter: true, aotLibrary: 'todo.aot.g.dart'),
        _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart'),
      ]) {
        expect(wrapper, isNot(containsCode('rootBundle')));
        expect(wrapper, isNot(containsCode('loadString')));
        expect(wrapper, isNot(containsCode('flutter/services.dart')));
      }
    });

    test('the wrapper is itself a component, so it goes where one goes', () {
      final out = _wrapper(_schema(), interpreter: true);
      expect(
        out,
        containsCode('class TodoApp implements SlintSoftwareComponent'),
      );
      expect(
        out,
        containsCode(
          'Object? getProperty(String name) => component.getProperty(name)',
        ),
      );
      expect(
        out,
        containsCode(
          'void setProperty(String name, Object? value) => component.setProperty(name, value)',
        ),
      );
      expect(
        out,
        containsCode(
          'void setCallbackHandler(String name, SlintCallbackHandler handler) => component.setCallbackHandler(name, handler)',
        ),
      );
      expect(
        out,
        containsCode(
          'Object? invokeCallback(String name, List<Object?> arguments) => component.invokeCallback(name, arguments)',
        ),
      );
    });

    test('without a backend there is nothing for load to run on', () {
      final out = _wrapper(_schema());
      expect(out, isNot(containsCode('static TodoApp load(')));
      expect(out, isNot(containsCode('assetPath')));
    });

    test('the AOT default names the factory slint_compiler generates', () {
      final out = _wrapper(_schema(), aotLibrary: 'todo.aot.g.dart');
      expect(out, containsCode('aot.${aotFactoryName('TodoApp')}'));
    });
  });

  group('typed members', () {
    test('maps each supported property kind to a Dart type', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema('ratio', TypeRef('float')),
            PropertySchema('count', TypeRef('int')),
            PropertySchema('title', TypeRef('string')),
            PropertySchema('checked', TypeRef('bool')),
            PropertySchema('width', TypeRef('length')),
            PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
            PropertySchema('item', _todoItem),
          ],
        ),
      );

      expect(out, containsCode('double get ratio'));
      expect(out, containsCode('int get count'));
      expect(out, containsCode('String get title'));
      expect(out, containsCode('bool get checked'));
      expect(out, containsCode('double get width'));
      expect(
        out,
        containsCode('late final todoModel = SlintListModel<TodoItem>'),
      );
      expect(out, containsCode('TodoItem get item'));
    });

    test('converts values in both directions at the boundary', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema('count', TypeRef('int')),
            PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
          ],
        ),
      );

      // The bridge speaks JSON: numbers arrive as `num`, structs as maps.
      expect(
        out,
        containsCode("(component.getProperty('count') as num).toInt()"),
      );
      expect(
        out,
        containsCode('TodoItem.fromSlint(e as Map<Object?, Object?>)'),
      );
      expect(
        out,
        containsCode("(value) => component.setProperty('todo-model', value)"),
      );
      expect(out, containsCode('(e) => e.toSlint()'));
    });

    test('casts rather than rebuilds a list that needs no conversion', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema(
              'tags',
              TypeRef('array', element: TypeRef('string')),
            ),
          ],
        ),
      );
      expect(out, containsCode('late final tags = SlintListModel<String>'));
      expect(out, containsCode('(e) => e as String'));
      expect(
        out,
        containsCode("(value) => component.setProperty('tags', value)"),
      );
    });

    test('accessors keep the kebab-case name on the wire', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema('todo-model', TypeRef('array', element: _todoItem)),
          ],
        ),
      );
      expect(out, containsCode("() => component.getProperty('todo-model')"));
      expect(
        out,
        containsCode("(value) => component.setProperty('todo-model', value)"),
      );
    });

    test('emits a typed on/invoke pair per callback', () {
      final out = _wrapper(
        _schema(
          callbacks: [
            CallbackSchema('add-todo', [
              PropertySchema('text', TypeRef('string')),
            ], null),
          ],
        ),
      );
      expect(
        out,
        containsCode('void onAddTodo(void Function(String text) handler)'),
      );
      expect(out, containsCode('void invokeAddTodo(String text)'));
      expect(out, containsCode("invokeCallback('add-todo', [text])"));
      // The untyped bridge argument list is unpacked for the handler.
      expect(out, containsCode('handler(arguments[0] as String)'));
    });

    test(
      'names callback arguments positionally when the compiler has no name',
      () {
        final out = _wrapper(
          _schema(
            callbacks: [
              CallbackSchema('toggle-todo', [
                PropertySchema('', TypeRef('int')),
                PropertySchema('', TypeRef('bool')),
              ], null),
            ],
          ),
        );
        expect(out, containsCode('void Function(int arg1, bool arg2) handler'));
        expect(out, containsCode('void invokeToggleTodo(int arg1, bool arg2)'));
      },
    );

    test('a callback return value is typed and converted', () {
      final out = _wrapper(
        _schema(callbacks: [CallbackSchema('pick', const [], _todoItem)]),
      );
      expect(out, containsCode('void onPick(TodoItem Function() handler)'));
      expect(out, containsCode('(arguments) => handler().toSlint()'));
      expect(out, containsCode('TodoItem invokePick()'));
      expect(
        out,
        containsCode(
          "TodoItem.fromSlint(component.invokeCallback('pick', []) "
          'as Map<Object?, Object?>',
        ),
      );
    });

    test('emits typed color and brush accessors', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema('accent', TypeRef('color')),
            PropertySchema('fill', TypeRef('brush')),
            PropertySchema('thumb', TypeRef('image')),
          ],
        ),
      );
      expect(out, containsCode('SlintColor get accent'));
      expect(out, containsCode('SlintBrush get fill'));
      expect(out, containsCode('String get thumb'));
      expect(
        out,
        containsCode(
          "SlintColor.fromSlint(component.getProperty('accent') as String)",
        ),
      );
      expect(
        out,
        containsCode("component.setProperty('accent', value.toSlint())"),
      );
      expect(
        out,
        containsCode(
          "SlintBrush.fromSlint(component.getProperty('fill') as String)",
        ),
      );
      expect(out, containsCode("component.setProperty('thumb', value)"));
    });

    test('emits a Dart enum with fromSlint and toSlint', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema(
              'state',
              TypeRef('enum', enumName: 'Status', variants: ['active', 'done']),
            ),
          ],
        ),
      );
      expect(out, containsCode('enum Status {'));
      expect(out, containsCode("active('active')"));
      expect(out, containsCode("done('done')"));
      expect(out, containsCode('factory Status.fromSlint(String wire)'));
      expect(
        out,
        containsCode(
          "Status.fromSlint(component.getProperty('state') as String)",
        ),
      );
      expect(
        out,
        containsCode("component.setProperty('state', value.toSlint())"),
      );
    });
  });

  group('globals', () {
    test('emits an UnsupportedError stub per exported global', () {
      final out = generateWrapperLibrary(
        SlintSchema(
          const [],
          globals: [
            GlobalSchema('AppState', [PropertySchema('count', TypeRef('int'))]),
          ],
        ),
        sourceName: 'app.slint',
        slintSource: 'x',
      );
      expect(out, containsCode('class AppState {'));
      expect(
        out,
        containsCode(
          'Global property accessors are not yet supported by the interpreter backend',
        ),
      );
    });
  });

  group('struct classes', () {
    test('emits one class per named struct, deduped across components', () {
      final out = generateWrapperLibrary(
        SlintSchema([
          ComponentSchema('TodoApp', [
            PropertySchema('item', _todoItem),
          ], const []),
          ComponentSchema('SettingsPane', [
            PropertySchema('other', _todoItem),
          ], const []),
        ]),
        sourceName: 'app.slint',
        slintSource: 'x',
      );
      expect('class TodoItem {'.allMatches(out).length, 1);
    });

    test('gives the class a const constructor and typed final fields', () {
      final out = _wrapper(
        _schema(properties: [PropertySchema('item', _todoItem)]),
      );
      expect(
        out,
        containsCode(
          'const TodoItem({required this.title, '
          'required this.checked});',
        ),
      );
      expect(out, containsCode('final String title;'));
      expect(out, containsCode('final bool checked;'));
    });

    test('roundtrips through the Slint field names, not the Dart ones', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema(
              'item',
              TypeRef(
                'struct',
                structName: 'Row',
                fields: [PropertySchema('is-done', TypeRef('bool'))],
              ),
            ),
          ],
        ),
      );
      expect(out, containsCode('final bool isDone;'));
      expect(out, containsCode("isDone: value['is-done'] as bool"));
      expect(out, containsCode("'is-done': isDone"));
    });

    test('collects structs nested inside other structs', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema(
              'group',
              TypeRef(
                'struct',
                structName: 'Group',
                fields: [
                  PropertySchema('items', TypeRef('array', element: _todoItem)),
                ],
              ),
            ),
          ],
        ),
      );
      expect(out, containsCode('class Group {'));
      expect(out, containsCode('class TodoItem {'));
      expect(out, containsCode('final List<TodoItem> items;'));
    });

    test('compares list fields element-wise, not by identity', () {
      final out = _wrapper(
        _schema(
          properties: [
            PropertySchema(
              'group',
              TypeRef(
                'struct',
                structName: 'Group',
                fields: [
                  PropertySchema('items', TypeRef('array', element: _todoItem)),
                ],
              ),
            ),
          ],
        ),
      );
      expect(out, containsCode('bool _eq(Object? a, Object? b)'));
      expect(out, containsCode('_eq(items, other.items)'));
    });

    test('skips the deep helpers when no struct holds a list', () {
      final out = _wrapper(
        _schema(properties: [PropertySchema('item', _todoItem)]),
      );
      expect(out, isNot(containsCode('bool _eq(')));
      expect(out, containsCode('title == other.title'));
    });

    test('emits no struct classes for a struct-free component', () {
      final out = _wrapper(
        _schema(properties: [PropertySchema('title', TypeRef('string'))]),
      );
      expect(out, isNot(containsCode('fromSlint')));
    });
  });

  group('Slint names Dart cannot take as-is', () {
    // Slint allows dashes, Dart keywords, and names the wrapper itself uses;
    // any of these used to emit a library that does not compile.
    final schema = SlintSchema([
      ComponentSchema(
        'my-app',
        [
          PropertySchema('component', TypeRef('int')),
          PropertySchema('class', TypeRef('string')),
          PropertySchema('on-go', TypeRef('bool')),
          PropertySchema('hash-code', TypeRef('int')),
          PropertySchema(
            'row',
            TypeRef(
              'struct',
              structName: 'Row',
              fields: [
                PropertySchema('copy-with', TypeRef('bool')),
                PropertySchema('in', TypeRef('int')),
              ],
            ),
          ),
        ],
        [
          CallbackSchema('go', [
            PropertySchema('handler', TypeRef('int')),
          ], null),
          CallbackSchema('callback', const [], null),
        ],
      ),
    ]);
    String generate() => generateWrapperLibrary(
      schema,
      sourceName: 'my.slint',
      slintSource: 'x',
      assetPath: 'ui/my.slint',
    );

    test('escapes each clash with a trailing underscore', () {
      final out = generate();
      expect(
        out,
        containsCode('class MyApp implements SlintSoftwareComponent'),
      );
      expect(out, containsCode("static const componentName = 'my-app';"));
      expect(out, containsCode('int get component_'));
      expect(out, containsCode('String get class_'));
      expect(out, containsCode('bool get onGo_'));
      expect(out, containsCode('int get hashCode_'));
      expect(
        out,
        containsCode('void onGo(void Function(int handler_) handler)'),
      );
      expect(out, containsCode('void invokeCallback_()'));
      expect(out, containsCode('final bool copyWith_;'));
      expect(out, containsCode('final int in_;'));
      // The wire keeps the Slint names.
      expect(out, containsCode("component.getProperty('component')"));
      expect(out, containsCode("value['copy-with']"));
    });

    test('the escaped library analyzes clean', () async {
      // Inside the package, so its imports resolve through its dependencies.
      final dir = Directory.current.createTempSync('names_check_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/my.g.dart').writeAsStringSync(generate());
      final result = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        dir.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('the wrapper takes an instance from any backend', () {
    // A texture backend (slint_skia) or a headless one has no software
    // target, yet app code still drives it through the typed members.
    final out = _wrapper(_schema());
    expect(out, containsCode('final SlintComponent component;'));
    expect(
      out,
      containsCode('final SlintSoftwareComponent c => c.renderTarget'),
    );
  });

  test('embeds the source and the component name', () {
    final out = _wrapper(_schema(), slintSource: 'export component TodoApp {}');
    expect(out, containsCode(r'const _source = "export component TodoApp {}"'));
    expect(out, containsCode("static const componentName = 'TodoApp';"));
    expect(out, containsCode('static const slintSource = _source;'));
  });

  test('emits one class per exported component', () {
    final out = generateWrapperLibrary(
      SlintSchema([
        ComponentSchema('TodoApp', const [], const []),
        ComponentSchema('SettingsPane', const [], const []),
      ]),
      sourceName: 'app.slint',
      slintSource: 'x',
    );
    expect(
      out,
      containsCode('class TodoApp implements SlintSoftwareComponent {'),
    );
    expect(
      out,
      containsCode('class SettingsPane implements SlintSoftwareComponent {'),
    );
  });
}
