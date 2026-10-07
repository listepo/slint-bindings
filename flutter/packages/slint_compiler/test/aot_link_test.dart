import 'package:record_use/record_use.dart';
import 'package:slint_compiler/aot_build.dart'
    show nativeStaticLibsNote, splitLinkFlags;
import 'package:slint_compiler/aot_link.dart';
import 'package:test/test.dart';

const _lib = 'package:todo_example/todo.aot.g.dart';

Map<String, Object?> _component(String name, String newExtern) => {
  'name': name,
  'library': _lib,
  'newExtern': newExtern,
  'symbols': ['sym_${name}_new', 'sym_${name}_render'],
};

/// A recording whose only content is tear-offs/calls of [externNames] in
/// [_lib] — the shape the AOT compiler produces for the generated externs.
Recordings _recordings(List<String> externNames) => Recordings(
  calls: {
    for (final name in externNames) Method(name, const Library(_lib)): const [],
  },
  instances: const {},
);

void main() {
  final components = [
    _component('TodoApp', '_todoAppNew'),
    _component('SettingsPane', '_settingsPaneNew'),
  ];

  group('usedComponentNames', () {
    test('keeps everything when the toolchain recorded nothing', () {
      expect(usedComponentNames(null, components), {'TodoApp', 'SettingsPane'});
    });

    test('keeps only components whose _new extern was recorded', () {
      expect(usedComponentNames(_recordings(['_todoAppNew']), components), {
        'TodoApp',
      });
    });

    test('ignores recordings from other libraries', () {
      final other = Recordings(
        calls: {
          Method('_todoAppNew', const Library('package:other/x.dart')):
              const [],
        },
        instances: const {},
      );
      // No extern of ours referenced at all → the zero-hit guard keeps all.
      expect(usedComponentNames(other, components), {
        'TodoApp',
        'SettingsPane',
      });
    });

    test('a recording that misses every extern keeps everything', () {
      // An app using no component would not depend on this package; zero hits
      // means the recording missed the FFI tear-offs, and dropping every
      // component on that evidence would break the app.
      expect(usedComponentNames(_recordings(['_unrelated']), components), {
        'TodoApp',
        'SettingsPane',
      });
    });
  });

  group('partitionLinkFlags', () {
    test('splits frameworks, libraries, and passthrough flags', () {
      final groups = partitionLinkFlags([
        '-framework',
        'CoreFoundation',
        '-lSystem',
        '-lc',
        '-framework',
        'CoreText',
        '-Wl,-something',
      ]);
      expect(groups.frameworks, ['CoreFoundation', 'CoreText']);
      expect(groups.libraries, ['System', 'c']);
      expect(groups.other, ['-Wl,-something']);
    });

    test('preserves order and duplication of libraries', () {
      // rustc: "The order and any duplication can be significant on some
      // platforms."
      final groups = partitionLinkFlags(['-lgcc_s', '-lc', '-lgcc_s', '-ldl']);
      expect(groups.libraries, ['gcc_s', 'c', 'gcc_s', 'dl']);
    });

    test('a bare -l is not a library', () {
      expect(partitionLinkFlags(['-l']).other, ['-l']);
    });
  });

  group('nativeStaticLibsNote', () {
    test('extracts the flag list from cargo output', () {
      expect(
        nativeStaticLibsNote('''
   Compiling slint-dart-aot v0.1.0
note: Link against the following native artifacts when linking against this static library. The order and any duplication can be significant on some platforms.

note: native-static-libs: -framework CoreFoundation -lSystem -lc
    Finished `release` profile [optimized] target(s) in 3m 41s
'''),
        ['-framework', 'CoreFoundation', '-lSystem', '-lc'],
      );
    });

    test('the last note wins', () {
      expect(
        nativeStaticLibsNote(
          'note: native-static-libs: -la\n'
          'note: native-static-libs: -lb\n',
        ),
        ['-lb'],
      );
    });

    test('null when cargo did not rerun rustc', () {
      expect(nativeStaticLibsNote('Finished `release` in 0.1s\n'), isNull);
    });

    test('an empty note is an empty list, not null', () {
      expect(nativeStaticLibsNote('note: native-static-libs:  \n'), isEmpty);
    });

    test('keeps quoted paths with spaces whole', () {
      expect(
        nativeStaticLibsNote(
          'note: native-static-libs: -L "/Users/me/My SDK/lib" -lSystem\n',
        ),
        ['-L', '/Users/me/My SDK/lib', '-lSystem'],
      );
    });
  });

  group('splitLinkFlags', () {
    test('splits on whitespace', () {
      expect(splitLinkFlags('-la  -lb\t-lc'), ['-la', '-lb', '-lc']);
    });

    test('keeps quoted segments with spaces whole', () {
      expect(splitLinkFlags('-L "/Users/me/My SDK/lib" \'-framework\''), [
        '-L',
        '/Users/me/My SDK/lib',
        '-framework',
      ]);
    });

    test('backslash escapes the next character', () {
      expect(splitLinkFlags(r'-L My\ SDK/lib'), [r'-L', r'My SDK/lib']);
    });

    test('an unterminated quote runs to the end of the line', () {
      expect(splitLinkFlags('"/Users/me/My SDK/lib'), ['/Users/me/My SDK/lib']);
    });

    test('empty segments add no flags', () {
      expect(splitLinkFlags('   '), isEmpty);
    });
  });
}
