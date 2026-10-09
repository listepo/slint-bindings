// IME for SlintPanel. CoreTextEditContext is the WinUI text service
// (Windows.UI.Text.Core). GetForCurrentView needs a CoreWindow, which desktop
// WinUI does not have on Windows 10; when it throws, CharacterReceived still
// delivers committed text and this class stays inactive.
//
// The edit context's text store is only the preedit. Slint owns the committed
// string, and a custom platform cannot read it back. Composition updates go
// through sb_host_ime_*; a plain character still arrives as CharacterReceived
// so an English key is not inserted twice when TextUpdating also fires.

using System;
using System.Runtime.InteropServices;
using Microsoft.UI;
using Windows.Foundation;
using Windows.UI.Text.Core;

namespace SlintBindings.WinUI;

internal sealed class SlintTextInput
{
    private readonly Func<SlintHost?> _host;
    private readonly Func<Rect> _caretRect;
    private CoreTextEditContext? _edit;
    private bool _focused;
    private bool _suppressCharacter;

    public SlintTextInput(Func<SlintHost?> host, Func<Rect> caretRect)
    {
        _host = host;
        _caretRect = caretRect;
    }

    /// <summary>The edit context exists and has been told it has focus.</summary>
    public bool Active => _edit is not null && _focused;

    public bool IsComposing => _host()?.ImeComposing() ?? false;

    public void Attach()
    {
        if (_edit is not null) return;
        try
        {
            var manager = CoreTextServicesManager.GetForCurrentView();
            _edit = manager.CreateEditContext();
        }
        catch (Exception)
        {
            // Desktop WinUI on Windows 10 has no CoreWindow. Typing still works
            // through CharacterReceived; composition does not.
            _edit = null;
            return;
        }

        _edit.InputPaneDisplayPolicy = CoreTextInputPaneDisplayPolicy.Automatic;
        _edit.InputScope = CoreTextInputScope.Text;
        _edit.TextRequested += OnTextRequested;
        _edit.SelectionRequested += OnSelectionRequested;
        _edit.TextUpdating += OnTextUpdating;
        _edit.SelectionUpdating += OnSelectionUpdating;
        _edit.CompositionStarted += OnCompositionStarted;
        _edit.CompositionCompleted += OnCompositionCompleted;
        _edit.LayoutRequested += OnLayoutRequested;
        _edit.FocusRemoved += OnFocusRemoved;
    }

    public void Detach()
    {
        FocusLeave();
        if (_edit is null) return;
        _edit.TextRequested -= OnTextRequested;
        _edit.SelectionRequested -= OnSelectionRequested;
        _edit.TextUpdating -= OnTextUpdating;
        _edit.SelectionUpdating -= OnSelectionUpdating;
        _edit.CompositionStarted -= OnCompositionStarted;
        _edit.CompositionCompleted -= OnCompositionCompleted;
        _edit.LayoutRequested -= OnLayoutRequested;
        _edit.FocusRemoved -= OnFocusRemoved;
        _edit = null;
    }

    public void FocusEnter()
    {
        if (_edit is null || _focused) return;
        try
        {
            _edit.NotifyFocusEnter();
            _focused = true;
        }
        catch (Exception)
        {
            _focused = false;
        }
    }

    public void FocusLeave()
    {
        _host()?.ImeCompleted(false);
        _suppressCharacter = false;
        if (_edit is null || !_focused) return;
        _focused = false;
        try
        {
            _edit.NotifyFocusLeave();
        }
        catch (Exception)
        {
            // The context is already gone. Focus in Slint was cleared by the caller.
        }
    }

    /// <summary>A new key is starting, so a suppress flag from the previous key is stale.</summary>
    public void NoteKeyDown() => _suppressCharacter = false;

    /// <summary>True when CharacterReceived must not also insert the scalar.</summary>
    public bool ConsumeCharacter()
    {
        if (IsComposing || _suppressCharacter)
        {
            _suppressCharacter = false;
            return true;
        }
        return false;
    }

