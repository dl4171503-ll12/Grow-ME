# widget-native.ps1 - native helpers for the floating widget (dot-source)
if (-not ('GmRec' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.IO;
using System.Text;
using System.Collections.Generic;

public static class GmRec {
  [StructLayout(LayoutKind.Sequential)]
  public struct WAVEFORMATEX { public ushort wFormatTag; public ushort nChannels; public uint nSamplesPerSec; public uint nAvgBytesPerSec; public ushort nBlockAlign; public ushort wBitsPerSample; public ushort cbSize; }
  [StructLayout(LayoutKind.Sequential)]
  public struct WAVEHDR { public IntPtr lpData; public uint dwBufferLength; public uint dwBytesRecorded; public IntPtr dwUser; public uint dwFlags; public uint dwLoops; public IntPtr lpNext; public IntPtr reserved; }

  [DllImport("winmm.dll")] static extern int waveInOpen(out IntPtr hwi, uint device, ref WAVEFORMATEX fmt, IntPtr callback, IntPtr instance, uint flags);
  [DllImport("winmm.dll")] static extern int waveInPrepareHeader(IntPtr hwi, IntPtr hdr, uint size);
  [DllImport("winmm.dll")] static extern int waveInUnprepareHeader(IntPtr hwi, IntPtr hdr, uint size);
  [DllImport("winmm.dll")] static extern int waveInAddBuffer(IntPtr hwi, IntPtr hdr, uint size);
  [DllImport("winmm.dll")] static extern int waveInStart(IntPtr hwi);
  [DllImport("winmm.dll")] static extern int waveInReset(IntPtr hwi);
  [DllImport("winmm.dll")] static extern int waveInStop(IntPtr hwi);
  [DllImport("winmm.dll")] static extern int waveInClose(IntPtr hwi);

  static IntPtr h;
  static byte[] buf;
  static IntPtr hdrPtr;
  static GCHandle bufHandle;
  static int rate = 16000;
  public static bool IsRecording = false;

  public static string Start() {
    if (IsRecording) return "ALREADY";
    var fmt = new WAVEFORMATEX();
    fmt.wFormatTag = 1; fmt.nChannels = 1; fmt.nSamplesPerSec = (uint)rate;
    fmt.wBitsPerSample = 16; fmt.nBlockAlign = 2; fmt.nAvgBytesPerSec = (uint)(rate * 2); fmt.cbSize = 0;
    int rc = waveInOpen(out h, 0xFFFFFFFF, ref fmt, IntPtr.Zero, IntPtr.Zero, 0);
    if (rc != 0) return "OPEN_FAIL " + rc;
    int seconds = 60;
    buf = new byte[rate * 2 * seconds];
    bufHandle = GCHandle.Alloc(buf, GCHandleType.Pinned);
    var hdr = new WAVEHDR();
    hdr.lpData = bufHandle.AddrOfPinnedObject();
    hdr.dwBufferLength = (uint)buf.Length;
    hdrPtr = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WAVEHDR)));
    Marshal.StructureToPtr(hdr, hdrPtr, false);
    waveInPrepareHeader(h, hdrPtr, (uint)Marshal.SizeOf(typeof(WAVEHDR)));
    waveInAddBuffer(h, hdrPtr, (uint)Marshal.SizeOf(typeof(WAVEHDR)));
    rc = waveInStart(h);
    if (rc != 0) return "START_FAIL " + rc;
    IsRecording = true;
    return "RECORDING";
  }

  public static string Stop(string path) {
    if (!IsRecording) return "NOT_RECORDING";
    waveInStop(h);
    waveInReset(h);
    var hdr = (WAVEHDR)Marshal.PtrToStructure(hdrPtr, typeof(WAVEHDR));
    uint n = hdr.dwBytesRecorded;
    waveInUnprepareHeader(h, hdrPtr, (uint)Marshal.SizeOf(typeof(WAVEHDR)));
    waveInClose(h);
    Marshal.FreeHGlobal(hdrPtr);
    bufHandle.Free();
    IsRecording = false;
    if (n == 0) return "EMPTY";
    // auto-gain: built-in mic array can be very quiet; boost before saving so local ASR works
    short peak = 0;
    for (uint i = 0; i + 1 < n; i += 2) {
      short v = BitConverter.ToInt16(buf, (int)i);
      int a = Math.Abs((int)v); if (a > peak) peak = (short)Math.Min(a, 32767);
    }
    double gain = (peak > 0) ? Math.Min(40.0, (0.90 * 32767.0) / peak) : 1.0;
    if (gain < 1.0) gain = 1.0;
    byte[] outBuf = new byte[n];
    for (uint i = 0; i + 1 < n; i += 2) {
      short v = BitConverter.ToInt16(buf, (int)i);
      int sv = (int)Math.Round(v * gain);
      if (sv > 32767) sv = 32767; if (sv < -32768) sv = -32768;
      outBuf[i] = (byte)(sv & 0xFF); outBuf[i + 1] = (byte)((sv >> 8) & 0xFF);
    }
    using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write)) {
      var w = new BinaryWriter(fs);
      w.Write(new byte[] { (byte)'R', (byte)'I', (byte)'F', (byte)'F' });
      w.Write(36 + n);
      w.Write(new byte[] { (byte)'W', (byte)'A', (byte)'V', (byte)'E' });
      w.Write(new byte[] { (byte)'f', (byte)'m', (byte)'t', (byte)' ' });
      w.Write(16); w.Write((short)1); w.Write((short)1);
      w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
      w.Write(new byte[] { (byte)'d', (byte)'a', (byte)'t', (byte)'a' });
      w.Write((int)n);
      w.Write(outBuf, 0, (int)n);
      w.Flush();
    }
    return "SAVED " + n + " gain=" + Math.Round(gain, 1);
  }
}

