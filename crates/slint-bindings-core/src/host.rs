//! One embedded component and the pixel buffer it renders into.
//!
//! The host drives everything: size, scale, input, timers and frames. Nothing
//! here blocks or spins a loop, so it fits any native run loop (AppKit's main
//! thread, the WinUI dispatcher) as long as every call comes from that thread.

use std::cell::Cell;
use std::mem::{align_of, offset_of, size_of};
use std::rc::Rc;
use std::time::{Duration, Instant};

use slint::platform::software_renderer::{
    MinimalSoftwareWindow, PremultipliedRgbaColor, RepaintBufferType,
};
use slint::platform::{PointerEventButton, WindowEvent};
use slint::{ComponentHandle, LogicalPosition, LogicalSize, PhysicalSize, SharedString};

use crate::{Error, platform};

/// Bytes per pixel in the RGBA8 frames handed to the host.
pub const BYTES_PER_PIXEL: usize = 4;

/// Two vsync callbacks on the same thread closer than this share one timer tick.
const TICK_COALESCE: Duration = Duration::from_millis(1);

thread_local! {
    static LAST_TICK: Cell<Option<Instant>> = const { Cell::new(None) };
}

const TRANSPARENT: PremultipliedRgbaColor = PremultipliedRgbaColor {
    red: 0,
    green: 0,
    blue: 0,
    alpha: 0,
};

// `PremultipliedRgbaColor` is `#[repr(C)]` RGBA8. These fail the build if a
// future Slint release reorders the fields, which would make the frame copy
// below write the wrong channels.
const _: () = {
    assert!(size_of::<PremultipliedRgbaColor>() == BYTES_PER_PIXEL);
    assert!(align_of::<PremultipliedRgbaColor>() == 1);
    assert!(offset_of!(PremultipliedRgbaColor, red) == 0);
    assert!(offset_of!(PremultipliedRgbaColor, green) == 1);
    assert!(offset_of!(PremultipliedRgbaColor, blue) == 2);
    assert!(offset_of!(PremultipliedRgbaColor, alpha) == 3);
};

fn check_scale(scale: f32) -> Result<(), Error> {
    if scale.is_finite() && scale > 0.0 {
        Ok(())
    } else {
        Err(Error::BadScale { scale })
    }
}

/// Mouse buttons the host can forward.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PointerButton {
    /// Primary button.
    Left = 0,
    /// Secondary button.
    Right = 1,
    /// Wheel button.
    Middle = 2,
}

impl From<PointerButton> for PointerEventButton {
    fn from(button: PointerButton) -> Self {
        match button {
            PointerButton::Left => Self::Left,
            PointerButton::Right => Self::Right,
            PointerButton::Middle => Self::Middle,
        }
    }
}

impl TryFrom<u8> for PointerButton {
    type Error = Error;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Left),
            1 => Ok(Self::Right),
            2 => Ok(Self::Middle),
            _ => Err(Error::InvalidArgument(
                "pointer button must be 0 (left), 1 (right) or 2 (middle)",
            )),
        }
    }
}

/// What a call to [`EmbeddedHost::render`] did.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Frame {
    /// The buffer was written; the host must present it.
    pub redrawn: bool,
    /// Animations are running; the host should ask for another frame on its next vsync.
    pub animating: bool,
}

/// A Slint component rendered into a host-owned RGBA8 buffer.
pub struct EmbeddedHost<C: ComponentHandle> {
    component: C,
    window: Rc<MinimalSoftwareWindow>,
    pixels: Vec<PremultipliedRgbaColor>,
    width: u32,
    height: u32,
    scale: f32,
    /// The pixel storage was replaced. The reused-buffer renderer would otherwise
    /// repaint only dirty items and leave the rest of the new buffer transparent.
    full_repaint: bool,
}

