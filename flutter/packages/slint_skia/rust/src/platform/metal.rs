//! Apple: Skia renders into an `MTLTexture` the Swift plugin made from an
//! IOSurface-backed `CVPixelBuffer`, the same buffer its `FlutterTexture`
//! hands to Flutter.

use std::cell::RefCell;
use std::ffi::c_void;
use std::sync::Arc;

use i_slint_core::api::{PhysicalSize, Window};
use i_slint_core::graphics::RequestedGraphicsAPI;
use i_slint_core::partial_renderer::DirtyRegion;
use i_slint_core::platform::PlatformError;
use i_slint_core::renderer::DrawOutcome;
use i_slint_renderer_skia::skia_safe::gpu::{self, mtl};
use i_slint_renderer_skia::skia_safe::{Canvas, ColorType};
use i_slint_renderer_skia::{SkiaSharedContext, Surface};

use super::shared_texture;

/// Nothing to hold: Skia retains the texture, the plugin keeps its backing.
pub struct Attachment;

pub struct TextureSurface {
    context: RefCell<gpu::DirectContext>,
    texture: mtl::TextureInfo,
    size: PhysicalSize,
}

impl TextureSurface {
    /// # Safety
    ///
    /// `device`, `queue` and `texture` are live `id<MTLDevice>`,
    /// `id<MTLCommandQueue>` and `id<MTLTexture>`; the texture is
    /// BGRA8Unorm, `size`, made on `device` with render-target usage. Skia
    /// takes its own reference to each.
    pub unsafe fn wrap(
        device: *mut c_void,
        queue: *mut c_void,
        texture: *mut c_void,
        size: PhysicalSize,
    ) -> Result<Self, String> {
        let backend =
            unsafe { mtl::BackendContext::new(device as mtl::Handle, queue as mtl::Handle) };
        let context = gpu::direct_contexts::make_metal(&backend, None)
            .ok_or("Skia could not create a Metal context")?;
        let texture = unsafe { mtl::TextureInfo::new(texture as mtl::Handle) };
        Ok(Self {
            context: RefCell::new(context),
            texture,
            size,
        })
    }

    fn target(&self) -> gpu::BackendRenderTarget {
        gpu::backend_render_targets::make_mtl(
            (self.size.width as i32, self.size.height as i32),
            &self.texture,
        )
    }
}

impl Surface for TextureSurface {
    fn new(
        _: &SkiaSharedContext,
        _: Arc<dyn raw_window_handle::HasWindowHandle + Sync + Send>,
        _: Arc<dyn raw_window_handle::HasDisplayHandle + Sync + Send>,
        _: PhysicalSize,
        _: Option<RequestedGraphicsAPI>,
    ) -> Result<Self, PlatformError> {
        Err("the Metal texture surface wraps the plugin's texture, not a window".into())
    }

    fn name(&self) -> &'static str {
        "metal-texture"
    }

    fn render(
        &self,
        _window: &Window,
        _size: PhysicalSize,
        render_callback: &dyn Fn(
            &Canvas,
            Option<&mut gpu::DirectContext>,
            u8,
        ) -> Option<DirtyRegion>,
        pre_present_callback: &RefCell<Option<Box<dyn FnMut()>>>,
    ) -> Result<DrawOutcome, PlatformError> {
        // Metal hands out autoreleased objects; don't rely on the caller's pool.
        let _pool = AutoreleasePool::push();
        shared_texture::render(
            &self.context,
            &self.target(),
            ColorType::BGRA8888,
            render_callback,
            pre_present_callback,
        )
    }

    fn resize_event(&self, _size: PhysicalSize) -> Result<(), PlatformError> {
        // A new size is a new texture: the plugin reallocates and attaches again.
        Ok(())
    }

    fn bits_per_pixel(&self) -> Result<u8, PlatformError> {
        Ok(32)
    }
}

#[link(name = "objc")]
extern "C" {
    fn objc_autoreleasePoolPush() -> *mut c_void;
    fn objc_autoreleasePoolPop(pool: *mut c_void);
}

