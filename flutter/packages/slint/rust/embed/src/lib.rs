//! Embedding pieces shared by the native hosts and the Dart FFI.
//!
//! The C ABI in `slint-bindings` and the Dart FFI do not share a numeric event
//! encoding (`PointerButton` is 0 = left; Dart's `kind`/`button` bytes are the
//! map in [`events`]). They do share one process-wide software platform.

pub mod events;
pub mod platform;
pub mod thread;