impl<C: ComponentHandle> EmbeddedHost<C> {
    /// Creates the component through `make` and sizes it to `width`×`height`
    /// physical pixels at `scale` physical pixels per logical point.
    pub fn new(
        make: impl FnOnce() -> Result<C, slint::PlatformError>,
        width: u32,
        height: u32,
        scale: f32,
    ) -> Result<Self, Error> {
        check_scale(scale)?;
        platform::ensure_installed()?;
        // A window left over from a component that failed half-way is not ours.
        drop(platform::take_created_window());
        let component = make()?;
        // Window adapters are created lazily; asking for the window forces it.
        let _ = component.window();
        let window = platform::take_created_window().ok_or(Error::NoWindow)?;
        component.show()?;
        let mut host = Self {
            component,
            window,
            pixels: Vec::new(),
            width: 0,
            height: 0,
            scale,
            full_repaint: true,
        };
        host.resize(width, height, scale)?;
        Ok(host)
    }

    /// The component, for its generated property and callback accessors.
    pub fn component(&self) -> &C {
        &self.component
    }

    /// Current frame size in physical pixels.
    pub fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    /// Bytes a buffer passed to [`Self::render`] must hold.
    pub fn frame_len(&self) -> usize {
        self.width as usize * self.height as usize * BYTES_PER_PIXEL
    }

    /// Resizes the frame. A zero dimension is clamped to one pixel, because
    /// hosts report zero-sized views during layout and Slint cannot render them.
    pub fn resize(&mut self, width: u32, height: u32, scale: f32) -> Result<(), Error> {
        check_scale(scale)?;
        // Hosts report 0×0 while a view is being laid out. Slint cannot render that.
        let (width, height) = (width.max(1), height.max(1));
        // SwiftUI calls this on every layout pass. Reallocating the reused buffer
        // when nothing changed throws away the previous frame and forces a full paint.
        if width == self.width && height == self.height && scale == self.scale {
            return Ok(());
        }
        if scale != self.scale || self.width == 0 {
            self.dispatch(WindowEvent::ScaleFactorChanged {
                scale_factor: scale,
            })?;
        }
        self.scale = scale;
        self.width = width;
        self.height = height;
        self.window.set_size(PhysicalSize::new(width, height));
        self.dispatch(WindowEvent::Resized {
            size: LogicalSize::new(width as f32 / scale, height as f32 / scale),
        })?;
        let len = width as usize * height as usize;
        if self.pixels.len() == len {
            // Same pixel count (scale-only change): drop stale samples, keep the allocation.
            self.pixels.fill(TRANSPARENT);
        } else {
            self.pixels = vec![TRANSPARENT; len];
        }
        self.full_repaint = true;
        self.window.request_redraw();
        Ok(())
    }

    /// Renders into `out` (premultiplied RGBA8, rows top to bottom, no padding)
    /// if anything changed. When nothing changed `out` is left untouched, so the
    /// host keeps presenting the previous frame.
    pub fn render(&mut self, out: &mut [u8]) -> Result<Frame, Error> {
        let needed = self.frame_len();
        if out.len() < needed {
            return Err(Error::BufferTooSmall {
                got: out.len(),
                needed,
                width: self.width,
                height: self.height,
            });
        }
        let stride = self.width as usize;
        let full_repaint = self.full_repaint;
        let pixels = &mut self.pixels;
        let redrawn = self.window.draw_if_needed(|renderer| {
            // NewBuffer paints every pixel. Switching back afterwards keeps later
            // frames partial, which is what the reused buffer is for.
            if full_repaint {
                renderer.set_repaint_buffer_type(RepaintBufferType::NewBuffer);
            }
            renderer.render(pixels, stride);
            if full_repaint {
                renderer.set_repaint_buffer_type(RepaintBufferType::ReusedBuffer);
            }
        });
        if redrawn {
            self.full_repaint = false;
        }
        if redrawn {
            let len = self.pixels.len() * BYTES_PER_PIXEL;
            if len != needed {
                return Err(Error::InvalidArgument(
                    "internal frame size does not match the pixel buffer",
                ));
            }
            write_frame(out, &self.pixels);
        }
        Ok(Frame {
            redrawn,
            animating: self.window.has_active_animations(),
        })
    }

