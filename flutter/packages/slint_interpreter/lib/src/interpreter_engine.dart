import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:slint/slint_core.dart';

import 'bindings.g.dart';

typedef _InterpreterSlintCallbackFn = Void Function(
  Pointer<Void>,
  Pointer<Char>,
);

class _InterpreterDefList {
  _InterpreterDefList(this.handle);

  final SlintInterpreterDefinitionList handle;
  int _refs = 0;
  bool _freed = false;

  void retain() => _refs++;

  void release() {
    _refs--;
    if (_refs <= 0 && !_freed) {
      _freed = true;
      slint_interpreter_definitions_free(handle);
    }
  }
}

class InterpreterSlintEngine implements SlintEngine {
  late final _handle = slint_interpreter_engine_new();
  final _isolateToken = slintIsolateToken();
  bool _disposed = false;

  @override
  List<InterpreterSlintComponentDefinition> compile(
    String source, {
    String? path,
  }) {
    if (_disposed) throw StateError('Engine is disposed');
    final sourceCStr = source.toNativeUtf8();
    final pathCStr = path?.toNativeUtf8() ?? nullptr;

    try {
      final defList = slint_interpreter_engine_compile(
        _handle,
        sourceCStr.cast(),
        pathCStr.cast(),
      );

      if (defList.address == 0) {
        throw StateError(_getLastError());
      }

      // A non-null list always holds at least one definition: the crate
      // reports "no component" as an error. Names are read up front, so a
      // definition answers `name` even after the list is gone.
      final count = slint_interpreter_definitions_count(defList);
      final List<String> names;
      try {
        names = [for (var i = 0; i < count; i++) _definitionName(defList, i)];
      } catch (_) {
        slint_interpreter_definitions_free(defList);
        rethrow;
      }
      final owner = _InterpreterDefList(defList);
      return [
        for (var i = 0; i < count; i++)
          InterpreterSlintComponentDefinition._(owner, i, names[i]),
      ];
    } finally {
      malloc.free(sourceCStr);
      if (pathCStr.address != 0) {
        malloc.free(pathCStr);
      }
    }
  }

  /// Frees the engine. Idempotent; definitions and components it produced
  /// keep working.
  @override
  void dispose() {
    if (_disposed) return;
    checkSlintOwnerIsolate(_isolateToken, 'dispose');
    _disposed = true;
    slint_interpreter_engine_free(_handle);
  }
}

String _definitionName(SlintInterpreterDefinitionList list, int index) {
  final nameCStr = slint_interpreter_definitions_name(list, index);
  if (nameCStr.address == 0) {
    throw StateError(_getLastError());
  }
  final name = nameCStr.cast<Utf8>().toDartString();
  slint_interpreter_string_free(nameCStr.cast());
  return name;
}

class InterpreterSlintComponentDefinition implements SlintComponentDefinition {
  final _InterpreterDefList _list;
  final int _index;
  final _isolateToken = slintIsolateToken();
  bool _disposed = false;

  InterpreterSlintComponentDefinition._(this._list, this._index, this.name) {
    _list.retain();
  }

  @override
  final String name;

  @override
  InterpreterSlintComponent instantiate() {
    if (_disposed) {
      throw StateError('Component definition is disposed');
    }
    final instHandle = slint_interpreter_instantiate(_list.handle, _index);
    if (instHandle.address == 0) {
      throw StateError(_getLastError());
    }
    return InterpreterSlintComponent(instHandle);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    checkSlintOwnerIsolate(_isolateToken, 'dispose');
    _disposed = true;
    _list.release();
  }
}

