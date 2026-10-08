// VirtualKey → Slint key text (i-slint-common key_codes). Printable characters
// arrive through CharacterReceived instead.

using Windows.System;

namespace SlintBindings.WinUI;

internal static class SlintKeys
{
    public static string? Special(VirtualKey key) => key switch
    {
        VirtualKey.Back => "\u0008",
        VirtualKey.Tab => "\t",
        VirtualKey.Enter => "\n",
        VirtualKey.Escape => "\u001b",
        VirtualKey.Delete => "\u007f",
        VirtualKey.Up => "\uF700",
        VirtualKey.Down => "\uF701",
        VirtualKey.Left => "\uF702",
        VirtualKey.Right => "\uF703",
        VirtualKey.Insert => "\uF727",
        VirtualKey.Home => "\uF729",
        VirtualKey.End => "\uF72B",
        VirtualKey.PageUp => "\uF72C",
        VirtualKey.PageDown => "\uF72D",
        VirtualKey.F1 => "\uF704",
        VirtualKey.F2 => "\uF705",
        VirtualKey.F3 => "\uF706",
        VirtualKey.F4 => "\uF707",
        VirtualKey.F5 => "\uF708",
        VirtualKey.F6 => "\uF709",
        VirtualKey.F7 => "\uF70A",
        VirtualKey.F8 => "\uF70B",
        VirtualKey.F9 => "\uF70C",
        VirtualKey.F10 => "\uF70D",
        VirtualKey.F11 => "\uF70E",
        VirtualKey.F12 => "\uF70F",
        VirtualKey.Shift or VirtualKey.LeftShift or VirtualKey.RightShift => "\u0010",
        VirtualKey.Control or VirtualKey.LeftControl or VirtualKey.RightControl => "\u0011",
        VirtualKey.Menu or VirtualKey.LeftMenu or VirtualKey.RightMenu => "\u0012",
        VirtualKey.LeftWindows or VirtualKey.RightWindows => "\u0017",
        _ => null,
    };
}
