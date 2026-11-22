# asr-file.ps1 - transcribe an audio file locally (SenseVoice -> Whisper -> SAPI)
# usage: powershell -File scripts/asr-file.ps1 -Wav C:\path\to\rec.wav
param(
  [Parameter(Mandatory = $true)][string]$Wav
)
$ErrorActionPreference = 'Stop'
try {
  [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
  $env:PYTHONIOENCODING = 'utf-8'
  $env:PYTHONUTF8 = '1'
} catch {}
if (-not (Test-Path $Wav)) { Write-Host 'FILE_MISSING'; exit 2 }

$sv = Join-Path $PSScriptRoot 'asr-sensevoice.py'
$svDir = Join-Path $env:USERPROFILE '.grow-me\asr\sensevoice'
if ((Test-Path $sv) -and (Test-Path (Join-Path $svDir 'model.int8.onnx'))) {
  $out = & py -3 -X utf8 $sv $Wav $svDir 2>&1
  $line = ($out | Where-Object { $_ -like 'ASR_TEXT *' } | Select-Object -First 1)
  if ($line) { Write-Output $line; exit 0 }
}
$whisper = Join-Path $PSScriptRoot 'asr-whisper.py'
$modelDir = Join-Path $env:USERPROFILE '.grow-me\asr\faster-whisper-base'
if ((Test-Path $whisper) -and (Test-Path (Join-Path $modelDir 'model.bin'))) {
  $out = & py -3 -X utf8 $whisper $Wav $modelDir 2>&1
  $line = ($out | Where-Object { $_ -like 'ASR_TEXT *' } | Select-Object -First 1)
  if ($line) { Write-Output $line; exit 0 }
}
$sapi = Join-Path $PSScriptRoot 'widget-asr.ps1'
if (Test-Path $sapi) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $sapi -Wav $Wav
}
