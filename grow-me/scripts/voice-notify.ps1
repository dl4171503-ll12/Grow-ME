# voice-notify.ps1 - task-completion voice notification (Edge TTS, offline fallback)
# Behavior:
#   1) speaks a SHORT plain-language report (from -Text or -File)
#   2) checks the foreground window; if the agent window is NOT in the foreground,
#      prepends a reminder and repeats it (default 2 times) so the user notices.
# Usage:
#   powershell -File scripts/voice-notify.ps1 -Text "做完了，结果在报告里。"
#   powershell -File scripts/voice-notify.ps1 -File .grow-me/voice/20261121-1200-demo.txt
#   powershell -File scripts/voice-notify.ps1 -File ... -ForegroundWindow "DeepSeek Harness"
# Output: one JSON object on stdout.
param(
  [string]$Text,
  [string]$File,
  [string]$Voice = 'zh-CN-YunxiNeural',
  [ValidateSet('a', 'b', 'c', 'youth')][string]$Preset,
  [string]$Rate = '+0%',
  [string]$Pitch = '+0Hz',
  [string]$Volume = '+0%',
  [string]$ForegroundWindow = '',
  [int]$RepeatBackground = 2,
  [switch]$ForceForeground,
  [switch]$NoPlay
)
$ErrorActionPreference = 'Stop'
$presetMap = @{
  a     = @{ voice = 'zh-CN-XiaoxiaoNeural'; rate = 0; pitch = 0; volume = 0 }
  b     = @{ voice = 'zh-CN-XiaoyiNeural';   rate = 0; pitch = 0; volume = 0 }
  c     = @{ voice = 'zh-CN-YunxiNeural';    rate = 0; pitch = 0; volume = 0 }
  youth = @{ voice = 'zh-CN-YunxiNeural';    rate = -2; pitch = 8; volume = 0 }
}
$effRate = $Rate
$effPitch = $Pitch
$effVolume = $Volume
if ($Preset) {
  $Voice = $presetMap[$Preset].voice
  # keep the numeric accumulation simple: emit combined offsets as strings
  function Add-Offset([string]$base, [double]$delta, [string]$unit) {
    $v = 0.0
    if ($base -match '([+-]?\d+(?:\.\d+)?)') { $v = [double]$Matches[1] }
    $v += $delta
    $sign = if ($v -lt 0) { '-' } else { '+' }
    return ('{0}{1:0}{2}' -f $sign, [Math]::Abs([Math]::Round($v)), $unit)
  }
  $effRate = Add-Offset $Rate $presetMap[$Preset].rate '%'
  $effPitch = Add-Offset $Pitch $presetMap[$Preset].pitch 'Hz'
  $effVolume = Add-Offset $Volume $presetMap[$Preset].volume '%'
}
# built from chars so this file stays pure ASCII (PS 5.1 reads BOM-less files as ANSI)
$reminderPrefix = -join ([char]0x63D0, [char]0x9192, [char]0xFF1A)
$here = $PSScriptRoot
$edgeScript = Join-Path $here 'voice-edge-tts.ps1'
$offlineScript = Join-Path $here 'voice-offline.ps1'
$notifyLog = Join-Path $env:USERPROFILE '.grow-me\voice\notify.jsonl'
$voiceDir = Split-Path $notifyLog -Parent
New-Item -ItemType Directory -Force -Path $voiceDir | Out-Null

$spokenText = $Text
$sourceFile = $null
if ($File) {
  if (-not (Test-Path $File)) { Write-Host ('FILE_MISSING ' + $File); exit 3 }
  $sourceFile = (Resolve-Path $File).Path
  $spokenText = (Get-Content -LiteralPath $sourceFile -Raw -Encoding UTF8).Trim()
}
if (-not $spokenText) { Write-Host 'usage: voice-notify.ps1 -Text "..." | -File path'; exit 0 }

# foreground detection
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class GrowMeFg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
}
"@
$fgHandle = [GrowMeFg]::GetForegroundWindow()
$fgPid = 0
[void][GrowMeFg]::GetWindowThreadProcessId($fgHandle, [ref]$fgPid)
$fgName = ''
$fgTitle = ''
if ($fgPid -gt 0) {
  $p = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
  if ($p) { $fgName = $p.ProcessName }
}
if ($fgHandle -ne [IntPtr]::Zero) {
  $sb = New-Object System.Text.StringBuilder 512
  [void][GrowMeFg]::GetWindowText($fgHandle, $sb, $sb.Capacity)
  $fgTitle = $sb.ToString()
}

$pattern = if ($ForegroundWindow) { $ForegroundWindow } else { 'DeepSeek Harness|DeepSeek|Harness|DSH|127\.0\.0\.1:52352' }
$inForeground = $false
if ($ForceForeground) {
  $inForeground = $true
} else {
  $inForeground = ($fgName -match $pattern) -or ($fgTitle -match $pattern)
}

$repeat = 1
$toSpeak = $spokenText
if (-not $inForeground) {
  $repeat = [Math]::Max(1, $RepeatBackground)
  $toSpeak = $reminderPrefix + $spokenText
}

$edgeOk = $true
$fallback = $false
for ($i = 1; $i -le $repeat; $i++) {
  $ok = $true
  if (Test-Path $edgeScript) {
    $edgeArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $edgeScript, '-Text', $toSpeak, '-Voice', $Voice, '-Rate', $effRate, '-Pitch', $effPitch, '-Volume', $effVolume)
    if ($NoPlay) { $edgeArgs += '-NoPlay' }
    & powershell @edgeArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $ok = $false }
  } else { $ok = $false }
  if (-not $ok) {
    $edgeOk = $false
    $fallback = $true
    if (Test-Path $offlineScript) {
      $offArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $offlineScript, '-Text', $toSpeak)
      if ($NoPlay) { $offArgs += '-SaveWav' ; $offArgs += (Join-Path $env:TEMP 'voice-notify-fallback.wav') }
      & powershell @offArgs 2>&1 | Out-Null
    }
  }
  if ($i -lt $repeat) { Start-Sleep -Seconds 2 }
}

$record = [ordered]@{
  ok = $true
  when = (Get-Date).ToString('o')
  foreground = $inForeground
  foreground_process = $fgName
  foreground_title = $fgTitle
  repeats = $repeat
  edge = $edgeOk
  fallback = $fallback
  voice = $Voice
  text = $spokenText
  file = $sourceFile
}
$line = ($record | ConvertTo-Json -Compress)
Add-Content -LiteralPath $notifyLog -Value $line -Encoding UTF8
$line
