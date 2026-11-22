# asr-setup.ps1 - install faster-whisper (offline ASR) and download a Chinese model
# usage: powershell -File scripts/asr-setup.ps1 [-Model base|small] [-Dir path]
param(
  [string]$Model = 'base',
  [string]$Dir
)
$ErrorActionPreference = 'Stop'
if (-not $Dir) { $Dir = Join-Path $env:USERPROFILE (".grow-me\asr\faster-whisper-" + $Model) }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
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
