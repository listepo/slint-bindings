import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:slint/slint_core.dart';

import 'bindings.g.dart' as b;
import 'element_info.dart';

typedef _CallbackFn = ffi.Void Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Char>,
);

/// Thrown when the testing backend rejects an operation — a `.slint` source
/// that does not compile, an unknown property, a stale element.
class SlintTestException implements Exception {
  SlintTestException(this.message);

  final String message;

  @override
  String toString() => 'SlintTestException: $message';
}

/// An element in the component's accessibility tree.
///
/// An element belongs to the query that produced it. Running another query
/// replaces the snapshot, so acting on an element from an earlier one throws
/// rather than silently acting on whatever now sits at that position — after
/// an interaction, re-run the query.
class SlintElement extends SlintElementInfo {
  SlintElement._(this._app, this._generation, super.json) : super.fromJson();

  final SlintTestApp _app;

  /// The query this element came from; see [SlintTestApp._generation].
  final int _generation;

  int get _index => index;

  /// Invokes the element's accessible default action — pressing a button,
  /// toggling a checkbox. Callback handlers it fires run before this returns.
  void click() {
    _app._checkUsable(this, _generation);
    if (!_app.guardNative(
      () => b.slint_testing_app_click(_app._handle, _index),
    )) {
      throw SlintTestException(_app._lastError() ?? 'click failed on $this');
    }
  }

  /// Sets the element's accessible value — the text of an input, the position
  /// of a slider.
  void setValue(String value) {
    _app._checkUsable(this, _generation);
    final ptr = value.toNativeUtf8();
    try {
      if (!_app.guardNative(
        () => b.slint_testing_app_set_value(_app._handle, _index, ptr.cast()),
      )) {
        throw SlintTestException(
          _app._lastError() ?? 'setValue failed on $this',
        );
      }
    } finally {
      calloc.free(ptr);
    }
  }
}

/// A `.slint` component instantiated on Slint's testing backend.
///
/// The component is compiled and instantiated, but never shown or rendered:
/// assertions run against the accessibility tree, so they describe what a
/// user can perceive and do rather than which pixels changed.
///
/// It is a [SlintComponent], so the wrapper `slint_generator` generated for
/// the `.slint` wraps it like any other backend's instance: find and act on
/// elements through the test app, and read properties and handle callbacks
/// through the wrapper's typed members.
///
/// ```dart
/// final ui = SlintTestApp.compile(TodoApp.slintSource,
///     component: TodoApp.componentName, files: TodoApp.slintFiles);
/// final app = TodoApp(ui);
/// addTearDown(app.dispose);
///
/// final added = <String>[];
/// app.onAddTodo(added.add);
/// ui.findById('TodoView::edit').single.setValue('buy milk');
/// ui.findByLabel('Add').single.click();
///
/// expect(added, ['buy milk']);
/// ```
///
/// Nothing here renders, so a wrapper's `renderTarget` throws for it.
class SlintTestApp with SlintNativeDisposeGuard implements SlintComponent {
  SlintTestApp._(this._handle, {this._sourceTree});

  final b.SlintTestingApp _handle;
  final _callbacks = <String, ffi.NativeCallable<_CallbackFn>>{};
  final _isolateToken = slintIsolateToken();
  SlintSourceTree? _sourceTree;
  bool _disposed = false;

  /// Bumped every time a query replaces the native element snapshot, so
  /// elements can tell whether the indices they hold still mean anything.
  int _generation = 0;

