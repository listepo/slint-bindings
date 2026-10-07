//! The process-wide Slint platform: one software window per component.
//!
//! Slint accepts exactly one platform per process and creates window adapters
//! through it, so this module owns both the install-once logic and the hand-off
//! of each freshly created window to the [`crate::EmbeddedHost`] that asked.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Instant;

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint::platform::{Platform, PlatformError, SetPlatformError, WindowAdapter};

use crate::Error;

thread_local! {
    // Slint objects are `!Send`; everything here lives on the host's UI thread.
    static INSTALLED: Cell<bool> = const { Cell::new(false) };
    static CREATED: RefCell<Option<Rc<MinimalSoftwareWindow>>> = const { RefCell::new(None) };
}

struct EmbedPlatform {
    start: Instant,
}

impl Platform for EmbedPlatform {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, PlatformError> {
        // The host keeps one persistent buffer per window, so Slint may repaint
        // only the dirty region of what it drew last time.
        let window = MinimalSoftwareWindow::new(RepaintBufferType::ReusedBuffer);
        CREATED.with_borrow_mut(|slot| *slot = Some(window.clone()));
        Ok(window)
    }

    fn duration_since_start(&self) -> core::time::Duration {
        self.start.elapsed()
    }
}

/// Installs the embedding platform once for this thread.
pub(crate) fn ensure_installed() -> Result<(), Error> {
    if INSTALLED.get() {
        return Ok(());
    }
    match slint::platform::set_platform(Box::new(EmbedPlatform {
        start: Instant::now(),
    })) {
        Ok(()) => {
            INSTALLED.set(true);
            Ok(())
        }
        Err(SetPlatformError::AlreadySet) => Err(Error::ForeignPlatform),
        // `SetPlatformError` is non-exhaustive; any future variant is still "not ours".
        Err(_) => Err(Error::ForeignPlatform),
    }
}

/// Takes the window the platform created most recently, if any.
pub(crate) fn take_created_window() -> Option<Rc<MinimalSoftwareWindow>> {
    CREATED.with_borrow_mut(Option::take)
}
