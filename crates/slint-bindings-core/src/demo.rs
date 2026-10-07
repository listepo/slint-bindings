//! The compiled demo component (`ui/demo.slint`).
//!
//! Separate from the host so the host stays generic over any component; the
//! Weft milestone replaces this with components built from a Weft tree.

// The Slint compiler's generated code unwraps internal invariants; the
// workspace lints are for code written here.
#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

slint::include_modules!();
