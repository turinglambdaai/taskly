using System.Runtime.InteropServices;

namespace Taskly.Services;

/// <summary>
/// System-tray icon via raw Shell_NotifyIcon (no tray NuGet package —
/// H.NotifyIcon's winmd breaks the WinUI XamlCompiler). A message-only
/// window receives the callback; its WndProc runs on the UI thread, so
/// events fire there directly.
/// </summary>
public sealed class TrayIconService : IDisposable
{
    private const int WM_APP_CB = 0x8000 + 0x0400; // WM_APP + 1024
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_LBUTTONDBLCLK = 0x0203;
    private const int WM_RBUTTONUP = 0x0205;
    private const int NIM_ADD = 0x0;
    private const int NIM_MODIFY = 0x1;
    private const int NIM_DELETE = 0x2;
    private const int NIF_MESSAGE = 0x1;
    private const int NIF_ICON = 0x2;
    private const int NIF_TIP = 0x4;
    private const int MENU_SHOW = 1;
    private const int MENU_EXIT = 2;
    private const uint WM_COMMAND_SIMPLE_SHOW = 0x0400 + 1;
    private const uint WM_COMMAND_SIMPLE_EXIT = 0x0400 + 2;

    public event Action? ShowRequested;
    public event Action? ExitRequested;

    private nint _hwnd;
    private nint _hicon;
    private string _tip = "Taskly";
    private WndProcDelegate? _wndProcDelegate;

    // Single tray per process: static WndProc dispatches to it.
    private static TrayIconService? _active;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public int cbSize;
        public nint hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public nint hwnd;
        public uint message;
        public nint wParam;
        public nint lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    private delegate nint WndProcDelegate(nint hwnd, uint msg, nint wParam, nint lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassW(ref WNDCLASSW wc);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint CreateWindowExW(uint exStyle, string className, string windowName,
        uint style, int x, int y, int w, int h, nint parent, nint menu, nint instance, nint param);

    [DllImport("user32.dll")]
    private static extern nint DefWindowProcW(nint hwnd, uint msg, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern bool GetMessageW(out MSG msg, nint hwnd, uint min, uint max);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG msg);

    [DllImport("user32.dll")]
    private static extern nint DispatchMessageW(ref MSG msg);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool DestroyWindow(nint hwnd);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Shell_NotifyIconW(int message, ref NOTIFYICONDATA data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint LoadImageW(nint hInst, string name, uint type, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hwnd);

    [DllImport("user32.dll")]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool AppendMenuW(nint menu, uint flags, nint id, string text);

    [DllImport("user32.dll")]
    private static extern int TrackPopupMenu(nint menu, uint flags, int x, int y,
        int reserved, nint hwnd, nint rect);

    [DllImport("user32.dll")]
    private static extern bool DestroyMenu(nint menu);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT p);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSW
    {
        public uint style;
        public nint lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public nint hInstance;
        public nint hIcon;
        public nint hCursor;
        public nint hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
    }

    private string _showText = "Show";
    private string _exitText = "Exit";

    public void Show(nint hInstance, string iconPath, string tip, string showText, string exitText)
    {
        _tip = tip;
        _showText = showText;
        _exitText = exitText;
        _active = this;

        _wndProcDelegate = new WndProcDelegate(WndProc);
        var wndProc = _wndProcDelegate;
        var wc = new WNDCLASSW
        {
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(wndProc),
            lpszClassName = "TasklyTrayWnd",
            hInstance = hInstance,
        };
        _ = RegisterClassW(ref wc);
        // HWND_MESSAGE: a message-only window — never in the taskbar.
        _hwnd = CreateWindowExW(0, "TasklyTrayWnd", "TasklyTray", 0,
            0, 0, 0, 0, (nint)(-3), nint.Zero, nint.Zero, nint.Zero); // -3 = HWND_MESSAGE

        if (_hwnd == nint.Zero)
        {
            return;
        }

        // LR_LOADFROMFILE = 0x10.
        _hicon = LoadImageW(nint.Zero, iconPath, 1, 0, 0, 0x10);

        var nid = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP,
            uCallbackMessage = WM_APP_CB,
            hIcon = _hicon,
            szTip = tip,
        };
        _ = Shell_NotifyIconW(NIM_ADD, ref nid);

        // Pump on the dedicated tray thread (MainWindow starts it as a
        // background STA thread); events marshal to the UI via the window's
        // DispatcherQueue in the subscriber.
        while (GetMessageW(out var msg, _hwnd, 0, 0))
        {
            _ = TranslateMessage(ref msg);
            _ = DispatchMessageW(ref msg);
        }
    }

    private static nint WndProc(nint hwnd, uint msg, nint wParam, nint lParam)
    {
        if (msg == WM_APP_CB && _active is not null)
        {
            switch (lParam)
            {
                case WM_LBUTTONUP or WM_LBUTTONDBLCLK:
                    _active.ShowRequested?.Invoke();
                    break;
                case WM_RBUTTONUP:
                    _active.ShowMenu();
                    break;
            }
        }
        else if (msg == WM_COMMAND_SIMPLE_SHOW && _active is not null)
        {
            _active.ShowRequested?.Invoke();
        }
        else if (msg == WM_COMMAND_SIMPLE_EXIT && _active is not null)
        {
            _active.ExitRequested?.Invoke();
        }

        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    private void ShowMenu()
    {
        _ = SetForegroundWindow(_hwnd);
        var menu = CreatePopupMenu();
        _ = AppendMenuW(menu, 0, MENU_SHOW, _showText);
        _ = AppendMenuW(menu, 0, MENU_EXIT, _exitText);
        _ = GetCursorPos(out var p);
        // TPM_RETURNCMD returns the selection directly.
        var chosen = (int)TrackPopupMenu(menu, 0x0180, p.X, p.Y, 0, _hwnd, nint.Zero);
        _ = DestroyMenu(menu);
        if (chosen == MENU_SHOW)
        {
            ShowRequested?.Invoke();
        }
        else if (chosen == MENU_EXIT)
        {
            ExitRequested?.Invoke();
        }
    }

    public void UpdateTip(string tip)
    {
        _tip = tip;
        if (_hwnd == nint.Zero)
        {
            return;
        }

        var nid = new NOTIFYICONDATA
        {
            cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hwnd,
            uID = 1,
            uFlags = NIF_TIP,
            szTip = _tip,
        };
        _ = Shell_NotifyIconW(NIM_MODIFY, ref nid);
    }

    public void Dispose()
    {
        if (_hwnd != nint.Zero)
        {
            var nid = new NOTIFYICONDATA
            {
                cbSize = Marshal.SizeOf<NOTIFYICONDATA>(),
                hWnd = _hwnd,
                uID = 1,
            };
            _ = Shell_NotifyIconW(NIM_DELETE, ref nid);
            _ = DestroyWindow(_hwnd);
            _hwnd = nint.Zero;
        }

        if (_hicon != nint.Zero)
        {
            _ = DestroyIcon(_hicon);
            _hicon = nint.Zero;
        }

        if (_active == this)
        {
            _active = null;
        }
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(nint hicon);

    // Show() blocks on the message pump; exit means ending that pump.
    public void RequestShutdown()
    {
        _ = PostMessageW(_hwnd, 0x0010, nint.Zero, nint.Zero); // WM_CLOSE
    }

    [DllImport("user32.dll")]
    private static extern bool PostMessageW(nint hwnd, uint msg, nint wParam, nint lParam);
}
