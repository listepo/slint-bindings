#![allow(non_camel_case_types)]
// C ABI entry points: only ever called through the C ABI with the pointer
// contract in the header — marking them `unsafe fn` changes nothing for
// those callers, and every dereference is already an explicit unsafe block.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

//! C ABI over `i-slint-backend-testing`: instantiate a `.slint` component on
//! the testing platform and inspect it through the accessibility tree, so
//! tests assert on elements rather than pixels.
//!
//! Everything here is synchronous. The testing backend runs with
//! `init_no_event_loop`, so clicks go through the accessible *default action*
//! rather than the async pointer-event helpers, which need a running event
//! loop.

use std::cell::{Cell, RefCell};
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::ptr;
use std::time::Duration;

use i_slint_backend_testing::{init_no_event_loop, mock_elapsed_time};
use slint_dart_interpreter::{
    describe_all, Definition, ElementHandle, Engine, Instance, JsonCallback,
};

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
    // The testing platform is per-thread (`threading: false`), and
    // `init_no_event_loop` panics if a platform is already set.
    static BACKEND_READY: Cell<bool> = const { Cell::new(false) };
    // Return value of the host callback running right now, handed over by
    // slint_testing_callback_set_result. Cleared before each call and taken
    // after it, so a nested callback cannot leak its result outward.
    static CALLBACK_RESULT: RefCell<Option<String>> = const { RefCell::new(None) };
    // Slint takes the handler out for the duration of a call; registering a
    // new one while it runs panics. Host code may replace a handler from
    // inside its own callback, so defer those until the call returns.
    static HOST_CALLBACK_DEPTH: Cell<u32> = const { Cell::new(0) };
}

fn set_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = Some(msg));
}

fn clear_error() {
    LAST_ERROR.with(|e| *e.borrow_mut() = None);
}

/// See `slint_dart_core::thread`: false (with the error set) off the owning thread.
fn on_owner_thread() -> bool {
    match slint_dart_core::thread::check() {
        Ok(()) => true,
        Err(e) => {
            set_error(e);
            false
        }
    }
}

fn ensure_backend() {
    BACKEND_READY.with(|ready| {
        if !ready.get() {
            init_no_event_loop();
            ready.set(true);
        }
    });
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

/// Reads a required C string argument, recording an error and returning
/// `None` when it is null or not UTF-8.
fn read_str<'a>(ptr: *const c_char, what: &str) -> Option<&'a str> {
    if ptr.is_null() {
        set_error(format!("{what} is null"));
        return None;
    }
    match unsafe { CStr::from_ptr(ptr) }.to_str() {
        Ok(s) => Some(s),
        Err(_) => {
            set_error(format!("{what} is not valid UTF-8"));
            None
        }
    }
}

/// Component names, sorted, so error messages do not vary run to run.
fn component_names(defs: &[Definition]) -> String {
    let mut names: Vec<String> = defs.iter().map(Definition::name).collect();
    names.sort();
    names.join(", ")
}

/// One component instantiated on the testing backend, plus the element
/// snapshot the last query produced.
struct App {
    instance: Instance,
    elements: Vec<ElementHandle>,
    pending_callbacks: RefCell<Vec<(String, JsonCallback)>>,
}

impl App {
    fn element(&self, index: usize, what: &str) -> Option<&ElementHandle> {
        match self.elements.get(index) {
            Some(e) if e.is_valid() => Some(e),
            Some(_) => {
                set_error(format!(
                    "element {index} is stale — re-run the query after {what}"
                ));
                None
            }
            None => {
                set_error(format!(
                    "element {index} out of range ({} in the last query)",
                    self.elements.len()
                ));
                None
            }
        }
    }

    fn flush_pending_callbacks(&self) {
        let pending: Vec<(String, JsonCallback)> =
            self.pending_callbacks.borrow_mut().drain(..).collect();
        for (name, callback) in pending {
            if let Err(e) = self.instance.set_callback_json(&name, callback) {
                set_error(e);
                return;
            }
        }
    }

    fn register_callback(
        &self,
        name: &str,
        cb: SlintTestingCallbackFn,
        user_data: *mut c_void,
    ) -> bool {
        let callback_box = host_callback(cb, user_data);
        if HOST_CALLBACK_DEPTH.with(|d| d.get()) > 0 {
            self.pending_callbacks
                .borrow_mut()
                .push((name.to_string(), callback_box));
            return true;
        }
        match self.instance.set_callback_json(name, callback_box) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        }
    }
}

