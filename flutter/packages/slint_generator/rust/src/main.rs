//! Dumps the public interface of a `.slint` file as JSON on stdout.
//!
//! Used by `slint_compiler` (Dart) as the single schema source for both the
//! generated `.g.dart` wrappers and the generated AOT Rust glue crate. Unlike
//! `slint-interpreter` introspection, this exposes full types: struct fields,
//! array element types, and callback signatures.

use std::process::exit;
use std::rc::Rc;

use i_slint_compiler::diagnostics::BuildDiagnostics;
use i_slint_compiler::langtype::Type;
use i_slint_compiler::object_tree::{Component, PropertyVisibility};
use serde_json::{json, Value};

fn main() {
    let path = match std::env::args().nth(1) {
        Some(p) => p,
        None => {
            eprintln!("usage: slint-introspect <file.slint>");
            exit(64);
        }
    };

    let mut diag = BuildDiagnostics::default();
    let syntax_node = i_slint_compiler::parser::parse_file(&path, &mut diag);
    if diag.has_errors() {
        for d in diag.to_string_vec() {
            eprintln!("{d}");
        }
        exit(1);
    }
    let mut config = i_slint_compiler::CompilerConfiguration::new(
        i_slint_compiler::generator::OutputFormat::Rust,
    );
    // As slint-build does: only an embedding pass records `@image-url`s as
    // file resources, which is where `all_files_to_watch` finds them.
    config.embed_resources = i_slint_compiler::EmbedResourcesKind::EmbedAllResources;
    let (doc, diag, loader) = spin_on::spin_on(i_slint_compiler::compile_syntax_node(
        syntax_node.expect("no parse errors"),
        diag,
        config,
    ));
    if diag.has_errors() {
        for d in diag.to_string_vec() {
            eprintln!("{d}");
        }
        exit(1);
    }

    let mut components = Vec::new();
    let mut globals = Vec::new();
    for (name, export) in doc.exports.iter() {
        let Some(c) = export.as_ref().left() else {
            continue;
        };
        if c.is_global() {
            match component_json(&name.name, c) {
                Ok(v) => globals.push(v),
                Err(e) => {
                    eprintln!("{}: {e}", name.name);
                    exit(1);
                }
            }
            continue;
        }
        match component_json(&name.name, c) {
            Ok(v) => components.push(v),
            Err(e) => {
                eprintln!("{}: {e}", name.name);
                exit(1);
            }
        }
    }
    // Everything the file reads from disk besides itself — `import`ed `.slint`
    // files and `@image-url` resources — so a runtime compiler can be handed
    // the same tree. Builtins and unresolved imports are not files.
    // The loader knows the imported documents; the root document, which it
    // does not hold, carries the resources the embedding pass collected.
    let resources: Vec<std::path::PathBuf> = doc
        .embedded_file_resources
        .borrow()
        .iter()
        .filter_map(|r| r.path.as_ref().map(|p| std::path::PathBuf::from(&**p)))
        .collect();
    let main = std::fs::canonicalize(&path).ok();
    let mut files: Vec<String> = loader
        .all_files_to_watch()
        .into_iter()
        .chain(resources)
        .filter_map(|p| std::fs::canonicalize(p).ok())
        .filter(|p| p.is_file() && Some(p) != main.as_ref())
        .map(|p| p.to_string_lossy().into_owned())
        .collect();
    files.sort();
    files.dedup();
    println!(
        "{}",
        json!({ "components": components, "globals": globals, "files": files })
    );
}

fn component_json(export_name: &str, c: &Rc<Component>) -> Result<Value, String> {
    let root = c.root_element.borrow();
    let mut properties = Vec::new();
    let mut callbacks = Vec::new();
    for (name, decl) in root.property_declarations.iter() {
        // Compiler passes hoist internal widget properties into the root;
        // only user-declared API carries expose_in_public_api.
        if !decl.expose_in_public_api {
            continue;
        }
        match &decl.property_type {
            Type::Callback(f) => {
                // arg_names is best-effort in the compiler (an unset name is
                // the empty string); codegen falls back to positional names.
                let args = f
                    .args
                    .iter()
                    .enumerate()
                    .map(|(i, t)| {
                        let arg_name = f.arg_names.get(i).map_or("", |s| s.as_str());
                        Ok(json!({ "name": arg_name, "type": type_json(t)? }))
                    })
                    .collect::<Result<Vec<_>, String>>()
                    .map_err(|e| format!("callback '{name}': {e}"))?;
                let ret = match &f.return_type {
                    Type::Void => Value::Null,
                    t => type_json(t).map_err(|e| format!("callback '{name}': {e}"))?,
                };
                callbacks.push(json!({ "name": name.to_string(), "args": args, "return": ret }));
            }
            // ponytail: public functions not bridged; add when needed
            Type::Function(_) => {}
            ty => {
                if matches!(
                    decl.visibility,
                    PropertyVisibility::Input
                        | PropertyVisibility::Output
                        | PropertyVisibility::InOut
                ) {
                    let t = type_json(ty).map_err(|e| format!("property '{name}': {e}"))?;
                    properties.push(json!({ "name": name.to_string(), "type": t }));
                }
            }
        }
    }
    Ok(json!({ "name": export_name, "properties": properties, "callbacks": callbacks }))
}

fn type_json(t: &Type) -> Result<Value, String> {
    Ok(match t {
        Type::Float32 => json!({"kind": "float"}),
        Type::Int32 => json!({"kind": "int"}),
        Type::String => json!({"kind": "string"}),
        Type::Bool => json!({"kind": "bool"}),
        Type::Duration => json!({"kind": "duration"}),
        Type::Angle => json!({"kind": "angle"}),
        Type::Percent => json!({"kind": "percent"}),
        Type::PhysicalLength | Type::LogicalLength | Type::Rem => json!({"kind": "length"}),
        Type::Array(inner) => json!({"kind": "array", "element": type_json(inner)?}),
        Type::Struct(s) => {
            let name = s.name.slint_name().ok_or_else(|| {
                "anonymous structs are not supported; declare a named struct".to_string()
            })?;
            let fields = s
                .fields
                .iter()
                .map(|(k, v)| Ok(json!({"name": k.to_string(), "type": type_json(v)?})))
                .collect::<Result<Vec<_>, String>>()?;
            json!({"kind": "struct", "name": name.to_string(), "fields": fields})
        }
        Type::Color => json!({"kind": "color"}),
        Type::Brush => json!({"kind": "brush"}),
        Type::Image => json!({"kind": "image"}),
        Type::Enumeration(e) => json!({
            "kind": "enum",
            "name": e.name.to_string(),
            "variants": e.values.iter().map(|v| v.to_string()).collect::<Vec<_>>(),
        }),
        other => {
            return Err(format!(
            "unsupported type `{other}` (supported: numbers, string, bool, color, brush, image, enum, named structs, arrays)"
        ))
        }
    })
}
