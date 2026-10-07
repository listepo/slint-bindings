/// Flutter-free core of the `slint` package: component/engine interfaces,
/// render targets, and input event encoding.
///
/// Usable from plain Dart (CLIs, code generators, tests). The `SlintView`
/// widget lives in `package:slint/slint.dart`.
library;

export 'src/component.dart';
export 'src/engine.dart';
export 'src/events.dart';
export 'src/native_guard.dart';
export 'src/render_target.dart';
export 'src/slint_brush.dart';
export 'src/slint_color.dart';
export 'src/slint_model.dart';
export 'src/slint_tree.dart';
