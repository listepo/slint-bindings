//! The process-wide Slint platform: one software window per component.
//!
//! The install-once logic and the window hand-off live in `slint-embed`.
//! This module pins the buffer type the native hosts need: one persistent
//! buffer per window, so later frames can repaint only what changed.

use std::rc::Rc;

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint_embed::platform::InstallError;

use crate::Error;

/// Installs the embedding platform once for this thread.
pub(crate) fn ensure_installed() -> Result<(), Error> {
    slint_embed::platform::ensure_installed(RepaintBufferType::ReusedBuffer).map_err(
        |err| match err {
            InstallError::ForeignPlatform => Error::ForeignPlatform,
            InstallError::BufferMismatch => Error::BufferMismatch,
        },
    )
}

/// Takes the window the platform created most recently, if any.
pub(crate) fn take_created_window() -> Option<Rc<MinimalSoftwareWindow>> {
    slint_embed::platform::take_created_window()
}