class InterpreterSlintComponent
    with SlintNativeDisposeGuard
    implements SlintSoftwareComponent, SlintInspectableComponent {
  final SlintInterpreterInstance _instanceHandle;
  late final InterpreterSoftwareRenderTarget _renderTarget;
  final Map<String, NativeCallable<_InterpreterSlintCallbackFn>> _callbacks =
      {};
  final _isolateToken = slintIsolateToken();
  bool _disposed = false;

  InterpreterSlintComponent(this._instanceHandle) {
    // Owns no pixel buffer until resized, so creating it up front is free.
    _renderTarget = InterpreterSoftwareRenderTarget(this);
  }

  /// Software render target sharing the same instance handle.
  @override
  InterpreterSoftwareRenderTarget get renderTarget => _renderTarget;

  @override
  Object? getProperty(String name) {
    if (_disposed) throw StateError('Component is disposed');
    final nameCStr = name.toNativeUtf8();
    try {
      final jsonCStr = guardNative(
        () => slint_interpreter_instance_get_property(
          _instanceHandle,
          nameCStr.cast(),
        ),
      );
      if (jsonCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final json = jsonCStr.cast<Utf8>().toDartString();
      slint_interpreter_string_free(jsonCStr.cast());
      return jsonDecode(json);
    } finally {
      malloc.free(nameCStr);
    }
  }

  @override
  List<Map<String, Object?>> queryElements(String kind, [String? needle]) {
    if (_disposed) throw StateError('Component is disposed');
    final kindCStr = kind.toNativeUtf8();
    final needleCStr = needle?.toNativeUtf8();
    try {
      final jsonCStr = guardNative(
        () => slint_interpreter_instance_query_elements(
          _instanceHandle,
          kindCStr.cast(),
          needleCStr?.cast() ?? nullptr,
        ),
      );
      if (jsonCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final json = jsonCStr.cast<Utf8>().toDartString();
      slint_interpreter_string_free(jsonCStr.cast());
      return (jsonDecode(json) as List).cast<Map<String, Object?>>();
    } finally {
      malloc.free(kindCStr);
      if (needleCStr != null) malloc.free(needleCStr);
    }
  }

  @override
  void setProperty(String name, Object? value) {
    if (_disposed) throw StateError('Component is disposed');
    final nameCStr = name.toNativeUtf8();
    final jsonCStr = jsonEncode(value).toNativeUtf8();

    try {
      final success = guardNative(
        () => slint_interpreter_instance_set_property(
          _instanceHandle,
          nameCStr.cast(),
          jsonCStr.cast(),
        ),
      );
      if (!success) {
        throw StateError(_getLastError());
      }
    } finally {
      malloc.free(nameCStr);
      malloc.free(jsonCStr);
    }
  }

  @override
  void setCallbackHandler(String name, SlintCallbackHandler handler) {
    if (_disposed) throw StateError('Component is disposed');
    // Create the trampoline first; only close the old one after rust has
    // the new pointer, so a failed set_callback cannot leave a dangling fn.
    final callable =
        NativeCallable<_InterpreterSlintCallbackFn>.isolateLocal((
            Pointer<Void> userData,
            Pointer<Char> argsJsonPtr,
          ) {
            final argsJson = argsJsonPtr.cast<Utf8>().toDartString();
            try {
              final result = handler(jsonDecode(argsJson) as List<dynamic>);
              // The crate copies the result while this call is still running;
              // no result reads as the declared type's default on the Slint side.
              if (result != null) {
                final resultCStr = jsonEncode(result).toNativeUtf8();
                try {
                  slint_interpreter_callback_set_result(resultCStr.cast());
                } finally {
                  malloc.free(resultCStr);
                }
              }
            } catch (e, s) {
              // Cannot unwind through Rust; report through the zone so a bug in
              // the handler shows up (FlutterError / a failing test) instead of
              // vanishing.
              Zone.current.handleUncaughtError(e, s);
            }
          })
          // The trampoline must not keep a test isolate alive after its
          // component is gone.
          ..keepIsolateAlive = false;

    final nameCStr = name.toNativeUtf8();
    try {
      final success = guardNative(
        () => slint_interpreter_instance_set_callback(
          _instanceHandle,
          nameCStr.cast(),
          callable.nativeFunction,
          nullptr,
        ),
      );
      if (!success) {
        callable.close();
        throw StateError(_getLastError());
      }
    } finally {
      malloc.free(nameCStr);
    }

    final previous = _callbacks.remove(name);
    if (previous != null) {
      deferRelease(previous.close);
    }
    _callbacks[name] = callable;
  }

  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    if (_disposed) throw StateError('Component is disposed');
    final nameCStr = name.toNativeUtf8();
    final argsJson = jsonEncode(arguments);
    final argsCStr = argsJson.toNativeUtf8();

    try {
      final resultCStr = guardNative(
        () => slint_interpreter_instance_invoke(
          _instanceHandle,
          nameCStr.cast(),
          argsCStr.cast(),
        ),
      );
      if (resultCStr.address == 0) {
        throw StateError(_getLastError());
      }
      final resultJson = resultCStr.cast<Utf8>().toDartString();
      slint_interpreter_string_free(resultCStr.cast());
      return jsonDecode(resultJson);
    } finally {
      malloc.free(nameCStr);
      malloc.free(argsCStr);
    }
  }

  /// Frees the instance. Safe from inside one of its own callbacks: the
  /// native side is released once the call that ran the callback returns.
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    checkSlintOwnerIsolate(_isolateToken, 'dispose');
    _disposed = true;
    disposeNative();
  }

  @override
  void releaseNative() {
    slint_interpreter_instance_free(_instanceHandle);
    for (final callable in _callbacks.values) {
      callable.close();
    }
    _callbacks.clear();
    _renderTarget.dispose();
  }
}

