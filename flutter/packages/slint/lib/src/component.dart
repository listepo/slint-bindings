import 'render_target.dart';

/// A compiled, instantiable component.
///
/// Mirrors `slint_interpreter::ComponentDefinition`.
abstract interface class SlintComponentDefinition {
  String get name;

  SlintComponent instantiate();

  void dispose();
}

typedef SlintCallbackHandler = Object? Function(List<Object?> arguments);

/// A live component instance.
///
/// Mirrors `slint_interpreter::ComponentInstance`. Property and callback
/// values are plain Dart values (bool, num, String — richer types as the
/// backends grow).
abstract interface class SlintComponent {
  /// Instantiates the component a generated wrapper registered for [path].
  ///
  /// `TodoApp.register()` once at startup makes
  /// `SlintComponent.load('ui/todo.slint')` return a `TodoApp`, built through
  /// the wrapper's `defaultFactory`: the backend follows the build mode —
  /// interpreter in debug, AOT in release — and nothing reads the file.
  /// Synchronous: the instance is usable, and renderable, on return.
  ///
  /// [T] is the wrapper type to return; `final TodoApp app =
  /// SlintComponent.load(...)` infers it. When [path] registered several
  /// components, [component] names the one to build, or [T] picks it; with
  /// neither there is no meaningful "first" to fall back on. Registration is
  /// per component, not per file, so a component the app never registers is
  /// still tree-shaken out of a release build.
  ///
  /// [path] must be a single `.slint` file. Every `.slint` an app loads has a
  /// generated wrapper: loading one always yields the typed Dart side of it.
  static T load<T extends SlintComponent>(String path, {String? component}) {
    if (!path.endsWith('.slint')) {
      throw ArgumentError.value(path, 'path', 'not a .slint file');
    }
    final registered = _registry[path];
    if (registered == null || registered.isEmpty) {
      throw StateError(
        "SlintComponent.load('$path'): nothing is registered for that path. "
        "Call the generated wrapper's register() first — TodoApp.register() "
        'for a TodoApp.',
      );
    }
    final _Registration entry;
    if (component != null) {
      entry =
          registered[component] ??
          (throw ArgumentError.value(
            component,
            'component',
            "'$path' registers ${_names(registered)}",
          ));
    } else if (registered.length == 1) {
      entry = registered.values.single;
    } else {
      final ofType = registered.values.where((r) => r.type == T).toList();
      if (ofType.length != 1) {
        throw StateError(
          "'$path' registers ${_names(registered)} — name the one to load "
          'with `component:` or a type argument',
        );
      }
      entry = ofType.single;
    }
    final instance = entry.create();
    if (instance is! T) {
      instance.dispose();
      throw StateError(
        "'$path' registered a ${instance.runtimeType} for "
        "'${entry.name}', not a $T",
      );
    }
    return instance;
  }

  /// Makes [load] answer [path] with [create] for [component]. Generated
  /// wrappers expose this as `register()`; call that once at startup.
  static void register<T extends SlintComponent>(
    String path,
    String component,
    T Function() create,
  ) {
    (_registry[path] ??= {})[component] = (
      name: component,
      type: T,
      create: create,
    );
  }

  /// Forgets everything registered for [path].
  static void unregister(String path) => _registry.remove(path);

  static final _registry = <String, Map<String, _Registration>>{};

  static String _names(Map<String, _Registration> registered) =>
      (registered.keys.toList()..sort()).join(', ');

  Object? getProperty(String name);

  void setProperty(String name, Object? value);

  void setCallbackHandler(String name, SlintCallbackHandler handler);

  Object? invokeCallback(String name, List<Object?> arguments);

  void dispose();
}

typedef _Registration = ({
  String name,
  Type type,
  SlintComponent Function() create,
});

/// A live instance that renders through a software target — satisfied by both
/// the interpreter instances (`slint_interpreter`) and the AOT-compiled ones
/// (`slint_compiler`).
abstract interface class SlintSoftwareComponent implements SlintComponent {
  SlintSoftwareRenderTarget get renderTarget;
}

/// A live instance whose accessibility tree can be inspected.
///
/// This is what lets a test find an element inside a Slint UI — which Flutter
/// sees as a single opaque widget — and work out where on screen to click it.
/// `slint_patrol` builds Patrol finders on top of it.
///
/// Descriptors are decoded JSON maps, like the property bridge: `id`,
/// `typeName`, `role`, `label`, `value`, `placeholder`, `description`,
/// `checked`, `checkable`, `enabled`, `itemIndex`, `itemCount`, and the
/// element's `x`, `y`, `width`, `height` in Slint logical pixels relative to
/// the window.
abstract interface class SlintInspectableComponent implements SlintComponent {
  /// Finds elements in the accessibility tree. [kind] is `all`, `label`,
  /// `id`, or `type`; [needle] is the text to match, unused for `all`.
  List<Map<String, Object?>> queryElements(String kind, [String? needle]);
}
