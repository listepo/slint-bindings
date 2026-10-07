import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Writes [source] and the [files] it reads — base64 by path relative to it,
/// as a generated wrapper's `slintFiles` holds them — into a fresh temporary
/// directory, and returns the path of the entry file, named [name].
///
/// For backends that compile at runtime: the Slint compiler resolves
/// `import`s and `@image-url`s from disk, relative to the file it compiles.
/// The entry sits deep enough that every leading `../` in [files] stays
/// inside the directory; a path that would still leave it is rejected.
///
/// ponytail: the directory is never deleted — one per call, and callers make
/// one call per factory. Clean up if something ever calls this per frame.
/// Handle to a temporary tree written by [writeSlintTree].
///
/// Call [dispose] to delete the directory and everything under it.
class SlintSourceTree {
  SlintSourceTree(this.entryPath, this._rootDir);

  /// Absolute path of the entry `.slint` file.
  final String entryPath;

  final Directory _rootDir;
  var _disposed = false;

  /// Path of the entry `.slint` file — the value [writeSlintTree] used to
  /// return directly.
  String get path => entryPath;

  /// Deletes the temporary tree recursively. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_rootDir.existsSync()) {
      _rootDir.deleteSync(recursive: true);
    }
  }
}

/// Writes [source] and the [files] it reads — base64 by path relative to it,
/// as a generated wrapper's `slintFiles` holds them — into a fresh temporary
/// directory and returns a handle to the entry file.
///
/// Keys in [files] may use `../` segments so a shared UI one package over
/// lands where Slint's import resolver expects it. Paths that would escape the
/// tree are rejected.
SlintSourceTree writeSlintTree(
  String source,
  Map<String, String> files, {
  String name = 'main.slint',
}) {
  final depth = files.keys
      .map((k) => k.split('/').takeWhile((s) => s == '..').length)
      .fold(0, max);
  String entryDir(Uri root) =>
      root.resolve([for (var i = 0; i < depth; i++) 'd$i/'].join()).toString();

  final probe = Uri.parse('file:///root/');
  for (final key in files.keys) {
    if (!Uri.parse(entryDir(probe)).resolve(key).path.startsWith(probe.path)) {
      throw ArgumentError.value(key, 'files', 'leaves the tree');
    }
  }

  final rootDir = Directory.systemTemp.createTempSync('slint_dart_');
  final dir = Uri.parse(entryDir(rootDir.uri));
  for (final MapEntry(:key, :value) in files.entries) {
    File.fromUri(dir.resolve(key))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(base64Decode(value));
  }
  final entry = File.fromUri(dir.resolve(name))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(source);
  return SlintSourceTree(entry.path, rootDir);
}
