/// `todo-model` → `todoModel`.
String camelCase(String kebab) {
  final parts = kebab.split('-').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return kebab;
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

/// Dart reserved words: never valid as a member or parameter name.
const _reservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', //
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};

/// Members every Dart object has; a generated member with one of these names
/// would be an invalid override.
const objectMembers = {'hashCode', 'runtimeType', 'toString', 'noSuchMethod'};

/// Slint name → Dart identifier: [camelCase], with a trailing `_` when that
/// is a reserved word or one of [taken] — names the generated class already
/// uses for its own members.
String dartName(String slintName, [Set<String> taken = const {}]) {
  final name = camelCase(slintName);
  return _reservedWords.contains(name) || taken.contains(name)
      ? '${name}_'
      : name;
}

/// `add-todo` → `AddTodo`.
String pascalCase(String kebab) => kebab
    .split('-')
    .where((p) => p.isNotEmpty)
    .map((p) => p[0].toUpperCase() + p.substring(1))
    .join();

/// `TodoApp` → `todoAppFactory`: the name `slint_compiler` gives the AOT
/// backend factory it generates, and that the typed wrapper refers to.
String aotFactoryName(String pascal) =>
    '${camelCase(snakeFromPascal(pascal).replaceAll('_', '-'))}Factory';

/// Slint name → Rust identifier, mirroring i-slint-compiler's `ident()`:
/// dashes become underscores.
String rustIdent(String slintName) => slintName.replaceAll('-', '_');

/// `align_center` → `Align_center`, mirroring i-slint-compiler enum variants.
String enumVariantRustIdent(String slintVariant) {
  final b = StringBuffer();
  var nextUpper = true;
  for (final unit in slintVariant.runes) {
    final ch = String.fromCharCode(unit);
    if (ch == '-') {
      nextUpper = true;
    } else if (nextUpper) {
      b.write(ch.toUpperCase());
      nextUpper = false;
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

/// `TodoApp` → `todo_app` (for symbol prefixes and helper fn names).
String snakeFromPascal(String pascal) {
  final b = StringBuffer();
  for (var i = 0; i < pascal.length; i++) {
    final ch = pascal[i];
    final isUpper = ch.toUpperCase() == ch && ch.toLowerCase() != ch;
    if (isUpper && i > 0) b.write('_');
    b.write(ch.toLowerCase());
  }
  return b.toString().replaceAll('-', '_');
}
