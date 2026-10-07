//! Windows: Skia renders through D3D12 into a shared BGRA8 texture on
//! Flutter's adapter; the C++ plugin hands the texture's NT handle to a
//! `flutter::GpuSurfaceTexture`.

use std::cell::RefCell;
use std::ffi::c_void;
use std::sync::Arc;

use i_slint_core::api::{PhysicalSize, Window};
use i_slint_core::graphics::RequestedGraphicsAPI;
use i_slint_core::partial_renderer::DirtyRegion;
use i_slint_core::platform::PlatformError;
use i_slint_core::renderer::DrawOutcome;
use i_slint_renderer_skia::skia_safe::gpu::{self, d3d};
use i_slint_renderer_skia::skia_safe::{Canvas, ColorType};
use i_slint_renderer_skia::{SkiaSharedContext, Surface};
use windows::core::PCWSTR;
use windows::Win32::Foundation::{CloseHandle, GENERIC_ALL, HANDLE, LUID};
use windows::Win32::Graphics::Direct3D::D3D_FEATURE_LEVEL_11_0;
use windows::Win32::Graphics::Direct3D12::{
    D3D12CreateDevice, ID3D12CommandQueue, ID3D12Device, ID3D12Resource,
    D3D12_COMMAND_LIST_TYPE_DIRECT, D3D12_COMMAND_QUEUE_DESC, D3D12_HEAP_FLAG_SHARED,
    D3D12_HEAP_PROPERTIES, D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_DESC,
    D3D12_RESOURCE_DIMENSION_TEXTURE2D, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET,
    D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS, D3D12_RESOURCE_STATE_COMMON,
};
use windows::Win32::Graphics::Dxgi::Common::{
    DXGI_FORMAT_B8G8R8A8_UNORM, DXGI_SAMPLE_DESC, DXGI_STANDARD_MULTISAMPLE_QUALITY_PATTERN,
};
use windows::Win32::Graphics::Dxgi::{
    CreateDXGIFactory2, IDXGIAdapter1, IDXGIFactory4, DXGI_CREATE_FACTORY_FLAGS,
};

use super::shared_texture;

/// The NT handle of the texture the surface renders into; closed on drop.
/// The surface keeps the texture itself alive.
pub struct Attachment {
    handle: HANDLE,
}

impl Attachment {
    pub fn shared_handle(&self) -> *mut c_void {
        self.handle.0
    }
}

impl Drop for Attachment {
    fn drop(&mut self) {
        let _ = unsafe { CloseHandle(self.handle) };
    }
}

pub struct TextureSurface {
    // Dropped first: Skia's context before the D3D objects it was made from.
    context: RefCell<gpu::DirectContext>,
    target: gpu::BackendRenderTarget,
    _backend: d3d::BackendContext,
}

/// A device and a direct queue on the adapter with this LUID (0/0: the
/// first adapter, WARP on a machine without a GPU).
fn device(
    luid_low: u32,
    luid_high: i32,
) -> Result<(IDXGIAdapter1, ID3D12Device, ID3D12CommandQueue), String> {
    let factory: IDXGIFactory4 = unsafe { CreateDXGIFactory2(DXGI_CREATE_FACTORY_FLAGS(0)) }
        .map_err(|e| format!("CreateDXGIFactory2 failed: {e}"))?;
    let adapter: IDXGIAdapter1 = if luid_low == 0 && luid_high == 0 {
        unsafe { factory.EnumAdapters1(0) }
    } else {
        unsafe {
            factory.EnumAdapterByLuid(LUID {
                LowPart: luid_low,
                HighPart: luid_high,
            })
        }
    }
    .map_err(|e| format!("no DXGI adapter with LUID {luid_high:#x}:{luid_low:#x}: {e}"))?;
    let mut device: Option<ID3D12Device> = None;
    unsafe { D3D12CreateDevice(&adapter, D3D_FEATURE_LEVEL_11_0, &mut device) }
        .map_err(|e| format!("D3D12CreateDevice failed: {e}"))?;
    let device = device.ok_or("D3D12CreateDevice returned no device")?;
    let queue: ID3D12CommandQueue = unsafe {
        device.CreateCommandQueue(&D3D12_COMMAND_QUEUE_DESC {
            Type: D3D12_COMMAND_LIST_TYPE_DIRECT,
            ..Default::default()
        })
    }
    .map_err(|e| format!("CreateCommandQueue failed: {e}"))?;
    Ok((adapter, device, queue))
}

