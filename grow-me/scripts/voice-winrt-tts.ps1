# voice-winrt-tts.ps1 - higher-quality Windows natural voices via WinRT (offline, no API)
# Usage:
#   powershell -File scripts/voice-winrt-tts.ps1 -ListVoices
#   powershell -File scripts/voice-winrt-tts.ps1 -Text "你好" -Voice "Microsoft Yaoyao" [-SaveWav x.wav] [-Rate 1.0] [-NoPlay]
param(
  [string]$Text,
  [string]$Voice,
  [string]$SaveWav,
  [double]$Rate = 1.0,
  [switch]$ListVoices,
  [switch]$NoPlay
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesisStream, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage, ContentType = WindowsRuntime]

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  })[0]

function Await($WinRtTask, $ResultType) {
  $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
  $netTask = $asTask.Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}

$all = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices
if ($ListVoices) {
  $all | ForEach-Object { "{0} | {1}" -f $_.DisplayName, $_.Language }
  exit 0
}
if (-not $Text) {
  Write-Host 'usage: voice-winrt-tts.ps1 -Text "..." [-Voice "Microsoft Yaoyao"] [-SaveWav x.wav] [-Rate 1.0] [-NoPlay]'
  exit 0
}

$target = $null
if ($Voice) { $target = $all | Where-Object { $_.DisplayName -eq $Voice -or $_.DisplayName -like "*$Voice*" } | Select-Object -First 1 }
if (-not $target) { $target = $all | Where-Object { $_.Language -eq 'zh-CN' } | Select-Object -First 1 }
if (-not $target) { $target = $all | Select-Object -First 1 }
if (-not $target) { Write-Host 'NO_VOICE'; exit 3 }

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$synth.Voice = $target
try { $synth.Options.SpeakingRate = $Rate } catch {}
$stream = Await ($synth.SynthesizeTextToStreamAsync($Text)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])

$out = $SaveWav
if (-not $out) { $out = Join-Path $env:TEMP ('growme-tts-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wav') }
$fileStream = [IO.File]::Create($out)
try {
  $netStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
  $netStream.CopyTo($fileStream)
} finally {
  $fileStream.Dispose()
}

Write-Host ("VOICE " + $target.DisplayName + " " + $target.Language)
Write-Host ("TTS_OK " + $Text)
Write-Host ("WAV " + $out)

if (-not $NoPlay) {
  try {
    $player = New-Object System.Media.SoundPlayer $out
    $player.PlaySync()
  } catch {
    Write-Host ('PLAY_FAIL ' + $_.Exception.Message)
  }
}