    private void OnTextRequested(CoreTextEditContext sender, CoreTextTextRequestedEventArgs args)
    {
        var request = args.Request;
        if (request is null) return;
        var text = _host()?.ImeText() ?? "";
        var start = Math.Clamp(request.Range.StartCaretPosition, 0, text.Length);
        var end = Math.Clamp(request.Range.EndCaretPosition, start, text.Length);
        request.Text = text.Substring(start, end - start);
    }

    private void OnSelectionRequested(CoreTextEditContext sender, CoreTextSelectionRequestedEventArgs args)
    {
        var request = args.Request;
        if (request is null) return;
        var (start, end) = _host()?.ImeSelection() ?? (0, 0);
        request.Selection = new CoreTextRange
        {
            StartCaretPosition = start,
            EndCaretPosition = end,
        };
    }

    private void OnTextUpdating(CoreTextEditContext sender, CoreTextTextUpdatingEventArgs args)
    {
        args.Result = CoreTextTextUpdatingResult.Succeeded;
        var host = _host();
        if (host is null)
        {
            args.Result = CoreTextTextUpdatingResult.Failed;
            return;
        }
        var text = args.Text ?? "";
        var composing = host.ImeComposing();
        // One BMP scalar with no composition is also delivered as CharacterReceived.
        if (!composing && text.Length <= 1) return;
        var range = args.Range;
        var selection = args.NewSelection;
        if (!host.ImeReplace(
                range.StartCaretPosition,
                range.EndCaretPosition,
                text,
                selection.StartCaretPosition,
                selection.EndCaretPosition))
        {
            args.Result = CoreTextTextUpdatingResult.Failed;
            return;
        }
        if (!composing) _suppressCharacter = true;
    }

    private void OnSelectionUpdating(CoreTextEditContext sender, CoreTextSelectionUpdatingEventArgs args)
    {
        var range = args.Selection;
        _host()?.ImeSelect(range.StartCaretPosition, range.EndCaretPosition);
    }

    private void OnCompositionStarted(CoreTextEditContext sender, CoreTextCompositionStartedEventArgs args) =>
        _host()?.ImeStarted();

    private void OnCompositionCompleted(CoreTextEditContext sender, CoreTextCompositionCompletedEventArgs args)
    {
        _host()?.ImeCompleted(args.IsCanceled);
        _suppressCharacter = true;
    }

    private void OnLayoutRequested(CoreTextEditContext sender, CoreTextLayoutRequestedEventArgs args)
    {
        var request = args.Request;
        if (request is null) return;
        var caret = _caretRect();
        request.LayoutBounds.TextBounds = caret;
        request.LayoutBounds.ControlBounds = caret;
    }

    private void OnFocusRemoved(CoreTextEditContext sender, object args)
    {
        _focused = false;
        _host()?.ImeCompleted(false);
    }

    /// <summary>
    /// Screen rectangle of a caret-sized box inside the panel, in physical pixels.
    /// Slint 1.18 does not report the caret, so the candidate window anchors to
    /// the demo field's place, matching the macOS host.
    /// </summary>
    public static Rect ScreenCaret(SlintPanel panel)
    {
        var scale = panel.XamlRoot?.RasterizationScale ?? 1.0;
        var local = panel.TransformToVisual(null).TransformPoint(new Point(16, 48));
        var x = local.X * scale;
        var y = local.Y * scale;
        var hwnd = WindowHandle(panel);
        if (hwnd != 0)
        {
            var point = new NativeWindow.POINT { X = (int)Math.Round(x), Y = (int)Math.Round(y) };
            unsafe
            {
                if (NativeWindow.ClientToScreen(hwnd, &point))
                {
                    x = point.X;
                    y = point.Y;
                }
            }
        }
        return new Rect(x, y, 2 * scale, 24 * scale);
    }

    private static nint WindowHandle(SlintPanel panel)
    {
        var root = panel.XamlRoot;
        if (root is null) return 0;
        try
        {
            return Win32Interop.GetWindowFromWindowId(root.ContentIslandEnvironment.AppWindowId);
        }
        catch (Exception)
        {
            return 0;
        }
    }

    private static partial class NativeWindow
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct POINT
        {
            public int X;
            public int Y;
        }

        [LibraryImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static unsafe partial bool ClientToScreen(IntPtr hwnd, POINT* point);
    }
}
