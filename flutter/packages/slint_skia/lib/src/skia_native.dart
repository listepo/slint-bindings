// Entry points of slint-skia-ffi that bindings.g.dart does not carry,
// declared by hand. The attach and pixel calls exist only on their own
// platform (behind `#if` in the header), so ffigen, which parses the header
// for one host, cannot generate them; ffigen.yaml excludes every name
// declared here so a regeneration never duplicates one. `@Native` binds
// lazily: a symbol another platform lacks is fine as long as nothing calls
// it there.
//
// The Dart names are the C symbols, as in bindings.g.dart.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:slint_skia/src/bindings.g.dart')
library;

import 'dart:ffi';

/// Drops the attached surface and what it rendered into.
@Native<Bool Function(Pointer<Void>)>()
external bool slint_skia_instance_detach(Pointer<Void> instance);

/// iOS/macOS: renders into an `id<MTLTexture>` (BGRA8Unorm, render target)
/// made on `device`, with commands on `queue`.
@Native<
  Bool Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Uint32,
    Uint32,
  )
>()
external bool slint_skia_instance_attach_metal(
  Pointer<Void> instance,
  Pointer<Void> device,
  Pointer<Void> queue,
  Pointer<Void> texture,
  int width,
  int height,
);

/// Android: renders into an `ANativeWindow*` (one acquired reference, which
/// the call takes over).
@Native<Bool Function(Pointer<Void>, Pointer<Void>, Uint32, Uint32)>()
external bool slint_skia_instance_attach_android(
  Pointer<Void> instance,
  Pointer<Void> window,
  int width,
  int height,
);

/// Windows: renders into a new D3D12 shared texture on the adapter with this
/// LUID; returns its NT handle, null on error.
@Native<Pointer<Void> Function(Pointer<Void>, Uint32, Int32, Uint32, Uint32)>()
external Pointer<Void> slint_skia_instance_attach_d3d(
  Pointer<Void> instance,
  int luidLow,
  int luidHigh,
  int width,
  int height,
);

/// Linux: renders offscreen through headless EGL and reads every frame back.
@Native<Bool Function(Pointer<Void>, Uint32, Uint32)>()
external bool slint_skia_instance_attach_gl(
  Pointer<Void> instance,
  int width,
  int height,
);

/// Linux: the last frame (RGBA8888 premultiplied), borrowed until the next
/// render, attach, detach or free; null before the first frame.
@Native<Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)>()
external Pointer<Uint8> slint_skia_instance_pixels(
  Pointer<Void> instance,
  Pointer<Size> length,
);
