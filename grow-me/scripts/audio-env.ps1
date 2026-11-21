# audio-env.ps1 - inspect/set Windows default playback device volume (no external deps)
param(
  [switch]$SetVolume,
  [double]$Level = 0.85,
  [switch]$Unmute
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct PROPERTYKEY { public Guid fmtid; public int pid; }

[StructLayout(LayoutKind.Explicit)]
public struct PROPVARIANT {
  [FieldOffset(0)] public short vt;
  [FieldOffset(8)] public IntPtr pointer;
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumeratorComObject { }

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
  int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
  int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
  int GetDevice(string id, out IMMDevice device);
  int RegisterEndpointNotificationCallback(IntPtr client);
  int UnregisterEndpointNotificationCallback(IntPtr client);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
  int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
  int OpenPropertyStore(int access, out IPropertyStore props);
  int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
  int GetState(out int state);
}

[Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPropertyStore {
  int GetCount(out int count);
  int GetAt(int index, out PROPERTYKEY key);
  int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
  int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
  int Commit();
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioEndpointVolume {
  int RegisterControlChangeNotify(IntPtr notify);
  int UnregisterControlChangeNotify(IntPtr notify);
  int GetChannelCount(out int count);
  int SetMasterVolumeLevel(float level, ref Guid context);
  int SetMasterVolumeLevelScalar(float level, ref Guid context);
  int GetMasterVolumeLevel(out float level);
  int GetMasterVolumeLevelScalar(out float level);
  int GetChannelVolumeLevel(uint channel, out float level);
  int SetChannelVolumeLevel(uint channel, float level, ref Guid context);
  int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
  int GetChannelVolumeLevelScalar(uint channel, out float level);
  int SetMute(bool mute, ref Guid context);
  int GetMute(out bool mute);
  int GetVolumeStepInfo(out uint step, out uint stepCount);
  int VolumeStepUp(ref Guid context);
  int VolumeStepDown(ref Guid context);
  int QueryHardwareSupport(out int mask);
  int GetVolumeRange(out float min, out float max, out float inc);
}

public static class AudioEnv {
  public static string Report(bool setVolume, double level, bool unmute) {
    var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
    IMMDevice dev;
    int hr = enumerator.GetDefaultAudioEndpoint(0, 0, out dev);
    if (hr != 0) return "ERR no-default-render hr=" + hr;
    string id = ""; dev.GetId(out id);
    IPropertyStore store;
    dev.OpenPropertyStore(0, out store);
    var key = new PROPERTYKEY { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };
    PROPVARIANT val;
    string name = "";
    if (store.GetValue(ref key, out val) == 0 && val.vt == 31) name = Marshal.PtrToStringUni(val.pointer);
    var iid = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
    object obj;
    dev.Activate(ref iid, 1, IntPtr.Zero, out obj);
    var vol = (IAudioEndpointVolume)obj;
    float scalar; vol.GetMasterVolumeLevelScalar(out scalar);
    bool mute; vol.GetMute(out mute);
    if (setVolume) {
      var ctx = Guid.Empty;
      vol.SetMasterVolumeLevelScalar((float)level, ref ctx);
      if (unmute) vol.SetMute(false, ref ctx);
      vol.GetMasterVolumeLevelScalar(out scalar);
      vol.GetMute(out mute);
    }
    return "DEVICE=" + name + " | id=" + id + " | volume=" + Math.Round(scalar * 100) + "% | mute=" + mute;
  }
}
"@
$out = [AudioEnv]::Report($SetVolume, $Level, $Unmute)
Write-Output $out
