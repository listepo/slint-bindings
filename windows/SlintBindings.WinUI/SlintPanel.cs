// WinUI 3 control presenting a SlintHost.
// M1 (this file): CPU frames copied into a WriteableBitmap shown by an Image.
// M3: replace the Image with a SwapChainPanel and let Rust render on the GPU into
// a DXGI swap chain (wgpu's SurfaceTargetUnsafe::SwapChainPanel or Skia on D3D12).
// SetSwapChain must be called on this control's UI thread.

using System;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;

namespace SlintBindings.WinUI;

public sealed class SlintPanel : UserControl
{
    private readonly Image _image = new() { Stretch = Stretch.Fill };
    private WriteableBitmap? _bitmap;

    public SlintHost? Host { get; private set; }

    public SlintPanel()
    {
        Content = _image;
        IsTabStop = true;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        SizeChanged += (_, _) => SyncSize();
        PointerMoved += (_, e) => Forward(e, (x, y, _) => Host?.PointerMoved(x, y));
        PointerPressed += (_, e) => { Focus(FocusState.Pointer); Forward(e, (x, y, b) => Host?.PointerPressed(x, y, b)); };
        PointerReleased += (_, e) => Forward(e, (x, y, b) => Host?.PointerReleased(x, y, b));
        PointerExited += (_, _) => Host?.PointerExited();
        PointerWheelChanged += (_, e) =>
        {
            var p = e.GetCurrentPoint(this);
            Host?.PointerScrolled((float)p.Position.X, (float)p.Position.Y, 0, p.Properties.MouseWheelDelta);
        };
        GotFocus += (_, _) => Host?.FocusChanged(true);
        LostFocus += (_, _) => Host?.FocusChanged(false);
        // TODO(M2): map VirtualKey to Slint key text (arrows U+F700…, Backspace U+0008) and
        // route CharacterReceived for typed text; IME needs CoreTextEditContext.
        CharacterReceived += (_, e) => Host?.KeyPressed(e.Character.ToString());
    }

    private float Scale => (float)(XamlRoot?.RasterizationScale ?? 1.0);

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Host ??= new SlintHost(1, 1, Scale);
        SyncSize();
        // Fires once per composition frame on the UI thread: tick timers, then render if dirty.
        CompositionTarget.Rendering += OnRendering;
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        CompositionTarget.Rendering -= OnRendering;
        Host?.Dispose();
        Host = null;
    }

    private void SyncSize()
    {
        if (Host is null) return;
        var w = Math.Max(1, (int)Math.Round(ActualWidth * Scale));
        var h = Math.Max(1, (int)Math.Round(ActualHeight * Scale));
        Host.Resize(w, h, Scale);
        _bitmap = new WriteableBitmap(w, h);
        _image.Source = _bitmap;
    }

    private void OnRendering(object? sender, object e)
    {
        SlintHost.Tick();
        if (Host is null || _bitmap is null) return;
        using var stream = _bitmap.PixelBuffer.AsStream();
        var bgra = new byte[_bitmap.PixelWidth * _bitmap.PixelHeight * 4];
        if (Host.RenderBgra(bgra, out _))
        {
            stream.Write(bgra, 0, bgra.Length);
            _bitmap.Invalidate();
        }
    }

    // Positions arrive in DIPs (logical pixels) relative to this control, which is what Slint expects.
    private void Forward(PointerRoutedEventArgs e, Action<float, float, int> send)
    {
        var p = e.GetCurrentPoint(this);
        var button = p.Properties.PointerUpdateKind switch
        {
            PointerUpdateKind.RightButtonPressed or PointerUpdateKind.RightButtonReleased => 1,
            PointerUpdateKind.MiddleButtonPressed or PointerUpdateKind.MiddleButtonReleased => 2,
            _ => 0,
        };
        send((float)p.Position.X, (float)p.Position.Y, button);
        e.Handled = true;
    }
}
