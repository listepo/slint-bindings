//! Host-driven Slint embedding.
//!
//! A native host (an `NSView`, a WinUI panel) owns the run loop, the surface
//! and the input. This crate installs a Slint platform with no event loop of
//! its own: the host resizes, forwards input, ticks timers and asks for a
//! frame whenever it wants one. M1 renders on the CPU into a buffer the host
//! owns; the GPU milestone swaps the renderer, not this API.

mod demo;
mod host;
mod platform;

pub use demo::DemoForm;
pub use host::{EmbeddedHost, Frame, PointerButton};

/// Everything that can go wrong while embedding.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// Another Slint platform (for example winit) was installed first.
    #[error("a different Slint platform is already installed in this process")]
    ForeignPlatform,
    /// Slint itself refused an operation.
    #[error("slint: {0}")]
    Platform(#[from] slint::PlatformError),
    /// The component did not ask for a window during construction.
    #[error("the component was created without a window adapter")]
    NoWindow,
    /// The caller's buffer cannot hold a frame of the current size.
    #[error("buffer holds {got} bytes, a {width}x{height} RGBA frame needs {needed}")]
    BufferTooSmall {
        /// Bytes the caller passed.
        got: usize,
        /// Bytes the frame needs.
        needed: usize,
        /// Frame width in physical pixels.
        width: u32,
        /// Frame height in physical pixels.
        height: u32,
    },
    /// `scale` was zero, negative, or not finite. Logical size is pixels divided by scale.
    #[error("scale must be finite and greater than zero (got {scale})")]
    BadScale {
        /// The rejected scale, in physical pixels per logical point.
        scale: f32,
    },
    /// The host passed a null pointer or another value this API rejects.
    #[error("{0}")]
    InvalidArgument(&'static str),
}
