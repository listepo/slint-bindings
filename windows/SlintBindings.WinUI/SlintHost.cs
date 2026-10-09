// C# owner of one embedded Slint component. UI-thread only, like the Swift SlintHost.

using System;
using System.Runtime.InteropServices;

namespace SlintBindings.WinUI;

public sealed class SlintException(string message) : Exception(message);

public sealed class SlintHost : IDisposable
{
    private IntPtr _handle;
    private byte[] _rgba = [];
    private SbSubmittedFn? _submittedThunk; // keeps the delegate alive while Rust holds its pointer
    private GCHandle _self;

    public int PixelWidth { get; private set; } = 1;
    public int PixelHeight { get; private set; } = 1;

    public event Action<string>? Submitted;

    public SlintHost(int pixelWidth, int pixelHeight, float scale)
    {
        _handle = NativeMethods.sb_demo_new((uint)Math.Max(pixelWidth, 1), (uint)Math.Max(pixelHeight, 1), scale);
        if (_handle == IntPtr.Zero) throw new SlintException(NativeMethods.LastError());
        PixelWidth = Math.Max(pixelWidth, 1);
        PixelHeight = Math.Max(pixelHeight, 1);
        _self = GCHandle.Alloc(this, GCHandleType.Weak);
        _submittedThunk = OnSubmittedNative;
        NativeMethods.sb_demo_on_submitted(_handle, Marshal.GetFunctionPointerForDelegate(_submittedThunk), GCHandle.ToIntPtr(_self));
    }

    private static void OnSubmittedNative(IntPtr userData, IntPtr name)
    {
        if (GCHandle.FromIntPtr(userData).Target is SlintHost host)
            host.Submitted?.Invoke(Marshal.PtrToStringUTF8(name) ?? "");
    }

    public static void Tick() => NativeMethods.sb_tick();

    public void Resize(int pixelWidth, int pixelHeight, float scale)
    {
        var width = Math.Max(pixelWidth, 1);
        var height = Math.Max(pixelHeight, 1);
        if (!NativeMethods.sb_host_resize(_handle, (uint)width, (uint)height, scale))
            throw new SlintException(NativeMethods.LastError());
        // Only publish the size after the core accepts it, so a failed call leaves the previous frame.
        PixelWidth = width;
        PixelHeight = height;
    }

    /// <summary>Renders if the scene changed and writes premultiplied BGRA8 into <paramref name="bgra"/>.</summary>
    /// <returns>True when <paramref name="bgra"/> was written.</returns>
    public unsafe bool RenderBgra(Span<byte> bgra, out bool animating)
    {
        var len = (int)NativeMethods.sb_host_frame_len(_handle);
        if (_rgba.Length != len) _rgba = new byte[len];
        SbFrame frame;
        fixed (byte* p = _rgba) frame = NativeMethods.sb_host_render(_handle, p, (nuint)len);
        if (frame.Failed != 0) throw new SlintException(NativeMethods.LastError());
        animating = frame.Animating != 0;
        if (frame.Redrawn == 0) return false;
        if (bgra.Length < len)
            throw new SlintException("BGRA buffer is shorter than the frame");
        // TODO(M2): let the core render BGRA directly (WriteableBitmap and DXGI both want it) and drop this swizzle.
        for (var i = 0; i + 3 < len; i += 4)
        {
            bgra[i] = _rgba[i + 2];
            bgra[i + 1] = _rgba[i + 1];
            bgra[i + 2] = _rgba[i];
            bgra[i + 3] = _rgba[i + 3];
        }
        return true;
    }

    public void PointerMoved(float x, float y) => NativeMethods.sb_host_pointer_moved(_handle, x, y);
    public void PointerPressed(float x, float y, int button)
    {
        if (button is < 0 or > 2) throw new SlintException("pointer button must be 0, 1 or 2");
        NativeMethods.sb_host_pointer_pressed(_handle, x, y, (byte)button);
    }
    public void PointerReleased(float x, float y, int button)
    {
        if (button is < 0 or > 2) throw new SlintException("pointer button must be 0, 1 or 2");
        NativeMethods.sb_host_pointer_released(_handle, x, y, (byte)button);
    }
    public void PointerExited() => NativeMethods.sb_host_pointer_exited(_handle);
    public void PointerScrolled(float x, float y, float dx, float dy) => NativeMethods.sb_host_pointer_scrolled(_handle, x, y, dx, dy);
    public void KeyPressed(string text) => NativeMethods.sb_host_key_pressed(_handle, text);
    public void KeyReleased(string text) => NativeMethods.sb_host_key_released(_handle, text);
    public void KeyRepeated(string text) => NativeMethods.sb_host_key_repeated(_handle, text);
    public void FocusChanged(bool focused) => NativeMethods.sb_host_focus_changed(_handle, focused);
    public void SetName(string name) => NativeMethods.sb_demo_set_name(_handle, name);

    public void Dispose()
    {
        if (_handle == IntPtr.Zero) return;
        NativeMethods.sb_demo_on_submitted(_handle, IntPtr.Zero, IntPtr.Zero);
        NativeMethods.sb_host_free(_handle);
        _handle = IntPtr.Zero;
        if (_self.IsAllocated) _self.Free();
        _submittedThunk = null;
    }
}