class InterpreterSoftwareRenderTarget implements SlintSoftwareRenderTarget {
  final InterpreterSlintComponent _component;
  Pointer<Uint8> _pixelBuffer = nullptr;
  Uint8List _pixels = Uint8List(0);
  // 0×0 until resize(): the same size the Slint window starts at, so width,
  // height and pixels never describe a buffer the renderer would reject.
  int _width = 0;
  int _height = 0;
  bool _disposed = false;

  InterpreterSoftwareRenderTarget(this._component);

  void _freeBuffer() {
    if (_pixelBuffer.address != 0) {
      malloc.free(_pixelBuffer);
      _pixelBuffer = nullptr;
      _pixels = Uint8List(0);
    }
  }

  @override
  SlintComponent get component => _component;

  @override
  int get width => _width;

  @override
  int get height => _height;

  @override
  void resize(int width, int height) {
    if (_disposed ||
        _component._disposed ||
        (width == _width && height == _height)) {
      return;
    }
    // A render may be writing into the buffer this would free.
    if (_component.inNativeCall) {
      throw StateError('resize() called from inside a Slint callback');
    }
    _freeBuffer();
    _width = width;
    _height = height;
    if (width > 0 && height > 0) {
      final bufferSize = width * height * 4;
      _pixelBuffer = malloc<Uint8>(bufferSize);
      _pixels = _pixelBuffer.asTypedList(bufferSize);
    }
    _component.guardNative(
      () => slint_interpreter_instance_set_size(
        _component._instanceHandle,
        width,
        height,
      ),
    );
  }

  @override
  bool render() {
    if (_disposed || _component._disposed || _pixelBuffer.address == 0) {
      return false;
    }
    return _component.guardNative(
      () => slint_interpreter_instance_render(
        _component._instanceHandle,
        _pixelBuffer.cast(),
        _pixels.length,
      ),
    );
  }

  @override
  void dispatchPointerEvent(SlintPointerEvent event) {
    if (_disposed || _component._disposed) return;
    _component.guardNative(
      () => slint_interpreter_instance_pointer_event(
        _component._instanceHandle,
        event.kind.index,
        event.x,
        event.y,
        event.button.index,
        event.scrollDeltaX,
        event.scrollDeltaY,
      ),
    );
  }

  @override
  void dispatchKeyEvent(SlintKeyEvent event) {
    if (_disposed || _component._disposed) return;
    final textCStr = event.text.toNativeUtf8();
    try {
      _component.guardNative(
        () => slint_interpreter_instance_key_event(
          _component._instanceHandle,
          textCStr.cast(),
          event.pressed,
        ),
      );
    } finally {
      malloc.free(textCStr);
    }
  }

  @override
  Uint8List get pixels => _pixels;

  /// Frees the pixel buffer — at once, or with the component when a render
  /// that may still be writing into it is on the stack.
  @override
  void dispose() {
    if (_disposed && _pixelBuffer.address == 0) {
      return;
    }
    _disposed = true;
    if (!_component.inNativeCall) _freeBuffer();
  }
}

String _getLastError() {
  final errCStr = slint_interpreter_last_error();
  if (errCStr.address == 0) {
    return 'unknown error';
  }
  final err = errCStr.cast<Utf8>().toDartString();
  slint_interpreter_string_free(errCStr.cast());
  return err;
}