public static class GmWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

  public static bool ForceForeground(IntPtr h) {
    try {
      if (GetForegroundWindow() == h) return true;
      // Alt tap unlocks the foreground lock
      keybd_event(0x12, 0, 0, UIntPtr.Zero);
      keybd_event(0x12, 0, 2, UIntPtr.Zero);
      System.Threading.Thread.Sleep(80);
      ShowWindow(h, 9);
      BringWindowToTop(h);
      SetForegroundWindow(h);
      System.Threading.Thread.Sleep(150);
      if (GetForegroundWindow() == h) return true;
      // AttachThreadInput fallback
      uint fgPid; uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out fgPid);
      uint myThread = GetCurrentThreadId();
      if (fgThread != 0 && fgThread != myThread) {
        AttachThreadInput(myThread, fgThread, true);
        BringWindowToTop(h);
        SetForegroundWindow(h);
        AttachThreadInput(myThread, fgThread, false);
        System.Threading.Thread.Sleep(150);
      }
      return GetForegroundWindow() == h;
    } catch { return false; }
  }

  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static List<string> Windows() {
    var list = new List<string>();
    EnumWindows((h, l) => {
      if (IsWindowVisible(h)) {
        var sb = new StringBuilder(512); GetWindowText(h, sb, 512);
        if (sb.Length > 0) { uint pid; GetWindowThreadProcessId(h, out pid); list.Add(h.ToInt64() + "|" + pid + "|" + sb.ToString()); }
      }
      return true;
    }, IntPtr.Zero);
    return list;
  }
}

[ComImport, Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A")]
public class VirtualDesktopManager { }

[ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVirtualDesktopManager {
  int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out int onCurrentDesktop);
  int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
  int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
}

public static class GmVd {
  static IVirtualDesktopManager manager;
  static IVirtualDesktopManager Manager() {
    if (manager == null) manager = (IVirtualDesktopManager)new VirtualDesktopManager();
    return manager;
  }
  public static string Status(IntPtr hwnd) {
    try { int on; Manager().IsWindowOnCurrentVirtualDesktop(hwnd, out on); return on != 0 ? "current" : "other"; }
    catch { return "unknown"; }
  }
  public static bool FollowCurrent(IntPtr hwnd) {
    try {
      var m = Manager();
      int on; m.IsWindowOnCurrentVirtualDesktop(hwnd, out on);
      if (on != 0) return false;
      IntPtr fg = GmWin.GetForegroundWindow();
      if (fg == IntPtr.Zero) return false;
      Guid g;
      if (m.GetWindowDesktopId(fg, out g) != 0) return false;
      return m.MoveWindowToDesktop(hwnd, ref g) == 0;
    } catch { return false; }
  }
  public static bool IsTopmost(IntPtr hwnd) {
    try { return (GmWin.GetWindowLong(hwnd, -20) & 0x8) != 0; } catch { return false; }
  }
}
"@
}
