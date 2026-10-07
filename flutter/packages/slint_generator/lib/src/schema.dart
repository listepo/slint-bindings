/// Typed public interface of a `.slint` file, as reported by the
/// `slint-introspect` tool (see `rust/src/main.rs`).
class GlobalSchema {
  GlobalSchema(this.name, this.properties);

  factory GlobalSchema.fromJson(Map<String, Object?> json) => GlobalSchema(
    json['name'] as String,
    [
      for (final p in (json['properties'] as List).cast<Map<String, Object?>>())
        PropertySchema(
          p['name'] as String,
          TypeRef.fromJson(p['type'] as Map<String, Object?>),
        ),
    ],
  );

  final String name;
  final List<PropertySchema> properties;
}

class SlintSchema {
  SlintSchema(
    this.components, {
    this.globals = const [],
    this.files = const [],
  });

  factory SlintSchema.fromJson(Map<String, Object?> json) => SlintSchema(
    [
      for (final c in (json['components'] as List).cast<Map<String, Object?>>())
        ComponentSchema.fromJson(c),
    ],
    globals: [
      for (final g
          in (json['globals'] as List?)?.cast<Map<String, Object?>>() ??
              const [])
        GlobalSchema.fromJson(g),
    ],
    files: [...?(json['files'] as List?)?.cast<String>()],
  );

  final List<ComponentSchema> components;

  /// Exported `global` components and their public properties.
  final List<GlobalSchema> globals;

  /// Canonical absolute paths of what the file reads besides itself:
  /// `import`ed `.slint` files and `@image-url` resources.
  final List<String> files;
}

class ComponentSchema {
  ComponentSchema(this.name, this.properties, this.callbacks);

  factory ComponentSchema.fromJson(
    Map<String, Object?> json,
  ) => ComponentSchema(
    json['name'] as String,
    [
      for (final p in (json['properties'] as List).cast<Map<String, Object?>>())
        PropertySchema(
          p['name'] as String,
          TypeRef.fromJson(p['type'] as Map<String, Object?>),
        ),
    ],
    [
      for (final c in (json['callbacks'] as List).cast<Map<String, Object?>>())
        CallbackSchema.fromJson(c),
    ],
  );

  final String name;
  final List<PropertySchema> properties;
  final List<CallbackSchema> callbacks;
}

class PropertySchema {
  PropertySchema(this.name, this.type);

  final String name;
  final TypeRef type;
}

class CallbackSchema {
  CallbackSchema(this.name, this.args, this.returnType);

  factory CallbackSchema.fromJson(Map<String, Object?> json) => CallbackSchema(
    json['name'] as String,
    [
      for (final a in (json['args'] as List).cast<Map<String, Object?>>())
        PropertySchema(
          a['name'] as String,
          TypeRef.fromJson(a['type'] as Map<String, Object?>),
        ),
    ],
    json['return'] == null
        ? null
        : TypeRef.fromJson(json['return'] as Map<String, Object?>),
  );

  final String name;

  /// Argument types, with the declared names where the compiler knows them —
  /// [PropertySchema.name] is the empty string when it does not.
  final List<PropertySchema> args;
  final TypeRef? returnType;
}

/// One of: float, int, string, bool, duration, angle, percent, length,
/// color, brush, image, enum (with [enumName] and [variants]), array
/// (with [element]), struct (with [structName] and [fields]).
class TypeRef {
  TypeRef(
    this.kind, {
    this.element,
    this.structName,
    this.fields,
    this.enumName,
    this.variants,
  });

  factory TypeRef.fromJson(Map<String, Object?> json) {
    final kind = json['kind'] as String;
    return TypeRef(
      kind,
      element: json['element'] == null
          ? null
          : TypeRef.fromJson(json['element'] as Map<String, Object?>),
      structName: kind == 'struct' ? json['name'] as String? : null,
      fields: json['fields'] == null
          ? null
          : [
              for (final f
                  in (json['fields'] as List).cast<Map<String, Object?>>())
                PropertySchema(
                  f['name'] as String,
                  TypeRef.fromJson(f['type'] as Map<String, Object?>),
                ),
            ],
      enumName: kind == 'enum' ? json['name'] as String? : null,
      variants: kind == 'enum' && json['variants'] != null
          ? [...(json['variants'] as List).cast<String>()]
          : null,
    );
  }

  final String kind;
  final TypeRef? element;
  final String? structName;
  final List<PropertySchema>? fields;
  final String? enumName;
  final List<String>? variants;
}
