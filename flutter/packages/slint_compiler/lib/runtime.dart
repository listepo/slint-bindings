/// The runtime half of the AOT backend: [SlintCompilerFactory] and the
/// [SlintComponentOps] bundle a generated `*.aot.g.dart` fills in.
///
/// Separate from `slint_compiler.dart` so apps and generated code import only
/// this, not the build-time generator API.
library;

export 'src/runtime.dart';
