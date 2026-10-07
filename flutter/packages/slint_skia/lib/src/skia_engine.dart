import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
// dart:ui's Size (re-exported here) would shadow dart:ffi's.
import 'package:flutter/services.dart' hide Size;
import 'package:slint/slint.dart';

import 'bindings.g.dart';
import 'skia_native.dart';

/// The error of this thread's last failed slint-skia-ffi call, or null.
String? _takeError() {
  final ptr = slint_skia_last_error();
  if (ptr == nullptr) {
    return null;
  }
  final msg = ptr.cast<Utf8>().toDartString();
  _freeString(ptr);
  return msg;
}

String _getLastError() => _takeError() ?? 'Unknown error';

void _freeString(Pointer<Char> ptr) {
  if (ptr != nullptr) {
    slint_skia_string_free(ptr.cast());
  }
}

/// Implementation of SlintEngine using Skia renderer
class SkiaSlintEngine implements SlintEngine {
  late Pointer<Void> _enginePtr;

  SkiaSlintEngine() {
    _enginePtr = slint_skia_engine_new();
    if (_enginePtr == nullptr) {
      throw StateError('Failed to create Skia engine: ${_getLastError()}');
    }
  }

  @override
  List<SlintComponentDefinition> compile(String source, {String? path}) {
    final sourceCString = source.toNativeUtf8();
    final pathCString = (path ?? '').toNativeUtf8();

    try {
      final defPtr = slint_skia_engine_compile(
        _enginePtr,
        sourceCString.cast<Char>(),
        pathCString.cast<Char>(),
      );

      if (defPtr == nullptr) {
        throw StateError('Failed to compile: ${_getLastError()}');
      }

      final namePtr = slint_skia_definitions_name(defPtr, 0);
      if (namePtr == nullptr) {
        slint_skia_definitions_free(defPtr);
        throw StateError('Failed to read component name: ${_getLastError()}');
      }
      final name = namePtr.cast<Utf8>().toDartString();
      _freeString(namePtr.cast());
      return [SkiaSlintComponentDefinition._create(defPtr, name)];
    } finally {
      calloc.free(sourceCString);
      calloc.free(pathCString);
    }
  }

  @override
  void dispose() {
    if (_enginePtr != nullptr) {
      slint_skia_engine_free(_enginePtr);
      _enginePtr = nullptr;
    }
  }
}

/// Implementation of SlintComponentDefinition for Skia
class SkiaSlintComponentDefinition implements SlintComponentDefinition {
  late Pointer<Void> _defPtr;
  final String _name;

  SkiaSlintComponentDefinition._create(this._defPtr, this._name);

  @override
  String get name => _name;

  /// Instantiate this component definition
  @override
  SlintComponent instantiate() {
    if (_defPtr == nullptr) {
      throw StateError('Component definition is disposed');
    }
    final instPtr = slint_skia_instantiate(_defPtr);
    if (instPtr == nullptr) {
      throw StateError('Failed to instantiate: ${_getLastError()}');
    }
    return SkiaSlintComponent._create(instPtr);
  }

  @override
  void dispose() {
    if (_defPtr != nullptr) {
      slint_skia_definitions_free(_defPtr);
      _defPtr = nullptr;
    }
  }
}

/// Implementation of SlintComponent for Skia
class SkiaSlintComponent implements SlintComponent {
  late Pointer<Void> _instPtr;

  SkiaSlintComponent._create(this._instPtr);

  /// Set the component size in logical pixels
  void setSize(double width, double height) {
    final success = slint_skia_instance_set_size(_instPtr, width, height);
    if (!success) {
      throw StateError('Failed to set size: ${_getLastError()}');
    }
  }

