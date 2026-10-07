library;

import 'dart:isolate';

/// Token for the isolate that created a Slint native object.
///
/// [checkSlintOwnerIsolate] throws when [dispose] (or another owner-only
/// operation) runs on a different isolate — the FFI backends free native
/// resources only on the owning thread, and a dispose that skips the native
/// free would leak.
Object slintIsolateToken() => Isolate.current;

void checkSlintOwnerIsolate(Object token, String operation) {
  if (!identical(Isolate.current, token)) {
    throw StateError(
      '$operation must be called on the isolate that created this object',
    );
  }
}

/// For backend implementations: defers freeing a native component while a
/// call into it is still on the stack.
///
/// A Slint callback runs Dart code in the middle of a native call: a click
/// dispatched by a pointer event, a timer fired by `render`, or
/// `invokeCallback` itself. If that code disposes the component, freeing the
/// native instance right away pulls it out from under the native frame that
/// is still using it. Route every native call through [guardNative] and free
/// in [releaseNative]. [disposeNative] runs the release at once when no call
/// is active, or when the outermost one returns.
mixin SlintNativeDisposeGuard {
  var _depth = 0;
  var _releasePending = false;
  var _released = false;
  final _deferredReleases = <void Function()>[];

  /// Whether a native call into this component is on the stack.
  bool get inNativeCall => _depth > 0;

  /// Runs [call]; a release requested during it waits until it returns.
  T guardNative<T>(T Function() call) {
    _depth++;
    try {
      return call();
    } finally {
      if (--_depth == 0) {
        _runDeferredReleases();
        if (_releasePending) {
          _releasePending = false;
          _release();
        }
      }
    }
  }

  /// Runs [release] once the outermost [guardNative] call returns.
  ///
  /// Use when tearing down a resource — such as a [NativeCallable] — that
  /// must not be freed while a native call into it is still on the stack.
  void deferRelease(void Function() release) {
    if (_depth > 0) {
      _deferredReleases.add(release);
    } else {
      release();
    }
  }

  void _runDeferredReleases() {
    if (_deferredReleases.isEmpty) {
      return;
    }
    final pending = List<void Function()>.from(_deferredReleases);
    _deferredReleases.clear();
    for (final release in pending) {
      release();
    }
  }

  /// Releases the native resources now, or once the outermost [guardNative]
  /// call returns.
  void disposeNative() {
    if (_depth > 0) {
      _releasePending = true;
    } else {
      _release();
    }
  }

  void _release() {
    if (_released) return;
    _released = true;
    releaseNative();
  }

  /// Frees the native instance and everything tied to it. Runs at most once.
  void releaseNative();
}
