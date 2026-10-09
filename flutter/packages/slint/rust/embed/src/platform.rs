//! One software platform per process, and a hand-off for each new window.
//!
//! Slint accepts exactly one platform. The native hosts ask for a reused
//! buffer (they keep the pixels). The Dart software renderer asks for a new
//! buffer (it paints into whatever pointer the caller passed this frame).

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Instant;

use slint::platform::software_renderer::{MinimalSoftwareWindow, RepaintBufferType};
use slint::platform::{Platform, PlatformError, SetPlatformError, WindowAdapter};

type NextWindow = Box<dyn FnOnce() -> Result<Rc<dyn WindowAdapter>, PlatformError>>;

thread_local! {
    // Slint objects are `!Send`; the hand-off lives on the installing thread.
    static INSTALLED: Cell<Option<RepaintBufferType>> = const { Cell::new(None) };
    static CREATED: RefCell<Option<Rc<MinimalSoftwareWindow>>> = const { RefCell::new(None) };
    // One-shot override so a GPU window can be born from this same platform.
    // Empty for every software window, which is the Dart renderer and the CPU hosts.
    static NEXT: RefCell<Option<NextWindow>> = const { RefCell::new(None) };
}

struct EmbedPlatform {
    start: Instant,
    buffer: RepaintBufferType,
}

impl Platform for EmbedPlatform {
    fn create_window_adapter(&self) -> Result<Rc<dyn WindowAdapter>, PlatformError> {
        // A GPU host stages its own adapter for this one component. Software
        // windows, including every Dart view, leave the slot empty.
        if let Some(factory) = NEXT.with_borrow_mut(Option::take) {
            return factory();
        }
        let window = MinimalSoftwareWindow::new(self.buffer);
        CREATED.with_borrow_mut(|slot| *slot = Some(window.clone()));
        Ok(window)
    }

    fn duration_since_start(&self) -> core::time::Duration {
        self.start.elapsed()
    }
}

/// Why [`ensure_installed`] refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallError {
    /// Some other platform (for example winit) is already set.
    ForeignPlatform,
    /// This platform is already set, but for the other buffer type.
    BufferMismatch,
}

impl std::fmt::Display for InstallError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::ForeignPlatform => {
                "a different Slint platform is already installed in this process"
            }
            Self::BufferMismatch => {
                "the embedding platform is already installed with a different buffer type"
            }
        })
    }
}

impl std::error::Error for InstallError {}

/// Installs the embedding platform once for this thread.
///
/// A second call with the same `buffer` is a no-op. A second call with the
/// other buffer type fails: Slint will not replace a platform.
pub fn ensure_installed(buffer: RepaintBufferType) -> Result<(), InstallError> {
    if let Some(existing) = INSTALLED.with(Cell::get) {
        return if existing == buffer {
            Ok(())
        } else {
            Err(InstallError::BufferMismatch)
        };
    }
    match slint::platform::set_platform(Box::new(EmbedPlatform {
        start: Instant::now(),
        buffer,
    })) {
        Ok(()) => {
            INSTALLED.with(|slot| slot.set(Some(buffer)));
            Ok(())
        }
        Err(SetPlatformError::AlreadySet) => Err(InstallError::ForeignPlatform),
        // `SetPlatformError` is non-exhaustive; any future variant is still "not ours".
        Err(_) => Err(InstallError::ForeignPlatform),
    }
}

/// Takes the window the platform created most recently, if any.
pub fn take_created_window() -> Option<Rc<MinimalSoftwareWindow>> {
    CREATED.with_borrow_mut(Option::take)
}

/// Makes the next `create_window_adapter` call return `factory`'s window.
///
/// Slint allows one platform per process. CPU and GPU hosts share this one;
/// the GPU host stages its adapter, creates the component, and the slot is
/// consumed. A software window created while the slot is set would receive
/// the GPU adapter, so [`clear_next_window`] runs if component creation fails.
pub fn set_next_window(factory: NextWindow) {
    NEXT.with_borrow_mut(|slot| *slot = Some(factory));
}

/// Drops a staged GPU window that nothing consumed.
///
/// Returns whether a factory was waiting.
pub fn clear_next_window() -> bool {
    NEXT.with_borrow_mut(|slot| slot.take().is_some())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_staged_window_is_cleared_once() {
        set_next_window(Box::new(|| Err(PlatformError::from("staged"))));
        assert!(clear_next_window());
        assert!(!clear_next_window());
    }
}