fn host_callback(cb: SlintTestingCallbackFn, user_data: *mut c_void) -> JsonCallback {
    Box::new(move |json: &str| {
        HOST_CALLBACK_DEPTH.with(|d| d.set(d.get() + 1));
        let result = (|| {
            let cstr = CString::new(json).ok()?;
            CALLBACK_RESULT.with(|r| r.borrow_mut().take());
            cb(user_data, cstr.as_ptr());
            CALLBACK_RESULT.with(|r| r.borrow_mut().take())
        })();
        HOST_CALLBACK_DEPTH.with(|d| d.set(d.get() - 1));
        result
    })
}

fn finish_host_work(app: &App) {
    app.flush_pending_callbacks();
}

#[repr(transparent)]
pub struct SlintTestingApp(*mut c_void);

pub type SlintTestingCallbackFn = extern "C" fn(user_data: *mut c_void, args_json: *const c_char);

fn null_app() -> SlintTestingApp {
    SlintTestingApp(ptr::null_mut())
}

impl SlintTestingApp {
    fn get<'a>(&self) -> Option<&'a mut App> {
        if self.0.is_null() {
            set_error("null app handle".into());
            return None;
        }
        Some(unsafe { &mut *(self.0 as *mut App) })
    }
}

/// Last error, or null. Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_last_error() -> *mut c_char {
    LAST_ERROR
        .with(|e| e.borrow_mut().take())
        .map_or(ptr::null_mut(), to_c_string)
}

#[no_mangle]
pub extern "C" fn slint_testing_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = catch_unwind(|| drop(unsafe { CString::from_raw(s) }));
    }
}

/// Advances the testing backend's mock clock, driving animations and timers.
#[no_mangle]
pub extern "C" fn slint_testing_elapse_ms(millis: u64) {
    clear_error();
    if !on_owner_thread() {
        return;
    }
    let _ = catch_unwind(|| {
        ensure_backend();
        mock_elapsed_time(Duration::from_millis(millis));
    });
}

/// Compiles `source` and instantiates `component` on the testing backend.
/// `component` may be null only when the source exports exactly one.
#[no_mangle]
pub extern "C" fn slint_testing_app_new(
    source: *const c_char,
    path: *const c_char,
    component: *const c_char,
) -> SlintTestingApp {
    clear_error();
    if !on_owner_thread() {
        return null_app();
    }
    match catch_unwind(|| {
        ensure_backend();
        let Some(source) = read_str(source, "source") else {
            return null_app();
        };
        let path = if path.is_null() {
            ""
        } else {
            match read_str(path, "path") {
                Some(p) => p,
                None => return null_app(),
            }
        };
        let wanted = if component.is_null() {
            None
        } else {
            match read_str(component, "component") {
                Some(c) => Some(c),
                None => return null_app(),
            }
        };

        let mut engine = Engine::new();
        let defs = match engine.compile(source, path) {
            Ok(d) => d,
            Err(e) => {
                set_error(e);
                return null_app();
            }
        };
        let def = match wanted {
            Some(name) => match defs.iter().find(|d| d.name() == name) {
                Some(d) => d,
                None => {
                    set_error(format!(
                        "no component named '{name}' (found: {})",
                        component_names(&defs)
                    ));
                    return null_app();
                }
            },
            // The compiler hands components back in hash order, so "the first
            // one" is not the first in the source — it is arbitrary. Only omit
            // the name when there is nothing to be ambiguous about.
            None => match defs.as_slice() {
                [only] => only,
                [] => {
                    set_error("source exports no component".into());
                    return null_app();
                }
                many => {
                    set_error(format!(
                        "source exports {} components ({}) — name the one to test",
                        many.len(),
                        component_names(&defs)
                    ));
                    return null_app();
                }
            },
        };
        let instance = match def.instantiate() {
            Ok(i) => i,
            Err(e) => {
                set_error(e);
                return null_app();
            }
        };
        let app = App {
            instance,
            elements: Vec::new(),
            pending_callbacks: RefCell::new(Vec::new()),
        };
        SlintTestingApp(Box::into_raw(Box::new(app)) as *mut c_void)
    }) {
        Ok(app) => app,
        Err(_) => {
            set_error("panicked in slint_testing_app_new".into());
            null_app()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_testing_app_free(app: SlintTestingApp) {
    if !on_owner_thread() {
        return;
    }
    if !app.0.is_null() {
        let _ = catch_unwind(|| drop(unsafe { Box::from_raw(app.0 as *mut App) }));
    }
}

/// Runs a query and returns its matches as a JSON array of element
/// descriptors, replacing the previous snapshot. `kind` is one of `label`,
/// `id`, `type`, or `all`; `needle` is ignored for `all`.
///
/// Caller frees with [slint_testing_string_free]; null means error.
#[no_mangle]
pub extern "C" fn slint_testing_app_query(
    app: SlintTestingApp,
    kind: *const c_char,
    needle: *const c_char,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let Some(kind) = read_str(kind, "kind") else {
            return ptr::null_mut();
        };
        // `needle` is read only for the kinds that take one, so `all` may
        // legitimately pass null.
        let needle = if needle.is_null() {
            None
        } else {
            match read_str(needle, "needle") {
                Some(n) => Some(n),
                None => return ptr::null_mut(),
            }
        };
        let found: Vec<ElementHandle> = match app.instance.query_elements(kind, needle) {
            Ok(found) => found,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };

        let json = match describe_all(&found) {
            Ok(json) => json,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };
        app.elements = found;
        to_c_string(json)
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_query".into());
            ptr::null_mut()
        }
    }
}

/// Invokes the accessible default action of the element at `index` in the
/// last query's snapshot — a button press, a checkbox toggle.
#[no_mangle]
pub extern "C" fn slint_testing_app_click(app: SlintTestingApp, index: usize) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let Some(element) = app.element(index, "the click") else {
            return false;
        };
        element.invoke_accessible_default_action();
        finish_host_work(app);
        true
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_click".into());
        false
    })
}

