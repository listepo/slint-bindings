/// Slint Skia FFI plugin — GPU-accelerated rendering via i-slint-renderer-skia.
///
/// Provides [SkiaSlintEngine], [SkiaSlintComponent], and [SkiaTextureRenderTarget]
/// for building Slint applications with GPU rendering in Flutter.
library;

export 'src/skia_engine.dart'
    show
        SkiaSlintEngine,
        SkiaSlintComponent,
        SkiaSlintComponentDefinition,
        SkiaTextureRenderTarget;