  /// Get a property value as JSON
  @override
  Object? getProperty(String name) {
    final nameCString = name.toNativeUtf8();
    try {
      final jsonPtr = slint_skia_instance_get_property(
        _instPtr,
        nameCString.cast<Char>(),
      );
      if (jsonPtr == nullptr) {
        throw StateError('Failed to get property "$name": ${_getLastError()}');
      }
      final jsonStr = jsonPtr.cast<Utf8>().toDartString();
      _freeString(jsonPtr.cast());
      return jsonDecode(jsonStr);
    } finally {
      calloc.free(nameCString);
    }
  }

  /// Set a property value from JSON
  @override
  void setProperty(String name, Object? value) {
    final nameCString = name.toNativeUtf8();
    final valueJson = jsonEncode(value);
    final jsonCString = valueJson.toNativeUtf8();

    try {
      final success = slint_skia_instance_set_property(
        _instPtr,
        nameCString.cast<Char>(),
        jsonCString.cast<Char>(),
      );
      if (!success) {
        throw StateError('Failed to set property "$name": ${_getLastError()}');
      }
    } finally {
      calloc.free(nameCString);
      calloc.free(jsonCString);
    }
  }

  /// Invoke a callback with arguments
  dynamic invoke(String name, List<dynamic> args) {
    final nameCString = name.toNativeUtf8();
    final argsJson = jsonEncode(args);
    final argsCString = argsJson.toNativeUtf8();

    try {
      final resultPtr = slint_skia_instance_invoke(
        _instPtr,
        nameCString.cast<Char>(),
        argsCString.cast<Char>(),
      );
      if (resultPtr == nullptr) {
        throw StateError('Failed to invoke "$name": ${_getLastError()}');
      }
      final resultJson = resultPtr.cast<Utf8>().toDartString();
      _freeString(resultPtr.cast());
      return jsonDecode(resultJson);
    } finally {
      calloc.free(nameCString);
      calloc.free(argsCString);
    }
  }

  /// Set up callback handler (not yet implemented)
  @override
  void setCallbackHandler(String name, SlintCallbackHandler handler) {
    throw UnimplementedError(
      'setCallbackHandler not implemented for Skia renderer. '
      'See README for architecture plans.',
    );
  }

  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    throw UnimplementedError(
      'invokeCallback not implemented for Skia renderer. '
      'See README for architecture plans.',
    );
  }

  @override
  void dispose() {
    if (_instPtr != nullptr) {
      slint_skia_instance_free(_instPtr);
      _instPtr = nullptr;
    }
  }
}

/// The slint_skia platform plugin: it owns the textures Flutter shows.
const _channel = MethodChannel('slint_skia');

/// Renders a [SkiaSlintComponent] into a Flutter external texture.
///
/// Show it with `Texture(textureId: target.textureId)` and call [render]
/// once per frame (from a `Ticker`). Sizes are physical pixels and Slint's
/// scale factor stays 1, so pointer coordinates are physical too (multiply
/// Flutter's logical offsets by the device pixel ratio).
///
/// The platform plugin owns the texture and slint-skia-ffi renders into it:
/// Metal into an IOSurface `CVPixelBuffer` on iOS and macOS, EGL into a
/// `SurfaceProducer` on Android, D3D12 into a shared texture on Windows, and
/// a headless EGL context read back into an `FlPixelBufferTexture` on Linux.
/// [dispose] releases the texture and disposes the component.
class SkiaTextureRenderTarget implements SlintTextureRenderTarget {
  SkiaTextureRenderTarget._(this._component, this.textureId);

  /// Registers a texture of [width] x [height] physical pixels with the
  /// platform plugin and attaches [component]'s GPU surface to it.
  static Future<SkiaTextureRenderTarget> create(
    SkiaSlintComponent component,
    int width,
    int height,
  ) async {
    _checkSize(width, height);
    _listen();
    final id = await _channel.invokeMethod<int>('create');
    if (id == null) {
      throw StateError('the slint_skia plugin returned no texture id');
    }
    final target = SkiaTextureRenderTarget._(component, id)
      .._wantedWidth = width
      .._wantedHeight = height;
    _live[id] = target;
    try {
      await target._attach(width, height);
    } catch (_) {
      _live.remove(id);
      await _channel.invokeMethod<void>('dispose', {'textureId': id});
      rethrow;
    }
    return target;
  }