/// Sets the accessible value of the element at `index` — typing into a text
/// input, moving a slider.
#[no_mangle]
pub extern "C" fn slint_testing_app_set_value(
    app: SlintTestingApp,
    index: usize,
    value: *const c_char,
) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let Some(value) = read_str(value, "value") else {
            return false;
        };
        let Some(element) = app.element(index, "the update") else {
            return false;
        };
        element.set_accessible_value(value);
        finish_host_work(app);
        true
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_set_value".into());
        false
    })
}

/// Property read; returns JSON. Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_app_get_property(
    app: SlintTestingApp,
    name: *const c_char,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let Some(name) = read_str(name, "name") else {
            return ptr::null_mut();
        };
        let result = match app.instance.get_property_json(name) {
            Ok(json) => to_c_string(json),
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        };
        finish_host_work(app);
        result
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_get_property".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_testing_app_set_property(
    app: SlintTestingApp,
    name: *const c_char,
    json: *const c_char,
) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let (Some(name), Some(json)) = (read_str(name, "name"), read_str(json, "json")) else {
            return false;
        };
        let ok = match app.instance.set_property_json(name, json) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        };
        if ok {
            finish_host_work(app);
        }
        ok
    })
    .unwrap_or_else(|_| {
        set_error("panicked in slint_testing_app_set_property".into());
        false
    })
}

/// Invokes a callback or function on the component; returns its result as
/// JSON. Caller frees with [slint_testing_string_free].
#[no_mangle]
pub extern "C" fn slint_testing_app_invoke(
    app: SlintTestingApp,
    name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let Some(app) = app.get() else {
            return ptr::null_mut();
        };
        let (Some(name), Some(args)) = (read_str(name, "name"), read_str(args_json, "args_json"))
        else {
            return ptr::null_mut();
        };
        let result = match app.instance.invoke_json(name, args) {
            Ok(json) => to_c_string(json),
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        };
        finish_host_work(app);
        result
    }) {
        Ok(json) => json,
        Err(_) => {
            set_error("panicked in slint_testing_app_invoke".into());
            ptr::null_mut()
        }
    }
}

/// Routes invocations of the callback `name` to `cb`, replacing whatever
/// handler the component had. `user_data` is handed back to `cb` untouched.
#[no_mangle]
pub extern "C" fn slint_testing_app_set_callback(
    app: SlintTestingApp,
    name: *const c_char,
    cb: SlintTestingCallbackFn,
    user_data: *mut c_void,
) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    if app.0.is_null() || name.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let Some(app) = app.get() else { return false };
        let Some(name) = read_str(name, "name") else {
            return false;
        };
        app.register_callback(name, cb, user_data)
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_testing_app_set_callback".into());
            false
        }
    }
}

/// Sets the return value of the host callback that is running right now, as
/// JSON. Only meaningful from inside a [SlintTestingCallbackFn]; the string is
/// copied, so the caller keeps ownership. Null clears it.
#[no_mangle]
pub extern "C" fn slint_testing_callback_set_result(json: *const c_char) {
    if !on_owner_thread() {
        return;
    }
    let _ = catch_unwind(|| {
        let value = if json.is_null() {
            None
        } else {
            unsafe { CStr::from_ptr(json) }
                .to_str()
                .ok()
                .map(str::to_string)
        };
        CALLBACK_RESULT.with(|r| *r.borrow_mut() = value);
    });
}
