//! Runtime `.slint` path: wraps `slint-interpreter` behind a renderer-agnostic
//! engine API (compile, instantiate, JSON value bridge, callbacks).
//!
//! This crate never depends on build-time codegen (`slint-build`); the
//! compile-time path is the `slint_compiler`-generated AOT crate.
//! Renderer-agnostic event mapping lives in `slint-dart-core`.

use std::collections::HashMap;

use i_slint_compiler::langtype::Type;
use slint_interpreter::json::{value_from_json, JsonExt};
use slint_interpreter::{Compiler, ComponentDefinition, ComponentInstance, Value};

mod elements;
pub use elements::describe_all;
pub use i_slint_backend_testing::ElementHandle;

/// Wraps slint_interpreter::Compiler for building and managing Slint components.
pub struct Engine {
    compiler: Compiler,
}

impl Engine {
    /// Create a new Engine instance.
    pub fn new() -> Self {
        Engine {
            compiler: Compiler::default(),
        }
    }

    /// Compile Slint source code and return a list of component definitions.
    /// Fails only when no component was produced; warning-level diagnostics
    /// do not abort the build.
    pub fn compile(&mut self, source: &str, path: &str) -> Result<Vec<Definition>, String> {
        let source_str = source.to_string();
        let path_buf = std::path::PathBuf::from(path);

        let result = spin_on::spin_on(self.compiler.build_from_source(source_str, path_buf));

        let defs: Vec<Definition> = result.components().map(Definition).collect();
        if defs.is_empty() {
            let diags = result
                .diagnostics()
                .map(|d| d.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            return Err(if diags.is_empty() {
                "no exported component found".to_string()
            } else {
                diags
            });
        }

        Ok(defs)
    }
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

/// Wraps slint_interpreter::ComponentDefinition.
pub struct Definition(pub ComponentDefinition);

impl Definition {
    /// Get the component name.
    pub fn name(&self) -> String {
        self.0.name().to_string()
    }

    /// Instantiate this component definition into a running instance.
    pub fn instantiate(&self) -> Result<Instance, String> {
        let mut property_types = HashMap::new();
        let mut callback_types = HashMap::new();
        for (name, (ty, _vis)) in self.0.properties_and_callbacks() {
            match &ty {
                Type::Callback(_) => {
                    callback_types.insert(name, ty);
                }
                _ if ty.is_property_type() => {
                    property_types.insert(name, ty);
                }
                _ => {}
            }
        }
        Ok(Instance {
            inner: self.0.create().map_err(|e| format!("{:?}", e))?,
            property_types,
            callback_types,
        })
    }
}

/// A host callback: JSON array of arguments in, optional JSON result out.
pub type JsonCallback = Box<dyn Fn(&str) -> Option<String> + 'static>;

/// Wraps slint_interpreter::ComponentInstance with property/callback types
/// for the JSON wire format.
pub struct Instance {
    pub inner: ComponentInstance,
    property_types: HashMap<String, Type>,
    callback_types: HashMap<String, Type>,
}

impl Instance {
    /// Get a property value as JSON string.
    pub fn get_property_json(&self, name: &str) -> Result<String, String> {
        let value = self
            .inner
            .get_property(name)
            .map_err(|e| format!("Failed to get property '{}': {:?}", name, e))?;
        value.to_json_string()
    }

    /// Set a property value from a JSON string.
    pub fn set_property_json(&self, name: &str, json: &str) -> Result<(), String> {
        let ty = self
            .property_types
            .get(name)
            .ok_or_else(|| format!("unknown property '{name}'"))?;
        let value = Value::from_json_str(ty, json)?;
        self.inner
            .set_property(name, value)
            .map_err(|e| format!("Failed to set property '{}': {:?}", name, e))
    }

    /// Invoke a callback or method with JSON array arguments, returning JSON result.
    pub fn invoke_json(&self, name: &str, args_json: &str) -> Result<String, String> {
        let args_val: serde_json::Value = serde_json::from_str(args_json)
            .map_err(|e| format!("Failed to parse args JSON: {}", e))?;

        let args_array = args_val
            .as_array()
            .ok_or_else(|| "args_json must be a JSON array".to_string())?;

        let ty = self
            .callback_types
            .get(name)
            .ok_or_else(|| format!("unknown callback '{name}'"))?;
        let Type::Callback(f) = ty else {
            return Err(format!("'{name}' is not a callback"));
        };
        if args_array.len() != f.args.len() {
            return Err(format!(
                "callback '{name}' expects {} arguments, got {}",
                f.args.len(),
                args_array.len()
            ));
        }

        let args: Vec<Value> = f
            .args
            .iter()
            .zip(args_array.iter())
            .map(|(arg_ty, json)| value_from_json(arg_ty, json))
            .collect::<Result<Vec<_>, _>>()?;

        let result = self
            .inner
            .invoke(name, &args)
            .map_err(|e| format!("Failed to invoke '{}': {:?}", name, e))?;

        result.to_json_string()
    }

    /// Register a host callback; arguments arrive as a JSON array string.
    /// The handler's JSON result becomes the callback's return value; `None`
    /// (or JSON the bridge cannot convert) returns Void, which Slint reads as
    /// the declared type's default.
    pub fn set_callback_json(&self, name: &str, f: JsonCallback) -> Result<(), String> {
        let return_ty = self
            .callback_types
            .get(name)
            .and_then(|ty| match ty {
                Type::Callback(f) => Some(f.return_type.clone()),
                _ => None,
            })
            .unwrap_or(Type::Void);

        self.inner
            .set_callback(name, move |args: &[Value]| {
                let arr: Vec<serde_json::Value> = args
                    .iter()
                    .map(|v| v.to_json().unwrap_or(serde_json::Value::Null))
                    .collect();
                serde_json::to_string(&serde_json::Value::Array(arr))
                    .ok()
                    .and_then(|json_str| f(&json_str))
                    .and_then(|result| Value::from_json_str(&return_ty, &result).ok())
                    .unwrap_or(Value::Void)
            })
            .map_err(|e| format!("{:?}", e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn color_property_roundtrips_through_json() {
        i_slint_backend_testing::init_no_event_loop();
        let source = r#"
export component C inherits Window {
    in-out property <color> accent: #ff0000;
}
"#;
        let mut engine = Engine::new();
        let def = engine
            .compile(source, "test.slint")
            .unwrap()
            .into_iter()
            .find(|d| d.name() == "C")
            .unwrap();
        let inst = def.instantiate().unwrap();
        inst.set_property_json("accent", "\"#00ff00ff\"").unwrap();
        let json = inst.get_property_json("accent").unwrap();
        assert_eq!(json, "\"#00ff00\"");
    }

    #[test]
    fn enum_property_roundtrips_through_json() {
        i_slint_backend_testing::init_no_event_loop();
        let source = r#"
export enum Status { active, done }
export component C inherits Window {
    in-out property <Status> state: active;
}
"#;
        let mut engine = Engine::new();
        let def = engine
            .compile(source, "test.slint")
            .unwrap()
            .into_iter()
            .find(|d| d.name() == "C")
            .unwrap();
        let inst = def.instantiate().unwrap();
        inst.set_property_json("state", "\"Status.done\"").unwrap();
        let json = inst.get_property_json("state").unwrap();
        assert_eq!(json, "\"Status.done\"");
    }
}
