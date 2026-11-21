# voice-piper-tts.ps1 - offline neural TTS via Piper (no API, no key)
# Requires: py -3 -m pip install piper-tts  (model auto-download with -Ensure, ~63 MB)
# Usage:
#   powershell -File scripts/voice-piper-tts.ps1 -ListModels
#   powershell -File scripts/voice-piper-tts.ps1 -Text "你好" [-SaveWav x.wav] [-LengthScale 1.0] [-NoPlay] [-Ensure]
param(
  [string]$Text,
  [string]$SaveWav,
  [string]$Model = (Join-Path $env:USERPROFILE '.grow-me\tts\piper\zh_CN-huayan-medium.onnx'),
  [string]$Config,
  [double]$LengthScale = 1.0,
  [switch]$NoPlay,
  [switch]$Ensure
)
$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = $Model + '.json' }
$dir = Split-Path $Model -Parent
if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

function Ensure-Model {
  $name = [IO.Path]::GetFileNameWithoutExtension($Model)
  $base = 'https://hf-mirror.com/rhasspy/piper-voices/resolve/main/zh/zh_CN/' + ($name -replace '^zh_CN-','' -replace '-medium$','') + '/medium/' + $name
  if (-not (Test-Path $Model)) {
    Write-Host ('DOWNLOAD ' + $base + '.onnx')
    & curl.exe -L -s -o $Model ($base + '.onnx')
  }
  if (-not (Test-Path $Config)) {
    & curl.exe -L -s -o $Config ($base + '.onnx.json')
  }
}

if (-not (Test-Path $Model)) {
  if ($Ensure) { Ensure-Model } else {
    Write-Host ('MODEL_MISSING ' + $Model)
    Write-Host 'run with -Ensure to download (hf-mirror, ~63 MB), or install model manually'
    exit 3
  }
}
if (-not (Test-Path $Config)) { Write-Host ('CONFIG_MISSING ' + $Config); exit 3 }

$py = 'py'
$probe = & $py -3 -m piper --help 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host 'PIPER_MISSING (py -3 -m pip install piper-tts)'
  exit 4
}

if (-not $Text) {
  Write-Host 'usage: voice-piper-tts.ps1 -Text "..." [-SaveWav x.wav] [-LengthScale 1.0] [-NoPlay] [-Ensure]'
  Write-Host ('MODEL ' + $Model)
  exit 0
}

$inFile = Join-Path $env:TEMP ('piper-in-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
$outFile = $SaveWav
if (-not $outFile) { $outFile = Join-Path $env:TEMP ('piper-out-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wav') }
$outDir = Split-Path $outFile -Parent
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
[IO.File]::WriteAllText($inFile, $Text + "`n", [Text.UTF8Encoding]::new($false))
& $py -3 -m piper -m $Model -c $Config -i $inFile -f $outFile --length-scale $LengthScale 2>&1 | Out-Null
$code = $LASTEXITCODE
Remove-Item $inFile -Force -ErrorAction SilentlyContinue
if ($code -ne 0 -or -not (Test-Path $outFile)) { Write-Host ('TTS_FAIL exit=' + $code); exit 5 }

$voiceName = [IO.Path]::GetFileNameWithoutExtension($Model)
Write-Host ('VOICE piper:' + $voiceName + ' (length-scale ' + $LengthScale + ')')
Write-Host ('TTS_OK ' + $Text)
Write-Host ('WAV ' + $outFile)

if (-not $NoPlay) {
  try { (New-Object System.Media.SoundPlayer $outFile).PlaySync() } catch { Write-Host ('PLAY_FAIL ' + $_.Exception.Message) }
}
