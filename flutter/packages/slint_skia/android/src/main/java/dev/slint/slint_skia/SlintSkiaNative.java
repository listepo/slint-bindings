package dev.slint.slint_skia;

import android.view.Surface;

/** The JNI half of slint-skia-ffi (rust/src/lib.rs). */
final class SlintSkiaNative {
  static {
    // The same library Dart loaded as the package's native asset; loading it
    // here registers it with this class loader for JNI lookup.
    System.loadLibrary("slint_skia_ffi");
  }

  private SlintSkiaNative() {}

  /**
   * Acquires the ANativeWindow behind {@code surface}: one reference, which
   * {@code slint_skia_instance_attach_android} takes over. 0 on failure.
   */
  static native long nativeWindowFromSurface(Surface surface);
}