    /// Advances timers and animations. Call once per display refresh.
    ///
    /// Timers are thread-global. Two host views often fire their vsync
    /// callbacks back-to-back; a second call within [`TICK_COALESCE`] is ignored
    /// so animations do not run twice as fast.
    pub fn tick() {
        LAST_TICK.with(|slot| {
            let now = Instant::now();
            if let Some(prev) = slot.get()
                && now.saturating_duration_since(prev) < TICK_COALESCE
            {
                return;
            }
            slot.set(Some(now));
            slint::platform::update_timers_and_animations();
        });
    }

    /// Pointer moved to `x`,`y` logical points from the top-left corner.
    pub fn pointer_moved(&self, x: f32, y: f32) -> Result<(), Error> {
        self.dispatch(WindowEvent::PointerMoved {
            position: LogicalPosition::new(x, y),
        })
    }

    /// Pointer button went down.
    pub fn pointer_pressed(&self, x: f32, y: f32, button: PointerButton) -> Result<(), Error> {
        let position = LogicalPosition::new(x, y);
        self.dispatch(WindowEvent::PointerPressed {
            position,
            button: button.into(),
        })
    }

    /// Pointer button went up.
    pub fn pointer_released(&self, x: f32, y: f32, button: PointerButton) -> Result<(), Error> {
        let position = LogicalPosition::new(x, y);
        self.dispatch(WindowEvent::PointerReleased {
            position,
            button: button.into(),
        })
    }

    /// Pointer left the view.
    pub fn pointer_exited(&self) -> Result<(), Error> {
        self.dispatch(WindowEvent::PointerExited)
    }

    /// Scroll wheel or trackpad delta, in logical points.
    pub fn pointer_scrolled(&self, x: f32, y: f32, dx: f32, dy: f32) -> Result<(), Error> {
        let position = LogicalPosition::new(x, y);
        self.dispatch(WindowEvent::PointerScrolled {
            position,
            delta_x: dx,
            delta_y: dy,
        })
    }

    /// A key went down; `text` is the character it produces or a Slint key code.
    pub fn key_pressed(&self, text: &str) -> Result<(), Error> {
        self.dispatch(WindowEvent::KeyPressed {
            text: SharedString::from(text),
        })
    }

    /// A key went up.
    pub fn key_released(&self, text: &str) -> Result<(), Error> {
        self.dispatch(WindowEvent::KeyReleased {
            text: SharedString::from(text),
        })
    }

    /// A held key auto-repeated. Distinct from [`Self::key_pressed`].
    pub fn key_repeated(&self, text: &str) -> Result<(), Error> {
        self.dispatch(WindowEvent::KeyPressRepeated {
            text: SharedString::from(text),
        })
    }

    /// The host view gained or lost keyboard focus.
    pub fn focus_changed(&self, focused: bool) -> Result<(), Error> {
        self.dispatch(WindowEvent::WindowActiveChanged(focused))
    }

    fn dispatch(&self, event: WindowEvent) -> Result<(), Error> {
        // Whether Slint consumed the event does not matter to a host that owns no other UI here.
        self.window.dispatch_event_with_result(event)?;
        Ok(())
    }
}

