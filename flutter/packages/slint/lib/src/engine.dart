import 'component.dart';

/// Compiles `.slint` source into component definitions.
///
/// Mirrors `slint_interpreter::Compiler`.
abstract interface class SlintEngine {
  /// Compiles [source] and returns the exported component definitions.
  ///
  /// [path] is used for diagnostics and resolving relative imports.
  ///
  /// Synchronous: compilation is one FFI call, so there is nothing to wait
  /// for and a component can be on screen in the same frame it was asked for.
  List<SlintComponentDefinition> compile(String source, {String? path});

  void dispose();
}