  /// Targets by texture id, for the plugin's calls back into Dart.
  static final Map<int, SkiaTextureRenderTarget> _live = {};
  static bool _listening = false;

  final SkiaSlintComponent _component;

  @override
  final int textureId;

  int _width = 0;
  int _height = 0;
  int _wantedWidth = 0;
  int _wantedHeight = 0;

  /// Reallocating the texture for a new size: no frames until it lands.
  Future<void>? _attaching;

  /// Linux: the plugin is copying the frame out of the Rust-owned buffer,
  /// which the next render would overwrite.
  Future<void>? _delivering;

  /// Android: the platform took the surface away (app in the background).
  bool _suspended = false;

  /// Why an asynchronous step failed; the next [render] throws it.
  Object? _failure;

  bool _disposed = false;

  Pointer<Void> get _instance => _component._instPtr;

  @override
  SlintComponent get component => _component;

  @override
  int get width => _width;

  @override
  int get height => _height;

  /// Reallocates the texture at the new size, asynchronously: [render]
  /// returns false until the new texture is attached, and throws if that
  /// failed.
  @override
  void resize(int width, int height) {
    _checkSize(width, height);
    _wantedWidth = width;
    _wantedHeight = height;
    if (_disposed || _attaching != null) return;
    if (width == _width && height == _height) return;
    _attaching = _reattach();
  }

  Future<void> _reattach() async {
    try {
      // Sizes asked for while one attach was in flight land in the next.
      while (!_disposed &&
          (_wantedWidth != _width || _wantedHeight != _height)) {
        await _attach(_wantedWidth, _wantedHeight);
      }
    } catch (e) {
      _failure ??= e;
    } finally {
      _attaching = null;
    }
  }

  Future<void> _attach(int width, int height) async {
    if (Platform.isIOS || Platform.isMacOS) {
      final info = await _allocate(width, height);
      if (_disposed) return;
      _check(
        slint_skia_instance_attach_metal(
          _instance,
          _pointer(info, 'device'),
          _pointer(info, 'queue'),
          _pointer(info, 'texture'),
          width,
          height,
        ),
      );
    } else if (Platform.isAndroid) {
      final info = await _allocate(width, height);
      if (_disposed) return;
      _check(
        slint_skia_instance_attach_android(
          _instance,
          _pointer(info, 'window'),
          width,
          height,
        ),
      );
    } else if (Platform.isWindows) {
      final info = await _allocate(width, height);
      if (_disposed) return;
      final handle = slint_skia_instance_attach_d3d(
        _instance,
        info['luidLow']! as int,
        info['luidHigh']! as int,
        width,
        height,
      );
      _check(handle != nullptr);
      // The plugin duplicates the handle; ours stays valid until the next
      // attach or detach, which cannot run before this call returns.
      await _channel.invokeMethod<void>('setHandle', {
        'textureId': textureId,
        'handle': handle.address,
        'width': width,
        'height': height,
      });
    } else if (Platform.isLinux) {
      _check(slint_skia_instance_attach_gl(_instance, width, height));
    } else {
      throw UnsupportedError(
        'slint_skia has no GPU surface on ${Platform.operatingSystem}',
      );
    }
    _width = width;
    _height = height;
  }

  Future<Map<Object?, Object?>> _allocate(int width, int height) async {
    final info = await _channel.invokeMethod<Map<Object?, Object?>>(
      'allocate',
      {'textureId': textureId, 'width': width, 'height': height},
    );
    if (info == null) {
      throw StateError('the slint_skia plugin allocated no texture');
    }
    return info;
  }

  static Pointer<Void> _pointer(Map<Object?, Object?> info, String key) =>
      Pointer<Void>.fromAddress(info[key]! as int);

