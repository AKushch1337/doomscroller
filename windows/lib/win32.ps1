# Windows itself: windows of apps and the keyboard, through user32.dll.
# The Windows counterpart of lib/macos.sh. Needs no special permissions.

$WIN32_SOURCE = @'
using System;
using System.Runtime.InteropServices;

public static class DoomscrollerWin32 {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr window);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint thread, uint toThread, bool attach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);

  const int SW_RESTORE = 9;
  const uint KEYEVENTF_EXTENDEDKEY = 1, KEYEVENTF_KEYUP = 2;

  // Brings a window to the front. Windows lets only the app in front do
  // that, so this borrows its input queue for a moment. If that isn't
  // enough, it presses F13 first: a key that types nothing, but makes this
  // process the one that sent the last input, which Windows also accepts.
  public static bool Focus(IntPtr window) {
    if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
    for (int attempt = 0; attempt < 2; attempt++) {
      IntPtr front = GetForegroundWindow();
      if (front == window) return true;
      uint ignored;
      uint frontThread = GetWindowThreadProcessId(front, out ignored);
      uint thread = GetCurrentThreadId();
      bool attached = frontThread != 0 && frontThread != thread && AttachThreadInput(thread, frontThread, true);
      BringWindowToTop(window);
      SetForegroundWindow(window);
      if (attached) AttachThreadInput(thread, frontThread, false);
      if (GetForegroundWindow() == window) return true;
      PressKey(0x7C, false);  // F13
    }
    return GetForegroundWindow() == window;
  }

  // Presses and releases a key, by virtual-key code, in whatever has focus.
  public static void PressKey(byte key, bool extended) {
    uint flags = extended ? KEYEVENTF_EXTENDEDKEY : 0;
    keybd_event(key, 0, flags, UIntPtr.Zero);
    keybd_event(key, 0, flags | KEYEVENTF_KEYUP, UIntPtr.Zero);
  }
}
'@

# Compiles the helpers above, once per process. Takes a second, so only
# commands that need windows call it.
function load_win32 {
  if (-not ('DoomscrollerWin32' -as [type])) {
    Add-Type -TypeDefinition $WIN32_SOURCE
  }
}

# Returns the main window of a running app, by process name ("claude",
# "WindowsTerminal") or id, or 0 if it has none on screen.
function app_window($nameOrId) {
  if ($nameOrId -is [int]) {
    $processes = Get-Process -Id $nameOrId -ErrorAction SilentlyContinue
  } else {
    $processes = Get-Process -Name $nameOrId -ErrorAction SilentlyContinue
  }
  foreach ($process in @($processes)) {
    if ($process.MainWindowHandle -ne [IntPtr]::Zero) { return $process.MainWindowHandle }
  }
  return [IntPtr]::Zero
}

# Brings an app's main window to the front. Returns whether it worked.
function focus_app($nameOrId) {
  load_win32
  $window = app_window $nameOrId
  if ($window -eq [IntPtr]::Zero) { return $false }
  return [DoomscrollerWin32]::Focus($window)
}

# Presses the media play/pause key. Windows hands it to whatever is playing,
# like F8 on a Mac.
function press_play_pause_key {
  load_win32
  [DoomscrollerWin32]::PressKey(0xB3, $true)
}
