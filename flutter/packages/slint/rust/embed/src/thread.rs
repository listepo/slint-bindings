//! Thread affinity of everything behind the Dart C ABIs.
//!
//! Slint objects are `!Send` and each FFI crate keeps its error slot in a
//! thread-local, so a call from any thread but the first caller's is
//! undefined behaviour. Every entry point checks this first and reports an
//! error instead of corrupting state.

use std::sync::OnceLock;
use std::thread::ThreadId;

static OWNER: OnceLock<ThreadId> = OnceLock::new();

/// `Ok` on the thread that made the first call into this library, `Err`
/// with a message for the error slot on any other.
pub fn check() -> Result<(), String> {
    let me = std::thread::current().id();
    if *OWNER.get_or_init(|| me) == me {
        Ok(())
    } else {
        Err(
            "called from a thread other than the one that first used Slint; \
             Slint is single-threaded, so drive a component only from the \
             isolate that created it"
                .into(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::check;

    #[test]
    fn the_first_caller_owns_the_library_and_another_thread_does_not() {
        assert!(check().is_ok());
        let joined = std::thread::spawn(check).join();
        assert!(matches!(
            joined,
            Ok(Err(ref err)) if err.contains("single-threaded")
        ));
    }
}
