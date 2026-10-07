/// Slint runtime for Flutter via Rust FFI — slint-interpreter + software renderer.
///
/// Provides software-rendered [SlintEngine], [SlintComponent], and [SlintSoftwareRenderTarget]
/// implementations backed by Rust's Slint interpreter and MinimalSoftwareWindow.
library;

export 'src/factory.dart';
export 'src/interpreter_engine.dart';
