// WinUI virtual keys to Slint key text. The table lives in Rust
// (`virtual_key_text`) so the tests can cover every slint::platform::Key
// without Windows. Printable characters arrive through CharacterReceived.

using System.Text;
using Windows.System;

namespace SlintBindings.WinUI;

internal static class SlintKeys
{
    /// <summary>A key Slint names from the virtual key alone, or null when a character is required.</summary>
    public static string? Command(VirtualKey key, bool shift)
    {
        var buffer = new byte[16];
        unsafe
        {
            fixed (byte* p = buffer)
            {
                if (!NativeMethods.sb_virtual_key_command((ushort)key, shift, p, (nuint)buffer.Length))
                    return null;
            }
        }
        return Decode(buffer);
    }

    /// <summary>The Slint key text for one event, or null when it is not a Slint key.</summary>
    public static string? Text(VirtualKey key, string character, bool shift, bool control)
    {
        var buffer = new byte[16];
        unsafe
        {
            fixed (byte* p = buffer)
            {
                if (!NativeMethods.sb_virtual_key_text((ushort)key, character, shift, control, p, (nuint)buffer.Length))
                    return null;
            }
        }
        return Decode(buffer);
    }

    private static string? Decode(byte[] buffer)
    {
        var n = System.Array.IndexOf(buffer, (byte)0);
        if (n <= 0) return null;
        return Encoding.UTF8.GetString(buffer, 0, n);
    }
}
