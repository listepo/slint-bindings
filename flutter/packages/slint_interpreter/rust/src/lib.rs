#![allow(non_camel_case_types)]
// C ABI entry points: only ever called through the C ABI with the pointer
// contract in the header — marking them `unsafe fn` changes nothing for
// those callers, and every dereference is already an explicit unsafe block.
#![allow(clippy::not_unsafe_ptr_arg_deref)]

use std::cell::{Cell, RefCell};
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::ptr;
use std::rc::Rc;

use slint::platform::software_renderer::{
    MinimalSoftwareWindow, PremultipliedRgbaColor, RepaintBufferType,
};
use slint::ComponentHandle;
use slint::PhysicalSize;
use slint_dart_interpreter::{describe_all, Definition, Engine, Instance, JsonCallback};

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
    // Return value of the host callback running right now, handed over by
    // slint_interpreter_callback_set_result. Cleared before each call and
    // taken after it, so a nested callback cannot leak its result outward.
    static CALLBACK_RESULT: RefCell<Option<String>> = const { RefCell::new(None) };
    // Slint takes the handler out for the duration of a call; registering a
    // new one while it runs panics. Host code may replace a handler from
    // inside its own callback, so defer those until the call returns.
    static HOST_CALLBACK_DEPTH: Cell<u32> = const { Cell::new(0) };
}

fn set_error(msg: String) {
    LAST_ERROR.with(|e| *e.borrow_mut() = Some(msg));
}

fn ensure_platform_initialized() -> Result<(), String> {
    slint_dart_core::platform::ensure_installed(RepaintBufferType::NewBuffer)
        .map_err(|err| err.to_string())
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

fn get_error() -> Option<String> {
    LAST_ERROR.with(|e| e.borrow_mut().take())
}

// === Engine ===

#[repr(transparent)]
pub struct SlintInterpreterEngine(*mut c_void);

#[no_mangle]
pub extern "C" fn slint_interpreter_engine_new() -> SlintInterpreterEngine {
    clear_error();
    if !on_owner_thread() {
        return SlintInterpreterEngine(ptr::null_mut());
    }
    match catch_unwind(|| {
        let engine = Engine::new();
        Box::into_raw(Box::new(engine)) as *mut c_void
    }) {
        Ok(ptr) => SlintInterpreterEngine(ptr),
        Err(_) => {
            set_error("panicked in slint_interpreter_engine_new".into());
            SlintInterpreterEngine(ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_engine_free(engine: SlintInterpreterEngine) {
    if !on_owner_thread() {
        return;
    }
    if !engine.0.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { Box::from_raw(engine.0 as *mut Engine) });
        });
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_engine_compile(
    engine: SlintInterpreterEngine,
    source: *const c_char,
    path: *const c_char,
) -> SlintInterpreterDefinitionList {
    clear_error();
    if !on_owner_thread() {
        return SlintInterpreterDefinitionList(ptr::null_mut());
    }
    match catch_unwind(|| {
        if engine.0.is_null() || source.is_null() {
            set_error("null engine or source".into());
            return SlintInterpreterDefinitionList(ptr::null_mut());
        }

        let source_str = match unsafe { CStr::from_ptr(source) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("source is not valid UTF-8".into());
                return SlintInterpreterDefinitionList(ptr::null_mut());
            }
        };

        let path_str = if path.is_null() {
            "".to_string()
        } else {
            match unsafe { CStr::from_ptr(path) }.to_str() {
                Ok(s) => s.to_string(),
                Err(_) => {
                    set_error("path is not valid UTF-8".into());
                    return SlintInterpreterDefinitionList(ptr::null_mut());
                }
            }
        };

        let engine = unsafe { &mut *(engine.0 as *mut Engine) };
        let defs = match engine.compile(source_str, &path_str) {
            Ok(d) => d,
            Err(e) => {
                set_error(e);
                return SlintInterpreterDefinitionList(ptr::null_mut());
            }
        };

        let list = Box::new(defs);
        SlintInterpreterDefinitionList(Box::into_raw(list) as *mut c_void)
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_interpreter_engine_compile".into());
            SlintInterpreterDefinitionList(ptr::null_mut())
        }
    }
}

// === Definitions ===

#[repr(transparent)]
pub struct SlintInterpreterDefinitionList(*mut c_void);

#[no_mangle]
pub extern "C" fn slint_interpreter_definitions_count(list: SlintInterpreterDefinitionList) -> u32 {
    if !on_owner_thread() {
        return 0;
    }
    if list.0.is_null() {
        return 0;
    }
    catch_unwind(|| {
        let defs = unsafe { &*(list.0 as *const Vec<Definition>) };
        defs.len() as u32
    })
    .unwrap_or_default()
}

#[no_mangle]
pub extern "C" fn slint_interpreter_definitions_name(
    list: SlintInterpreterDefinitionList,
    index: u32,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    if list.0.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let defs = unsafe { &*(list.0 as *const Vec<Definition>) };
        if (index as usize) >= defs.len() {
            set_error("index out of bounds".into());
            return ptr::null_mut();
        }
        match CString::new(defs[index as usize].name()) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => {
                set_error("name contains null byte".into());
                ptr::null_mut()
            }
        }
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_interpreter_definitions_name".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_definitions_free(list: SlintInterpreterDefinitionList) {
    if !on_owner_thread() {
        return;
    }
    if !list.0.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { Box::from_raw(list.0 as *mut Vec<Definition>) });
        });
    }
}