  /// Must run right after the FFI call, before anything else reads the
  /// thread's error slot.
  static void _check(bool ok) {
    if (!ok) {
      throw StateError('attaching the GPU surface failed: ${_getLastError()}');
    }
  }

  static void _checkSize(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError(
        'texture size must be positive, got ${width}x$height',
      );
    }
  }

  /// Renders a frame into the texture if the scene changed, and tells
  /// Flutter. False: nothing changed, or there is no texture to draw into
  /// right now (a resize, or an Android surface change, in flight). Throws
  /// when rendering failed, or an earlier asynchronous step did.
  @override
  bool render() {
    final failure = _failure;
    if (failure != null) {
      _failure = null;
      throw failure;
    }
    if (_disposed || _suspended || _attaching != null || _delivering != null) {
      return false;
    }
    if (!slint_skia_instance_render(_instance)) {
      final error = _takeError();
      if (error == null) return false;
      throw StateError('render failed: $error');
    }
    _deliver();
    return true;
  }

  void _deliver() {
    // Android: Flutter consumes the SurfaceProducer's queued buffers itself.
    if (Platform.isAndroid) return;
    final args = <String, Object?>{'textureId': textureId};
    if (Platform.isLinux) {
      final length = calloc<Size>();
      try {
        final pixels = slint_skia_instance_pixels(_instance, length);
        if (pixels == nullptr) {
          throw StateError('no frame to hand over: ${_getLastError()}');
        }
        args.addAll({
          'pixels': pixels.address,
          'length': length.value,
          'width': _width,
          'height': _height,
        });
      } finally {
        calloc.free(length);
      }
    }
    final sent = _channel.invokeMethod<void>('frame', args).catchError((
      Object e,
    ) {
      _failure ??= e;
    });
    if (Platform.isLinux) {
      _delivering = sent.whenComplete(() => _delivering = null);
    }
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments as Map<Object?, Object?>;
      final target = _live[args['textureId']! as int];
      switch (call.method) {
        case 'surfaceCleanup':
          target?._suspend();
        case 'surfaceAvailable':
          target?._resume();
      }
    });
  }

  /// Android: the SurfaceProducer's surface is going away (the app went to
  /// the background): drop what renders into it.
  void _suspend() {
    _suspended = true;
    slint_skia_instance_detach(_instance);
  }

  /// Android: the producer can hand out a new surface: attach to it the way
  /// a resize does.
  void _resume() {
    if (_disposed || !_suspended) return;
    _suspended = false;
    _width = 0;
    _height = 0;
    _attaching ??= _reattach();
  }

  @override
  void dispatchPointerEvent(SlintPointerEvent event) {
    if (_disposed) return;
    final ok = slint_skia_instance_pointer_event(
      _instance,
      event.kind.index,
      event.x,
      event.y,
      event.button.index,
      event.scrollDeltaX,
      event.scrollDeltaY,
    );
    if (!ok) {
      throw StateError('pointer event failed: ${_getLastError()}');
    }
  }

  @override
  void dispatchKeyEvent(SlintKeyEvent event) {
    if (_disposed) return;
    final text = event.text.toNativeUtf8();
    try {
      if (!slint_skia_instance_key_event(
        _instance,
        text.cast<Char>(),
        event.pressed,
      )) {
        throw StateError('key event failed: ${_getLastError()}');
      }
    } finally {
      calloc.free(text);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _live.remove(textureId);
    // The plugin may still be reading what the Rust side owns (the Linux
    // frame, the Windows handle): tear down once it is done.
    final pending = [?_attaching, ?_delivering];
    if (pending.isEmpty) {
      _release();
    } else {
      unawaited(Future.wait(pending).whenComplete(_release));
    }
  }

  void _release() {
    // The surface first, then the texture it rendered into.
    slint_skia_instance_detach(_instance);
    unawaited(_channel.invokeMethod<void>('dispose', {'textureId': textureId}));
    _component.dispose();
  }
}