struct AutoreleasePool(*mut c_void);

impl AutoreleasePool {
    fn push() -> Self {
        Self(unsafe { objc_autoreleasePoolPush() })
    }
}

impl Drop for AutoreleasePool {
    fn drop(&mut self) {
        unsafe { objc_autoreleasePoolPop(self.0) }
    }
}

/// Metal objects made the way the Swift plugin makes them (minus the
/// `CVPixelBuffer`), through the Objective-C runtime, and a read-back.
#[cfg(test)]
pub mod test_support {
    use std::ffi::{c_char, c_void, CStr};
    use std::mem::transmute;

    use i_slint_core::api::PhysicalSize;
    use i_slint_renderer_skia::skia_safe::ColorType;

    use super::{AutoreleasePool, TextureSurface};

    #[link(name = "Metal", kind = "framework")]
    extern "C" {
        fn MTLCreateSystemDefaultDevice() -> *mut c_void;
    }

    #[link(name = "objc")]
    extern "C" {
        fn sel_registerName(name: *const c_char) -> *mut c_void;
        fn objc_getClass(name: *const c_char) -> *mut c_void;
        fn objc_msgSend();
        fn objc_release(object: *mut c_void);
    }

    type Id = *mut c_void;
    type MsgSend = unsafe extern "C" fn();

    pub struct MetalObjects {
        pub device: Id,
        pub queue: Id,
        pub texture: Id,
    }

    impl Drop for MetalObjects {
        fn drop(&mut self) {
            unsafe {
                objc_release(self.texture);
                objc_release(self.queue);
                objc_release(self.device);
            }
        }
    }

    fn sel(name: &CStr) -> Id {
        unsafe { sel_registerName(name.as_ptr()) }
    }

    /// A device, a queue and a BGRA8Unorm render-target texture; `None`
    /// when the machine has no Metal device.
    pub fn metal_objects(width: u32, height: u32) -> Option<MetalObjects> {
        const BGRA8_UNORM: usize = 80;
        const SHADER_READ_AND_RENDER_TARGET: usize = 0x1 | 0x4;
        let _pool = AutoreleasePool::push();
        unsafe {
            let device = MTLCreateSystemDefaultDevice();
            if device.is_null() {
                return None;
            }
            let send = objc_msgSend as MsgSend;
            let new_object = transmute::<MsgSend, unsafe extern "C" fn(Id, Id) -> Id>(send);
            let descriptor_for = transmute::<
                MsgSend,
                unsafe extern "C" fn(Id, Id, usize, usize, usize, bool) -> Id,
            >(send);
            let set_usage = transmute::<MsgSend, unsafe extern "C" fn(Id, Id, usize)>(send);
            let new_texture = transmute::<MsgSend, unsafe extern "C" fn(Id, Id, Id) -> Id>(send);

            let queue = new_object(device, sel(c"newCommandQueue"));
            let descriptor = descriptor_for(
                objc_getClass(c"MTLTextureDescriptor".as_ptr()),
                sel(c"texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
                BGRA8_UNORM,
                width as usize,
                height as usize,
                false,
            );
            set_usage(descriptor, sel(c"setUsage:"), SHADER_READ_AND_RENDER_TARGET);
            let texture = new_texture(device, sel(c"newTextureWithDescriptor:"), descriptor);
            Some(MetalObjects {
                device,
                queue,
                texture,
            })
        }
    }

    /// The texture's pixels as RGBA8888 premultiplied, through a second
    /// Skia context.
    pub fn read_rgba(objects: &MetalObjects, width: u32, height: u32) -> Vec<u8> {
        let _pool = AutoreleasePool::push();
        let surface = unsafe {
            TextureSurface::wrap(
                objects.device,
                objects.queue,
                objects.texture,
                PhysicalSize::new(width, height),
            )
        }
        .expect("wrap the texture for read-back");
        super::shared_texture::read_rgba(
            &surface.context,
            &surface.target(),
            ColorType::BGRA8888,
            width,
            height,
        )
    }
}
