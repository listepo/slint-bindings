package dev.slint.slint_skia;

import android.view.Surface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.Map;

/**
 * The platform half of SkiaTextureRenderTarget on Android: a Flutter
 * SurfaceProducer per texture, whose Surface slint-skia-ffi renders into
 * through Slint's EGL surface (rust/src/platform/android.rs).
 *
 * <p>Channel {@code slint_skia}: create / allocate (sets the size, returns
 * the ANativeWindow) / dispose. Tells Dart {@code surfaceCleanup} when the
 * surface goes away and {@code surfaceAvailable} when a new one can be
 * allocated.
 */
public final class SlintSkiaPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;
  private TextureRegistry textures;
  private final Map<Long, TextureRegistry.SurfaceProducer> producers = new HashMap<>();

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    textures = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), "slint_skia");
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    for (TextureRegistry.SurfaceProducer producer : producers.values()) {
      producer.release();
    }
    producers.clear();
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    if (call.method.equals("create")) {
      TextureRegistry.SurfaceProducer producer = textures.createSurfaceProducer();
      long id = producer.id();
      producer.setCallback(
          new TextureRegistry.SurfaceProducer.Callback() {
            @Override
            public void onSurfaceAvailable() {
              channel.invokeMethod("surfaceAvailable", textureArgs(id));
            }

            @Override
            public void onSurfaceCleanup() {
              channel.invokeMethod("surfaceCleanup", textureArgs(id));
            }
          });
      producers.put(id, producer);
      result.success(id);
      return;
    }
    boolean allocate = call.method.equals("allocate");
    if (!allocate && !call.method.equals("dispose")) {
      result.notImplemented();
      return;
    }
    Long id = longArg(call, "textureId");
    TextureRegistry.SurfaceProducer producer = id == null ? null : producers.get(id);
    if (producer == null) {
      result.error("slint_skia", call.method + ": unknown texture", null);
      return;
    }
    if (!allocate) {
      producers.remove(id);
      producer.release();
      result.success(null);
      return;
    }
    Long width = longArg(call, "width");
    Long height = longArg(call, "height");
    if (width == null || height == null || width <= 0 || height <= 0) {
      result.error("slint_skia", "allocate: bad size", null);
      return;
    }
    producer.setSize(width.intValue(), height.intValue());
    Surface surface = producer.getSurface();
    long window;
    try {
      window = SlintSkiaNative.nativeWindowFromSurface(surface);
    } catch (LinkageError e) {
      result.error("slint_skia", "loading slint_skia_ffi for JNI failed: " + e, null);
      return;
    }
    if (window == 0) {
      result.error("slint_skia", "ANativeWindow_fromSurface failed", null);
      return;
    }
    Map<String, Object> info = new HashMap<>();
    info.put("window", window);
    result.success(info);
  }

  private static Map<String, Object> textureArgs(long id) {
    Map<String, Object> args = new HashMap<>();
    args.put("textureId", id);
    return args;
  }

  /** Dart ints arrive as Integer or Long depending on their size. */
  private static Long longArg(MethodCall call, String key) {
    Object value = call.argument(key);
    return value instanceof Number ? ((Number) value).longValue() : null;
  }
}
