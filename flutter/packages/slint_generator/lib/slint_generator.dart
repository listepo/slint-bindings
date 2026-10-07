/// Shared `.slint` → Dart code generation.
///
/// [introspectSlint] extracts a typed [SlintSchema] from a `.slint` file (via
/// the `slint-introspect` Rust tool), and [generateWrapperLibrary] turns that
/// schema into typed Dart wrappers that drive any backend through a
/// `SlintComponentFactory`. `slint_compiler` builds on both for its AOT path.
library;

export 'src/emitter.dart';
export 'src/factory.dart';
export 'src/introspect.dart';
export 'src/names.dart';
export 'src/package_config.dart';
export 'src/schema.dart';
