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
    /// <summary>WinUI wheel units are multiples of 120; Slint wants logical points.</summary>
    private const float WheelDeltaToPoints = 40f / 120f;

    private readonly Image _image = new() { Stretch = Stretch.Fill };
    private WriteableBitmap? _bitmap;
    private byte[] _bgra = [];
    private XamlRoot? _xamlRoot;

    public SlintHost? Host { get; private set; }
    public string? LastError { get; private set; }

    public SlintPanel()
    {
        Content = _image;
        IsTabStop = true;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        SizeChanged += (_, _) => SyncSize();
        PointerMoved += (_, e) => Forward(e, (x, y, _) => Host?.PointerMoved(x, y));
        PointerPressed += (_, e) =>
        {
            Focus(FocusState.Pointer);
            CapturePointer(e.Pointer);
            Forward(e, (x, y, b) => Host?.PointerPressed(x, y, b));
        };
        PointerReleased += (_, e) =>
        {
            Forward(e, (x, y, b) => Host?.PointerReleased(x, y, b));
            ReleasePointerCapture(e.Pointer);
        };
        PointerCanceled += (_, e) =>
        {
            Host?.PointerExited();
            ReleasePointerCapture(e.Pointer);
        };
        PointerExited += (_, _) => Host?.PointerExited();
        PointerWheelChanged += OnWheel;
        GotFocus += (_, _) => Host?.FocusChanged(true);
        LostFocus += (_, _) => Host?.FocusChanged(false);
        PreviewKeyDown += OnPreviewKeyDown;
        KeyUp += OnKeyUp;
        CharacterReceived += OnCharacterReceived;
    }

    private float Scale => (float)(XamlRoot?.RasterizationScale ?? 1.0);

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            Host ??= new SlintHost(1, 1, Scale);
        }
        catch (SlintException ex)
        {
            LastError = ex.Message;
            return;
        }
        _xamlRoot = XamlRoot;
        if (_xamlRoot is not null)
            _xamlRoot.Changed += OnXamlRootChanged;
        SyncSize();
        CompositionTarget.Rendering += OnRendering;
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        if (_xamlRoot is not null)
            _xamlRoot.Changed -= OnXamlRootChanged;
        _xamlRoot = null;
        CompositionTarget.Rendering -= OnRendering;
        Host?.Dispose();
        Host = null;
    }

    private void OnXamlRootChanged(XamlRoot sender, XamlRootChangedEventArgs args) => SyncSize();

    private void SyncSize()
    {
        if (Host is null) return;
        var w = Math.Max(1, (int)Math.Round(ActualWidth * Scale));
        var h = Math.Max(1, (int)Math.Round(ActualHeight * Scale));
        try
        {
            Host.Resize(w, h, Scale);
            if (_bitmap is null || _bitmap.PixelWidth != w || _bitmap.PixelHeight != h)
            {
                _bitmap = new WriteableBitmap(w, h);
                _image.Source = _bitmap;
            }
            RenderFrame();
        }
        catch (SlintException ex)
        {
            LastError = ex.Message;
        }
    }

    private void OnRendering(object? sender, object e)
    {
        SlintHost.Tick();
        RenderFrame();
    }

    private void RenderFrame()
    {
        if (Host is null || _bitmap is null) return;
        try
        {
            using var stream = _bitmap.PixelBuffer.AsStream();
            var needed = _bitmap.PixelWidth * _bitmap.PixelHeight * 4;
            if (_bgra.Length != needed) _bgra = new byte[needed];
            if (Host.RenderBgra(_bgra, out _))
            {
                stream.Write(_bgra, 0, _bgra.Length);
                _bitmap.Invalidate();
            }
        }
        catch (SlintException ex)
        {
            LastError = ex.Message;
        }
    }

    private void OnWheel(object sender, PointerRoutedEventArgs e)
    {
        var p = e.GetCurrentPoint(this);
        var delta = p.Properties.MouseWheelDelta * WheelDeltaToPoints;
        var dx = p.Properties.IsHorizontalMouseWheel ? delta : 0;
        var dy = p.Properties.IsHorizontalMouseWheel ? 0 : delta;
        Host?.PointerScrolled((float)p.Position.X, (float)p.Position.Y, dx, dy);
        e.Handled = true;
    }

    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var text = SlintKeys.Special(e.Key);
        if (text is null) return;
        if (e.KeyStatus.WasKeyDown) Host?.KeyRepeated(text);
        else Host?.KeyPressed(text);
        e.Handled = true;
    }

    private void OnKeyUp(object sender, KeyRoutedEventArgs e)
    {
        var text = SlintKeys.Special(e.Key);
        if (text is null) return;
        Host?.KeyReleased(text);
        e.Handled = true;
    }

    private void OnCharacterReceived(object sender, CharacterReceivedRoutedEventArgs e)
    {
        if (char.IsControl(e.Character) && e.Character is not ' ') return;
        var text = e.Character.ToString();
        Host?.KeyPressed(text);
        Host?.KeyReleased(text);
        e.Handled = true;
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
