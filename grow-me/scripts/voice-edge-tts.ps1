# voice-edge-tts.ps1 - Edge neural TTS (online, no API key) with WAV/MP3 output and playback
# Usage:
#   powershell -File scripts/voice-edge-tts.ps1 -ListVoices
#   powershell -File scripts/voice-edge-tts.ps1 -Text "你好" [-Voice zh-CN-XiaoxiaoNeural] [-Rate +0%] [-Pitch +0Hz] [-SaveMp3 x.mp3] [-NoPlay]
param(
  [string]$Text,
  [string]$Voice = 'zh-CN-YunxiNeural',
  [ValidateSet('a', 'b', 'c')][string]$Preset,
  [string]$Rate = '+0%',
  [string]$Pitch = '+0Hz',
  [string]$SaveMp3,
  [switch]$NoPlay,
  [switch]$ListVoices,
  [switch]$ListPresets
)
$ErrorActionPreference = 'Stop'
$presets = [ordered]@{
  a = @{ voice = 'zh-CN-XiaoxiaoNeural'; label = 'A Xiaoxiao (female, warm)' }
  b = @{ voice = 'zh-CN-XiaoyiNeural'; label = 'B Xiaoyi (female, lively)' }
  c = @{ voice = 'zh-CN-YunxiNeural'; label = 'C Yunxi (male, sunny, default)' }
}
if ($ListPresets) {
  foreach ($k in $presets.Keys) { "{0} -> {1} | {2}" -f $k, $presets[$k].voice, $presets[$k].label }
  exit 0
}
if ($Preset) { $Voice = $presets[$Preset].voice }
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

# Decode MP3 to WAV via Python soundfile (libsndfile) and play with SoundPlayer.
# (WPF MediaPlayer was unreliable here: it reported duration but produced odd/no audio.)
$wav = [IO.Path]::ChangeExtension($mp3, '.wav')
$decoded = $false
try {
  $tmpPy = Join-Path $env:TEMP ('edge-dec-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.py')
  $pyCode = @'
import sys
import soundfile as sf
src, dst = sys.argv[1], sys.argv[2]
data, rate = sf.read(src, dtype="float32")
if getattr(data, "ndim", 1) > 1:
    data = data.mean(axis=1)
sf.write(dst, data, rate, subtype="PCM_16")
print("DECODED", rate)
'@
  Set-Content -Path $tmpPy -Value $pyCode -Encoding ASCII
  & py -3 -X utf8 $tmpPy $mp3 $wav 2>&1 | Out-Null
  $decoded = (Test-Path $wav) -and ((Get-Item $wav).Length -gt 1000)
  Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue
} catch { $decoded = $false }

if ($decoded) { Write-Host ('WAV ' + $wav) }

if (-not $NoPlay) {
  if ($decoded) {
    try { (New-Object System.Media.SoundPlayer $wav).PlaySync(); Write-Host 'PLAYED local wav' }
    catch { Write-Host ('PLAY_FAIL_WAV ' + $_.Exception.Message) }
  } else {
    try {
      Add-Type -AssemblyName PresentationCore
      $player = New-Object System.Windows.Media.MediaPlayer
      $player.Open([Uri]$mp3)
      $player.Play()
      for ($i = 0; $i -lt 60; $i++) { if ($player.NaturalDuration.HasTimeSpan) { break }; Start-Sleep -Milliseconds 100 }
      if ($player.NaturalDuration.HasTimeSpan) {
        $sec = $player.NaturalDuration.TimeSpan.TotalSeconds
        Start-Sleep -Milliseconds ([int]($sec * 1000) + 400)
      } else { Start-Sleep -Seconds 3 }
      $player.Close()
      Write-Host 'PLAYED mediaplayer'
    } catch {
      Write-Host ('PLAY_FAIL ' + $_.Exception.Message)
    }
  }
}