// === Instance ===

#[repr(transparent)]
pub struct SlintInterpreterInstance(*mut c_void);

pub type SlintInterpreterCallbackFn =
    extern "C" fn(user_data: *mut c_void, args_json: *const c_char);
struct InstanceHandle {
    core: Instance,
    window: Rc<MinimalSoftwareWindow>,
    pending_callbacks: RefCell<Vec<(String, JsonCallback)>>,
}

impl InstanceHandle {
    fn flush_pending_callbacks(&self) {
        let pending: Vec<(String, JsonCallback)> =
            self.pending_callbacks.borrow_mut().drain(..).collect();
        for (name, callback) in pending {
            if let Err(e) = self.core.set_callback_json(&name, callback) {
                set_error(e);
                return;
            }
        }
    }

    fn register_callback(
        &self,
        name: &str,
        cb: SlintInterpreterCallbackFn,
        user_data: *mut c_void,
    ) -> bool {
        let callback_box = host_callback(cb, user_data);
        if HOST_CALLBACK_DEPTH.with(|d| d.get()) > 0 {
            self.pending_callbacks
                .borrow_mut()
                .push((name.to_string(), callback_box));
            return true;
        }
        match self.core.set_callback_json(name, callback_box) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        }
    }
}

fn host_callback(cb: SlintInterpreterCallbackFn, user_data: *mut c_void) -> JsonCallback {
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

fn finish_host_work(handle: &InstanceHandle) {
    handle.flush_pending_callbacks();
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instantiate(
    list: SlintInterpreterDefinitionList,
    index: u32,
) -> SlintInterpreterInstance {
    clear_error();
    if !on_owner_thread() {
        return SlintInterpreterInstance(ptr::null_mut());
    }
    if list.0.is_null() {
        return SlintInterpreterInstance(ptr::null_mut());
    }
    if let Err(e) = ensure_platform_initialized() {
        set_error(e);
        return SlintInterpreterInstance(ptr::null_mut());
    }
    match catch_unwind(|| {
        let defs = unsafe { &*(list.0 as *const Vec<Definition>) };
        if (index as usize) >= defs.len() {
            set_error("index out of bounds".into());
            return ptr::null_mut();
        }

        let instance = match defs[index as usize].instantiate() {
            Ok(i) => i,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };

        // show() forces window creation through the shared software platform,
        // which parks the MinimalSoftwareWindow for this call to take.
        if let Err(e) = instance.inner.show() {
            set_error(format!("{:?}", e));
            return ptr::null_mut();
        }
        let window = match slint_dart_core::platform::take_created_window() {
            Some(w) => w,
            None => {
                set_error("platform did not create a window".into());
                return ptr::null_mut();
            }
        };

        let handle = InstanceHandle {
            core: instance,
            window,
            pending_callbacks: RefCell::new(Vec::new()),
        };

        Box::into_raw(Box::new(handle)) as *mut c_void
    }) {
        Ok(ptr) => SlintInterpreterInstance(ptr),
        Err(_) => {
            set_error("panicked in slint_interpreter_instantiate".into());
            SlintInterpreterInstance(ptr::null_mut())
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_free(instance: SlintInterpreterInstance) {
    if !on_owner_thread() {
        return;
    }
    if !instance.0.is_null() {
        let _ = catch_unwind(|| {
            let handle = unsafe { Box::from_raw(instance.0 as *mut InstanceHandle) };
            // show() parked a strong reference to the component in its
            // window; without hide() the component, its timers and its
            // callbacks outlive the free.
            let _ = handle.core.inner.hide();
            drop(handle);
        });
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_set_size(
    instance: SlintInterpreterInstance,
    width: u32,
    height: u32,
) {
    if !on_owner_thread() {
        return;
    }
    if instance.0.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        handle.window.set_size(PhysicalSize::new(width, height));
    });
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_render(
    instance: SlintInterpreterInstance,
    buffer: *mut u8,
    len: usize,
) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    if instance.0.is_null() || buffer.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        let size = handle.window.size();
        let expected_len = (size.width as usize) * (size.height as usize) * 4;
        if len != expected_len {
            set_error(format!(
                "buffer size mismatch: expected {}, got {}",
                expected_len, len
            ));
            return false;
        }

        let pixels = unsafe {
            std::slice::from_raw_parts_mut(buffer as *mut PremultipliedRgbaColor, len / 4)
        };

        slint::platform::update_timers_and_animations();

        let mut drawn = false;
        handle.window.draw_if_needed(|renderer| {
            renderer.render(pixels, size.width as usize);
            drawn = true;
        });

        finish_host_work(handle);
        drawn
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_interpreter_instance_render".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_pointer_event(
    instance: SlintInterpreterInstance,
    kind: u8,
    x: f32,
    y: f32,
    button: u8,
    dx: f32,
    dy: f32,
) {
    if !on_owner_thread() {
        return;
    }
    if instance.0.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        if let Some(event) = slint_dart_core::events::pointer_event(kind, x, y, button, dx, dy) {
            let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
            handle.window.dispatch_event(event);
            finish_host_work(handle);
        }
    });
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_key_event(
    instance: SlintInterpreterInstance,
    text: *const c_char,
    pressed: bool,
) {
    if !on_owner_thread() {
        return;
    }
    if instance.0.is_null() || text.is_null() {
        return;
    }
    let _ = catch_unwind(|| {
        if let Ok(text_str) = unsafe { CStr::from_ptr(text) }.to_str() {
            let event = slint_dart_core::events::key_event(text_str, pressed);
            let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
            handle.window.dispatch_event(event);
            finish_host_work(handle);
        }
    });
}

/// Finds elements in this instance's accessibility tree and returns them as a
/// JSON array of descriptors — identity, accessible state, and geometry in
/// Slint logical pixels relative to the window.
///
/// `kind` is one of `label`, `id`, `type`, or `all`; `needle` carries the text
/// to match and may be null for `all`. This is what lets a test find a Slint
/// element and work out where to click it; the descriptors match the ones
/// `slint-testing-ffi` produces, because both come from `describe_all`.
///
/// Caller frees with [slint_interpreter_string_free]; null means error.
#[no_mangle]
pub extern "C" fn slint_interpreter_instance_query_elements(
    instance: SlintInterpreterInstance,
    kind: *const c_char,
    needle: *const c_char,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    if instance.0.is_null() || kind.is_null() {
        set_error("instance and kind must not be null".into());
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let Ok(kind) = (unsafe { CStr::from_ptr(kind) }).to_str() else {
            set_error("query kind is not valid UTF-8".into());
            return ptr::null_mut();
        };
        let needle = if needle.is_null() {
            None
        } else {
            match unsafe { CStr::from_ptr(needle) }.to_str() {
                Ok(n) => Some(n),
                Err(_) => {
                    set_error("query value is not valid UTF-8".into());
                    return ptr::null_mut();
                }
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        let found = match handle.core.query_elements(kind, needle) {
            Ok(found) => found,
            Err(e) => {
                set_error(e);
                return ptr::null_mut();
            }
        };
        match describe_all(&found)
            .and_then(|json| CString::new(json).map_err(|_| "json contains null byte".to_string()))
        {
            Ok(cstr) => cstr.into_raw(),
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        }
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_interpreter_instance_query_elements".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_get_property(
    instance: SlintInterpreterInstance,
    name: *const c_char,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    if instance.0.is_null() || name.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("property name is not valid UTF-8".into());
                return ptr::null_mut();
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        let result = match handle.core.get_property_json(name_str) {
            Ok(json) => match CString::new(json) {
                Ok(cstr) => cstr.into_raw(),
                Err(_) => {
                    set_error("json contains null byte".into());
                    ptr::null_mut()
                }
            },
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        };
        finish_host_work(handle);
        result
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_interpreter_instance_get_property".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_set_property(
    instance: SlintInterpreterInstance,
    name: *const c_char,
    json: *const c_char,
) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    if instance.0.is_null() || name.is_null() || json.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("property name is not valid UTF-8".into());
                return false;
            }
        };
        let json_str = match unsafe { CStr::from_ptr(json) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("json is not valid UTF-8".into());
                return false;
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        let ok = match handle.core.set_property_json(name_str, json_str) {
            Ok(()) => true,
            Err(e) => {
                set_error(e);
                false
            }
        };
        if ok {
            finish_host_work(handle);
        }
        ok
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("panicked in slint_interpreter_instance_set_property".into());
            false
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_invoke(
    instance: SlintInterpreterInstance,
    name: *const c_char,
    args_json: *const c_char,
) -> *mut c_char {
    clear_error();
    if !on_owner_thread() {
        return ptr::null_mut();
    }
    if instance.0.is_null() || name.is_null() || args_json.is_null() {
        return ptr::null_mut();
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("callback name is not valid UTF-8".into());
                return ptr::null_mut();
            }
        };
        let args_str = match unsafe { CStr::from_ptr(args_json) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("args_json is not valid UTF-8".into());
                return ptr::null_mut();
            }
        };

        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        let result = match handle.core.invoke_json(name_str, args_str) {
            Ok(result) => match CString::new(result) {
                Ok(cstr) => cstr.into_raw(),
                Err(_) => {
                    set_error("result contains null byte".into());
                    ptr::null_mut()
                }
            },
            Err(e) => {
                set_error(e);
                ptr::null_mut()
            }
        };
        finish_host_work(handle);
        result
    }) {
        Ok(ptr) => ptr,
        Err(_) => {
            set_error("panicked in slint_interpreter_instance_invoke".into());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_instance_set_callback(
    instance: SlintInterpreterInstance,
    name: *const c_char,
    cb: SlintInterpreterCallbackFn,
    user_data: *mut c_void,
) -> bool {
    clear_error();
    if !on_owner_thread() {
        return false;
    }
    if instance.0.is_null() || name.is_null() {
        return false;
    }
    match catch_unwind(|| {
        let name_str = match unsafe { CStr::from_ptr(name) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                set_error("Invalid callback name: not valid UTF-8".to_string());
                return false;
            }
        };
        let handle = unsafe { &*(instance.0 as *const InstanceHandle) };
        handle.register_callback(name_str, cb, user_data)
    }) {
        Ok(result) => result,
        Err(_) => {
            set_error("Panic in slint_interpreter_instance_set_callback".to_string());
            false
        }
    }
}

/// Sets the return value of the host callback that is running right now, as
/// JSON. Only meaningful from inside a [SlintInterpreterCallbackFn]; the
/// string is copied, so the caller keeps ownership. Null clears it.
#[no_mangle]
pub extern "C" fn slint_interpreter_callback_set_result(json: *const c_char) {
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

// === String memory management ===

#[no_mangle]
pub extern "C" fn slint_interpreter_string_free(s: *mut c_char) {
    if !s.is_null() {
        let _ = catch_unwind(|| {
            drop(unsafe { CString::from_raw(s) });
        });
    }
}

#[no_mangle]
pub extern "C" fn slint_interpreter_last_error() -> *mut c_char {
    match get_error() {
        Some(err) => match CString::new(err) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => ptr::null_mut(),
        },
        None => ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn doubles(_user_data: *mut c_void, args_json: *const c_char) {
        let args = unsafe { CStr::from_ptr(args_json) }.to_str().unwrap();
        let n: i64 = args.trim_matches(['[', ']']).parse().unwrap();
        let result = CString::new((n * 2).to_string()).unwrap();
        slint_interpreter_callback_set_result(result.as_ptr());
    }

    fn take_string(p: *mut c_char) -> String {
        assert!(!p.is_null(), "{:?}", get_error());
        let s = unsafe { CStr::from_ptr(p) }.to_str().unwrap().to_string();
        slint_interpreter_string_free(p);
        s
    }

    // One test: every entry point pins the thread that first calls in, and
    // libtest runs each test on a thread of its own.
    #[test]
    fn callback_results_and_free() {
        let engine = slint_interpreter_engine_new();
        let src = CString::new(
            "export component T inherits Window {
                pure callback compute(int) -> int;
                out property <int> shown: compute(21);
            }",
        )
        .unwrap();
        let path = CString::new("t.slint").unwrap();
        let defs = slint_interpreter_engine_compile(
            SlintInterpreterEngine(engine.0),
            src.as_ptr(),
            path.as_ptr(),
        );
        assert!(!defs.0.is_null(), "{:?}", get_error());
        let inst = slint_interpreter_instantiate(SlintInterpreterDefinitionList(defs.0), 0);
        assert!(!inst.0.is_null(), "{:?}", get_error());

        let name = CString::new("compute").unwrap();
        assert!(slint_interpreter_instance_set_callback(
            SlintInterpreterInstance(inst.0),
            name.as_ptr(),
            doubles,
            ptr::null_mut(),
        ));
        // A host callback's return value reaches Slint: through invoke, and
        // through a binding that calls it.
        let args = CString::new("[5]").unwrap();
        let invoked = slint_interpreter_instance_invoke(
            SlintInterpreterInstance(inst.0),
            name.as_ptr(),
            args.as_ptr(),
        );
        assert_eq!(take_string(invoked), "10");
        let shown = CString::new("shown").unwrap();
        let value = slint_interpreter_instance_get_property(
            SlintInterpreterInstance(inst.0),
            shown.as_ptr(),
        );
        assert_eq!(take_string(value), "42");

        // Freeing must release the component, not leave it owned by its
        // window (which show() gave a strong reference).
        let weak = unsafe { &*(inst.0 as *const InstanceHandle) }
            .core
            .inner
            .as_weak();
        slint_interpreter_instance_free(inst);
        assert!(weak.upgrade().is_none(), "component outlived its free");

        slint_interpreter_definitions_free(defs);
        slint_interpreter_engine_free(engine);
    }
}
