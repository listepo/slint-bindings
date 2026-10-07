//! Accessibility-tree queries over a live component.
//!
//! The element search comes from `i-slint-backend-testing`, but only its
//! `search_api` half: walking the item tree and reading accessible properties
//! and geometry needs no platform, so this works against a component running
//! on whatever platform the host installed — the testing backend in
//! `slint-testing-ffi`, the Flutter software renderer in the running app.
//! Installing the testing *platform* is a separate, explicit call that this
//! module never makes.
//!
//! Both FFI crates describe elements through here, so a headless test and a
//! test driving the live app see the same fields for the same element.

use i_slint_backend_testing::{ElementHandle, ElementQuery};
use serde_json::Value as JsonValue;

use crate::Instance;

impl Instance {
    /// Finds elements in this component's accessibility tree.
    ///
    /// `kind` is `all`, `label`, `id`, or `type`; `needle` carries the text to
    /// match and is unused for `all`.
    pub fn query_elements(
        &self,
        kind: &str,
        needle: Option<&str>,
    ) -> Result<Vec<ElementHandle>, String> {
        let root = &self.inner;
        let needle =
            || needle.ok_or_else(|| format!("query kind '{kind}' needs a value to match against"));
        match kind {
            // `from_root` already matches every descendant; adding
            // `match_descendants` would walk the tree twice and duplicate hits.
            "all" => Ok(ElementQuery::from_root(root).find_all()),
            "label" => Ok(ElementHandle::find_by_accessible_label(root, needle()?).collect()),
            "id" => Ok(ElementHandle::find_by_element_id(root, needle()?).collect()),
            "type" => Ok(ElementHandle::find_by_element_type_name(root, needle()?).collect()),
            other => Err(format!(
                "unknown query kind '{other}' (label, id, type, all)"
            )),
        }
    }
}

/// Serializes elements as a JSON array of descriptors.
pub fn describe_all(elements: &[ElementHandle]) -> Result<String, String> {
    let descriptors: Vec<JsonValue> = elements.iter().enumerate().map(describe).collect();
    serde_json::to_string(&descriptors).map_err(|e| format!("failed to serialize elements: {e}"))
}

/// One element as JSON: identity, accessible state, and geometry.
///
/// `index` is the element's position in the result it came from — the handle
/// tests use to act on it. Geometry is in Slint logical pixels, positioned
/// relative to the window, which is what a caller needs to convert an element
/// into a coordinate it can click.
fn describe((index, e): (usize, &ElementHandle)) -> JsonValue {
    let position = e.absolute_position();
    let size = e.size();
    serde_json::json!({
        "index": index,
        "id": e.id().map(|s| s.to_string()),
        "typeName": e.type_name().map(|s| s.to_string()),
        "role": e.accessible_role().map(|r| format!("{r:?}")),
        "label": e.accessible_label().map(|s| s.to_string()),
        "value": e.accessible_value().map(|s| s.to_string()),
        "placeholder": e.accessible_placeholder_text().map(|s| s.to_string()),
        "description": e.accessible_description().map(|s| s.to_string()),
        "checked": e.accessible_checked(),
        "checkable": e.accessible_checkable(),
        "enabled": e.accessible_enabled(),
        "itemIndex": e.accessible_item_index(),
        "itemCount": e.accessible_item_count(),
        "x": position.x,
        "y": position.y,
        "width": size.width,
        "height": size.height,
    })
}