/// Copies packed RGBA8 into `out`. `out` may be longer than one frame; only the frame is written.
fn write_frame(out: &mut [u8], pixels: &[PremultipliedRgbaColor]) {
    let len = pixels.len() * BYTES_PER_PIXEL;
    let Some(dst) = out.get_mut(..len) else {
        return;
    };
    // SAFETY: the const asserts above pin `PremultipliedRgbaColor` as packed RGBA8
    // (`repr(C)`, 4 bytes, align 1), so this slice is the pixel bytes and nothing past them.
    let src = unsafe { std::slice::from_raw_parts(pixels.as_ptr().cast::<u8>(), len) };
    dst.copy_from_slice(src);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::DemoForm;

    const WIDTH: u32 = 320;
    const HEIGHT: u32 = 200;

    fn demo() -> Result<EmbeddedHost<DemoForm>, Error> {
        EmbeddedHost::new(DemoForm::new, WIDTH, HEIGHT, 1.0)
    }

    #[test]
    fn first_frame_paints_visible_pixels() -> Result<(), Error> {
        let mut host = demo()?;
        let mut buf = vec![0u8; host.frame_len()];
        let frame = host.render(&mut buf)?;
        assert!(frame.redrawn);
        assert!(
            buf.as_chunks::<BYTES_PER_PIXEL>()
                .0
                .iter()
                .any(|px| px[3] > 0)
        );
        Ok(())
    }

    #[test]
    fn unchanged_scene_is_not_redrawn() -> Result<(), Error> {
        let mut host = demo()?;
        let mut buf = vec![0u8; host.frame_len()];
        host.render(&mut buf)?;
        assert!(!host.render(&mut buf)?.redrawn);
        Ok(())
    }

    #[test]
    fn short_buffer_is_rejected_not_overrun() -> Result<(), Error> {
        let mut host = demo()?;
        let mut buf = vec![0u8; host.frame_len() - 1];
        assert!(matches!(
            host.render(&mut buf),
            Err(Error::BufferTooSmall { .. })
        ));
        Ok(())
    }

    #[test]
    fn resize_changes_frame_len_and_forces_redraw() -> Result<(), Error> {
        let mut host = demo()?;
        let mut buf = vec![0u8; host.frame_len()];
        host.render(&mut buf)?;
        host.resize(WIDTH * 2, HEIGHT * 2, 2.0)?;
        assert_eq!(
            host.frame_len(),
            (WIDTH * 2 * HEIGHT * 2) as usize * BYTES_PER_PIXEL
        );
        let mut buf = vec![0u8; host.frame_len()];
        assert!(host.render(&mut buf)?.redrawn);
        assert!(
            buf.as_chunks::<BYTES_PER_PIXEL>()
                .0
                .iter()
                .any(|px| px[3] > 0)
        );
        Ok(())
    }

    #[test]
    fn zero_size_from_layout_is_clamped() -> Result<(), Error> {
        let mut host = demo()?;
        host.resize(0, 0, 1.0)?;
        assert_eq!(host.size(), (1, 1));
        Ok(())
    }

    #[test]
    fn property_set_from_host_reaches_the_component() -> Result<(), Error> {
        let host = demo()?;
        host.component().set_name("Ivan".into());
        assert_eq!(host.component().get_name(), "Ivan");
        Ok(())
    }

    #[test]
    fn same_size_resize_keeps_the_painted_frame() -> Result<(), Error> {
        let mut host = demo()?;
        let mut buf = vec![0u8; host.frame_len()];
        host.render(&mut buf)?;
        host.resize(WIDTH, HEIGHT, 1.0)?;
        assert!(!host.render(&mut buf)?.redrawn);
        Ok(())
    }

    #[test]
    fn pointer_button_rejects_out_of_range() {
        assert!(PointerButton::try_from(0).is_ok());
        assert!(PointerButton::try_from(2).is_ok());
        assert!(matches!(
            PointerButton::try_from(3),
            Err(Error::InvalidArgument(_))
        ));
    }

    #[test]
    fn tick_twice_in_a_row_does_not_panic() -> Result<(), Error> {
        let _host = demo()?;
        EmbeddedHost::<DemoForm>::tick();
        EmbeddedHost::<DemoForm>::tick();
        Ok(())
    }

    #[test]
    fn non_positive_scale_is_rejected_and_the_frame_stays() -> Result<(), Error> {
        let mut host = demo()?;
        assert!(matches!(
            host.resize(WIDTH, HEIGHT, 0.0),
            Err(Error::BadScale { .. })
        ));
        assert!(matches!(
            host.resize(WIDTH, HEIGHT, f32::NAN),
            Err(Error::BadScale { .. })
        ));
        assert_eq!(host.size(), (WIDTH, HEIGHT));
        Ok(())
    }
}