  /// Compiles [source] and instantiates [component].
  ///
  /// [component] may be omitted when the source exports exactly one — the
  /// compiler returns components unordered, so with several exports there is
  /// no meaningful "first" to fall back on and this throws instead of picking
  /// one arbitrarily.
  ///
  /// [files] is what [source] reads besides itself — `import`ed `.slint`
  /// files and `@image-url` resources, base64 by path relative to it, as a
  /// generated wrapper's `slintFiles` holds them. They are written to a
  /// temporary tree so the compiler finds them. [path] names the source in
  /// error messages and, without [files], anchors its relative imports.
  factory SlintTestApp.compile(
    String source, {
    String? component,
    String path = 'test.slint',
    Map<String, String> files = const {},
  }) {
    final tree = files.isEmpty
        ? null
        : writeSlintTree(source, files, name: path.split('/').last);
    final compilePath = tree?.path ?? path;
    final sourcePtr = source.toNativeUtf8();
    final pathPtr = compilePath.toNativeUtf8();
    final componentPtr = component?.toNativeUtf8();
    try {
      final handle = b.slint_testing_app_new(
        sourcePtr.cast(),
        pathPtr.cast(),
        componentPtr?.cast() ?? ffi.nullptr,
      );
      if (handle == ffi.nullptr) {
        throw SlintTestException(
          _readLastError() ?? 'failed to instantiate the component',
        );
      }
      return SlintTestApp._(handle, sourceTree: tree);
    } finally {
      calloc.free(sourcePtr);
      calloc.free(pathPtr);
      if (componentPtr != null) calloc.free(componentPtr);
    }
  }

  /// Every element in the component's accessibility tree.
  List<SlintElement> findAll() => _query('all', null);

  /// Elements whose accessible label is exactly [label] — the user-visible
  /// text of a button, checkbox, or input.
  List<SlintElement> findByLabel(String label) => _query('label', label);

  /// Elements with the given id, qualified by component: `TodoView::edit`.
  List<SlintElement> findById(String id) => _query('id', id);

  /// Elements of the given type, e.g. `Button` or `CheckBox`.
  List<SlintElement> findByType(String typeName) => _query('type', typeName);

  /// Elements with the given accessible [role], e.g. `Button`, `Checkbox`,
  /// `TextInput`. Filtered client-side from [findAll].
  List<SlintElement> findByRole(String role) => [
    for (final e in findAll())
      if (e.role == role) e,
  ];

  List<SlintElement> _query(String kind, String? needle) {
    _checkAlive();
    final kindPtr = kind.toNativeUtf8();
    final needlePtr = needle?.toNativeUtf8();
    try {
      final result = guardNative(
        () => b.slint_testing_app_query(
          _handle,
          kindPtr.cast(),
          needlePtr?.cast() ?? ffi.nullptr,
        ),
      );
      final json =
          _takeString(result) ??
          (throw SlintTestException(_lastError() ?? 'query failed'));
      final generation = ++_generation;
      return [
        for (final e in jsonDecode(json) as List)
          SlintElement._(this, generation, e as Map<String, Object?>),
      ];
    } finally {
      calloc.free(kindPtr);
      if (needlePtr != null) calloc.free(needlePtr);
    }
  }

  /// Reads a property of the component, decoded from the JSON bridge the
  /// runtime backends share.
  @override
  Object? getProperty(String name) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    try {
      final result = guardNative(
        () => b.slint_testing_app_get_property(_handle, namePtr.cast()),
      );
      final json =
          _takeString(result) ??
          (throw SlintTestException(
            _lastError() ?? "failed to read property '$name'",
          ));
      return jsonDecode(json);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Writes a property of the component. [value] is encoded as JSON, so maps
  /// and lists map onto Slint structs and models.
  @override
  void setProperty(String name, Object? value) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    final jsonPtr = jsonEncode(value).toNativeUtf8();
    try {
      if (!guardNative(
        () => b.slint_testing_app_set_property(
          _handle,
          namePtr.cast(),
          jsonPtr.cast(),
        ),
      )) {
        throw SlintTestException(
          _lastError() ?? "failed to set property '$name'",
        );
      }
    } finally {
      calloc.free(namePtr);
      calloc.free(jsonPtr);
    }
  }

