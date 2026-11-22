# asr-setup.ps1 - install local ASR engines and download models (offline, no API)
# usage:
#   powershell -File scripts/asr-setup.ps1                  # SenseVoice (recommended, Chinese)
#   powershell -File scripts/asr-setup.ps1 -Engine whisper -Model base
param(
  [ValidateSet('sensevoice', 'whisper')][string]$Engine = 'sensevoice',
  [string]$Model = 'base',
  [string]$Dir
)
$ErrorActionPreference = 'Stop'
if (-not $Dir) {
  if ($Engine -eq 'sensevoice') { $Dir = Join-Path $env:USERPROFILE '.grow-me\asr\sensevoice' }
  else { $Dir = Join-Path $env:USERPROFILE ('.grow-me\asr\faster-whisper-' + $Model) }
}
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

if ($Engine -eq 'sensevoice') {
  Write-Host '--- pip install sherpa-onnx ---'
  & py -3 -m pip install --quiet --disable-pip-version-check -i https://pypi.tuna.tsinghua.edu.cn/simple sherpa-onnx
  if ($LASTEXITCODE -ne 0) { Write-Host 'PIP_FAILED'; exit 2 }
  $base = 'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/'
  foreach ($f in 'model.int8.onnx', 'tokens.txt') {
    $out = Join-Path $Dir $f
    if (-not (Test-Path $out) -or (Get-Item $out).Length -lt 1000) {
      Write-Host ('downloading ' + $f)
      & curl.exe -L -s -o $out -m 900 ($base + $f)
    }
  }
  $m = Join-Path $Dir 'model.int8.onnx'
  if (-not (Test-Path $m)) { Write-Host 'MODEL_FAILED'; exit 3 }
  Write-Host ('MODEL_READY ' + $Dir + ' (' + [math]::Round((Get-Item $m).Length / 1MB, 1) + ' MB)')
  exit 0
}

Write-Host '--- pip install faster-whisper ---'
& py -3 -m pip install --quiet --disable-pip-version-check -i https://pypi.tuna.tsinghua.edu.cn/simple faster-whisper
if ($LASTEXITCODE -ne 0) { Write-Host 'PIP_FAILED'; exit 2 }
$base = 'https://hf-mirror.com/Systran/faster-whisper-' + $Model + '/resolve/main/'
foreach ($f in 'config.json', 'model.bin', 'tokenizer.json', 'vocabulary.txt') {
  $out = Join-Path $Dir $f
  if (-not (Test-Path $out) -or (Get-Item $out).Length -lt 100) {
    Write-Host ('downloading ' + $f)
    & curl.exe -L -s -o $out -m 900 ($base + $f)
  }
}
$bin = Join-Path $Dir 'model.bin'
if (-not (Test-Path $bin)) { Write-Host 'MODEL_FAILED'; exit 3 }
Write-Host ('MODEL_READY ' + $Dir + ' (' + [math]::Round((Get-Item $bin).Length / 1MB, 1) + ' MB)')
