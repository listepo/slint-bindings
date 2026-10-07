/// The runtime half of the generated wrappers: the [SlintComponentFactory]
/// base class that a `*.g.dart` takes and every backend extends.
///
/// Separate from `slint_generator.dart` so apps and generated code import only
/// this, not the build-time schema/emitter API.
library;

export 'src/factory.dart';