  /// Routes the callback [name] to [handler], replacing whatever handler the
  /// component had. The handler's result becomes the callback's; null reads
  /// as the declared type's default. A handler that throws is reported to the
  /// current zone — in a test, a failure — and Slint gets the default.
  @override
  void setCallbackHandler(String name, SlintCallbackHandler handler) {
    _checkAlive();
    // Only close the old trampoline once the crate holds the new one, so a
    // failed registration cannot leave it calling a closed pointer.
    final callable =
        ffi.NativeCallable<_CallbackFn>.isolateLocal((
            ffi.Pointer<ffi.Void> _,
            ffi.Pointer<ffi.Char> argsJson,
          ) {
            try {
              final args = jsonDecode(argsJson.cast<Utf8>().toDartString());
              final result = handler(args as List<Object?>);
              if (result != null) {
                final resultPtr = jsonEncode(result).toNativeUtf8();
                try {
                  b.slint_testing_callback_set_result(resultPtr.cast());
                } finally {
                  calloc.free(resultPtr);
                }
              }
            } catch (e, s) {
              // Cannot unwind through Rust.
              Zone.current.handleUncaughtError(e, s);
            }
          })
          // The trampoline must not keep a test isolate alive after its
          // component is gone.
          ..keepIsolateAlive = false;

    final namePtr = name.toNativeUtf8();
    try {
      if (!guardNative(
        () => b.slint_testing_app_set_callback(
          _handle,
          namePtr.cast(),
          callable.nativeFunction,
          ffi.nullptr,
        ),
      )) {
        callable.close();
        throw SlintTestException(
          _lastError() ?? "failed to set callback '$name'",
        );
      }
    } finally {
      calloc.free(namePtr);
    }
    final previous = _callbacks.remove(name);
    if (previous != null) {
      deferRelease(previous.close);
    }
    _callbacks[name] = callable;
  }

  /// Invokes a callback or public function on the component and returns its
  /// result.
  @override
  Object? invokeCallback(String name, List<Object?> arguments) {
    _checkAlive();
    final namePtr = name.toNativeUtf8();
    final argsPtr = jsonEncode(arguments).toNativeUtf8();
    try {
      final result = guardNative(
        () =>
            b.slint_testing_app_invoke(_handle, namePtr.cast(), argsPtr.cast()),
      );
      final json =
          _takeString(result) ??
          (throw SlintTestException(
            _lastError() ?? "failed to invoke '$name'",
          ));
      return jsonDecode(json);
    } finally {
      calloc.free(namePtr);
      calloc.free(argsPtr);
    }
  }

  /// Advances the backend's mock clock, driving animations and timers without
  /// waiting in real time.
  void elapse(Duration duration) {
    guardNative(() => b.slint_testing_elapse_ms(duration.inMilliseconds));
  }

  /// Releases the component. Safe to call twice, and from inside one of its
  /// own callback handlers: the native side is freed once the call that ran
  /// the handler returns.
  @override
  void dispose() {
    if (_disposed) return;
    checkSlintOwnerIsolate(_isolateToken, 'dispose');
    _disposed = true;
    disposeNative();
  }

  @override
  void releaseNative() {
    _sourceTree?.dispose();
    _sourceTree = null;
    b.slint_testing_app_free(_handle);
    for (final callable in _callbacks.values) {
      callable.close();
    }
    _callbacks.clear();
  }

  void _checkAlive() {
    if (_disposed) {
      throw SlintTestException('this SlintTestApp has been disposed');
    }
  }

  void _checkUsable(SlintElement element, int generation) {
    _checkAlive();
    if (generation != _generation) {
      throw SlintTestException(
        '$element came from an earlier query — re-run the query to act '
        'on it',
      );
    }
  }

  String? _lastError() => _readLastError();

  static String? _readLastError() => _takeString(b.slint_testing_last_error());

  /// Decodes an owned C string and frees it; null stays null.
  static String? _takeString(ffi.Pointer<ffi.Char> ptr) {
    if (ptr == ffi.nullptr) return null;
    final s = ptr.cast<Utf8>().toDartString();
    b.slint_testing_string_free(ptr);
    return s;
  }
}
