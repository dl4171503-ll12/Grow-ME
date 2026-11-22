# widget-native.ps1 - native helpers for the floating widget (dot-source)
if (-not ('GmRec' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.IO;
using System.Text;

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
      w.Write(buf, 0, (int)n);
      w.Flush();
    }
    return "SAVED " + n;
  }
}

public static class GmWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
}
