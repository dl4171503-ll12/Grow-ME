# voice-edge-tts.ps1 - Edge neural TTS (online, no API key) with WAV/MP3 output and playback
# Usage:
#   powershell -File scripts/voice-edge-tts.ps1 -ListVoices
#   powershell -File scripts/voice-edge-tts.ps1 -Text "你好" [-Voice zh-CN-XiaoxiaoNeural] [-Rate +0%] [-Pitch +0Hz] [-SaveMp3 x.mp3] [-NoPlay]
param(
  [string]$Text,
  [string]$Voice = 'zh-CN-XiaoxiaoNeural',
  [string]$Rate = '+0%',
  [string]$Pitch = '+0Hz',
  [string]$SaveMp3,
  [switch]$NoPlay,
  [switch]$ListVoices
)
$ErrorActionPreference = 'Stop'
if ($ListVoices) {
  & py -3 -m edge_tts --list-voices 2>&1 | Select-String 'zh-CN|en-US' | ForEach-Object { $_.Line }
  exit 0
}
if (-not $Text) {
  Write-Host 'usage: voice-edge-tts.ps1 -Text "..." [-Voice zh-CN-XiaoxiaoNeural] [-Rate +0%] [-Pitch +0Hz] [-SaveMp3 x.mp3] [-NoPlay]'
  exit 0
}
$dir = Join-Path $env:USERPROFILE '.grow-me\tts\edge'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$mp3 = $SaveMp3
if (-not $mp3) { $mp3 = Join-Path $dir ('edge-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.mp3') }
$mp3Dir = Split-Path $mp3 -Parent
if ($mp3Dir) { New-Item -ItemType Directory -Force -Path $mp3Dir | Out-Null }

& py -3 -m edge_tts --voice $Voice --rate $Rate --pitch $Pitch --text $Text --write-media $mp3 2>&1 | Out-Null
$code = $LASTEXITCODE
if ($code -ne 0 -or -not (Test-Path $mp3) -or (Get-Item $mp3).Length -lt 1000) {
  Write-Host ('EDGE_FAIL exit=' + $code)
  exit 5
}
Write-Host ('VOICE edge:' + $Voice + ' rate=' + $Rate)
Write-Host ('TTS_OK ' + $Text)
Write-Host ('MP3 ' + $mp3)

if (-not $NoPlay) {
  try {
    Add-Type -AssemblyName PresentationCore
    $player = New-Object System.Windows.Media.MediaPlayer
    $player.Open([Uri]$mp3)
    $player.Play()
    for ($i = 0; $i -lt 60; $i++) { if ($player.NaturalDuration.HasTimeSpan) { break }; Start-Sleep -Milliseconds 100 }
    if ($player.NaturalDuration.HasTimeSpan) {
      $sec = $player.NaturalDuration.TimeSpan.TotalSeconds
      Start-Sleep -Milliseconds ([int]($sec * 1000) + 400)
    } else {
      Start-Sleep -Seconds 3
    }
    $player.Close()
  } catch {
    Write-Host ('PLAY_FAIL ' + $_.Exception.Message)
  }
}