/// A BGRA8 render-target texture other devices (Flutter's ANGLE) can open
/// through an NT handle, without a keyed mutex.
fn new_shared_texture(device: &ID3D12Device, size: PhysicalSize) -> Result<ID3D12Resource, String> {
    let heap = D3D12_HEAP_PROPERTIES {
        Type: D3D12_HEAP_TYPE_DEFAULT,
        ..Default::default()
    };
    let desc = D3D12_RESOURCE_DESC {
        Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
        Width: u64::from(size.width),
        Height: size.height,
        DepthOrArraySize: 1,
        MipLevels: 1,
        Format: DXGI_FORMAT_B8G8R8A8_UNORM,
        SampleDesc: DXGI_SAMPLE_DESC {
            Count: 1,
            Quality: 0,
        },
        Flags: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET
            | D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS,
        ..Default::default()
    };
    let mut resource: Option<ID3D12Resource> = None;
    unsafe {
        device.CreateCommittedResource(
            &heap,
            D3D12_HEAP_FLAG_SHARED,
            &desc,
            D3D12_RESOURCE_STATE_COMMON,
            None,
            &mut resource,
        )
    }
    .map_err(|e| format!("CreateCommittedResource failed: {e}"))?;
    resource.ok_or_else(|| "CreateCommittedResource returned no texture".into())
}

/// Creates the shared texture on Flutter's adapter and a surface rendering
/// into it.
pub fn create(
    luid_low: u32,
    luid_high: i32,
    size: PhysicalSize,
) -> Result<(TextureSurface, Attachment), String> {
    let (adapter, device, queue) = device(luid_low, luid_high)?;
    let resource = new_shared_texture(&device, size)?;
    let handle =
        unsafe { device.CreateSharedHandle(&resource, None, GENERIC_ALL.0, PCWSTR::null()) }
            .map_err(|e| format!("CreateSharedHandle failed: {e}"))?;
    // Owned from here, so an error below closes it.
    let attachment = Attachment { handle };
    let surface = TextureSurface::wrap(adapter, device, queue, resource, size)?;
    Ok((surface, attachment))
}

impl TextureSurface {
    fn wrap(
        adapter: IDXGIAdapter1,
        device: ID3D12Device,
        queue: ID3D12CommandQueue,
        resource: ID3D12Resource,
        size: PhysicalSize,
    ) -> Result<Self, String> {
        let backend = d3d::BackendContext {
            adapter,
            device,
            queue,
            memory_allocator: None,
            protected_context: gpu::Protected::No,
        };
        // SAFETY: `backend` outlives the context (field order above).
        let context = unsafe { gpu::direct_contexts::make_d3d(&backend, None) }
            .ok_or("Skia could not create a D3D12 context")?;
        let info = d3d::TextureResourceInfo {
            resource,
            alloc: None,
            resource_state: D3D12_RESOURCE_STATE_COMMON,
            format: DXGI_FORMAT_B8G8R8A8_UNORM,
            sample_count: 1,
            level_count: 1,
            sample_quality_pattern: DXGI_STANDARD_MULTISAMPLE_QUALITY_PATTERN,
            protected: gpu::Protected::No,
        };
        let target =
            gpu::backend_render_targets::make_d3d((size.width as i32, size.height as i32), &info);
        Ok(Self {
            context: RefCell::new(context),
            target,
            _backend: backend,
        })
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
        Err("the D3D12 texture surface renders into a shared texture, not a window".into())
    }

    fn name(&self) -> &'static str {
        "d3d12-texture"
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
        shared_texture::render(
            &self.context,
            &self.target,
            ColorType::BGRA8888,
            render_callback,
            pre_present_callback,
        )
    }

    fn resize_event(&self, _size: PhysicalSize) -> Result<(), PlatformError> {
        // A new size is a new texture: the plugin attaches again.
        Ok(())
    }

    fn bits_per_pixel(&self) -> Result<u8, PlatformError> {
        Ok(32)
    }
}

#[cfg(test)]
pub mod test_support {
    use i_slint_core::api::PhysicalSize;
    use i_slint_renderer_skia::skia_safe::ColorType;
    use windows::Win32::Graphics::Direct3D12::ID3D12Resource;

    use super::{device, shared_texture, Attachment, TextureSurface};

    /// Opens the NT handle the way the plugin's consumer does, on a device
    /// of its own, and reads the texture back through a second Skia
    /// context as RGBA8888 premultiplied.
    pub fn read_rgba(attachment: &Attachment, width: u32, height: u32) -> Vec<u8> {
        let (adapter, device, queue) = device(0, 0).expect("a D3D12 device");
        let mut resource: Option<ID3D12Resource> = None;
        unsafe { device.OpenSharedHandle(attachment.handle, &mut resource) }
            .expect("open the shared handle");
        let surface = TextureSurface::wrap(
            adapter,
            device,
            queue,
            resource.expect("a shared texture"),
            PhysicalSize::new(width, height),
        )
        .expect("wrap the texture for read-back");
        shared_texture::read_rgba(
            &surface.context,
            &surface.target,
            ColorType::BGRA8888,
            width,
            height,
        )
    }
}
