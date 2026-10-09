// P/Invoke declarations for the sb_* C ABI (swift/Sources/CSlintBindings/slint_bindings.h).
// Keep in sync with the header; M2 generates this file instead (csbindgen or a cbindgen-driven step).

using System;
using System.Runtime.InteropServices;

namespace SlintBindings.WinUI;

[StructLayout(LayoutKind.Sequential)]
internal struct SbFrame
{
    public byte Redrawn;
    public byte Animating;
    public byte Failed;
}

internal enum SbPointerButton : byte
{
    Left = 0,
    Right = 1,
    Middle = 2,
}

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate void SbSubmittedFn(IntPtr userData, IntPtr name);

internal static partial class NativeMethods
{
    private const string Lib = "slint_bindings_ffi";

    [LibraryImport(Lib)] internal static partial IntPtr sb_last_error();
    [LibraryImport(Lib)] internal static partial IntPtr sb_demo_new(uint width, uint height, float scale);
    [LibraryImport(Lib)] internal static partial void sb_host_free(IntPtr host);
    [LibraryImport(Lib)] internal static partial nuint sb_host_frame_len(IntPtr host);

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_resize(IntPtr host, uint width, uint height, float scale);

    [LibraryImport(Lib)] internal static unsafe partial SbFrame sb_host_render(IntPtr host, byte* buf, nuint len);
    [LibraryImport(Lib)] internal static partial void sb_tick();

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_pointer_moved(IntPtr host, float x, float y);

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_pointer_pressed(IntPtr host, float x, float y, SbPointerButton button);

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_pointer_released(IntPtr host, float x, float y, SbPointerButton button);

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_pointer_exited(IntPtr host);

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_pointer_scrolled(IntPtr host, float x, float y, float dx, float dy);

    [LibraryImport(Lib)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_focus_changed(IntPtr host, [MarshalAs(UnmanagedType.U1)] bool focused);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_key_pressed(IntPtr host, string text);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_key_released(IntPtr host, string text);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_composition_update(IntPtr host, string preedit, int utf16Start, int utf16End);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static partial bool sb_host_composition_commit(IntPtr host, string text);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    [return: MarshalAs(UnmanagedType.U1)]
    internal static unsafe partial bool sb_appkit_key_text(
        ushort keyCode, string characters, string ignoring, uint modifiers, byte* buffer, nuint bufferLen);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial void sb_demo_set_name(IntPtr host, string name);

    [LibraryImport(Lib)]
    internal static partial void sb_demo_on_submitted(IntPtr host, IntPtr callback, IntPtr userData);

    internal static string LastError() =>
        Marshal.PtrToStringUTF8(sb_last_error()) ?? "unknown error";
}
