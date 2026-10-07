import 'dart:typed_data';

import 'component.dart';
import 'events.dart';

/// A component instance bound to a renderable surface.
abstract interface class SlintRenderTarget {
  SlintComponent get component;

  int get width;
  int get height;

  void resize(int width, int height);

  /// Renders a frame if the scene is dirty. Returns true when new content
  /// was produced.
  bool render();

  void dispatchPointerEvent(SlintPointerEvent event);

  void dispatchKeyEvent(SlintKeyEvent event);

  void dispose();
}

/// Software-rendered target exposing the frame as premultiplied RGBA8888
/// pixels (`slint_interpreter`).
abstract interface class SlintSoftwareRenderTarget
    implements SlintRenderTarget {
  Uint8List get pixels;
}

/// GPU-rendered target exposing a Flutter external-texture id (`slint_skia`).
abstract interface class SlintTextureRenderTarget implements SlintRenderTarget {
  int get textureId;
}
