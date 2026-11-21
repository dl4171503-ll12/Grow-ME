# voice-hybrid-tts.ps1 - offline Chinese+English hybrid TTS via Piper (no API, no key)
# Chinese runs use the zh model, English/ASCII runs use the en model, results are
# resampled to 22050 Hz mono and concatenated into one WAV.
# Usage:
#   powershell -File scripts/voice-hybrid-tts.ps1 -Text "你好，我是一个 AI Agent" [-SaveWav x.wav] [-NoPlay] [-Ensure]
param(
  [string]$Text,
  [string]$SaveWav,
  [string]$ModelZh = (Join-Path $env:USERPROFILE '.grow-me\tts\piper\zh_CN-huayan-medium.onnx'),
  [string]$ModelEn = (Join-Path $env:USERPROFILE '.grow-me\tts\piper\en_US-lessac-medium.onnx'),
  [double]$LengthScale = 1.0,
  [switch]$NoPlay,
  [switch]$Ensure
)
$ErrorActionPreference = 'Stop'
$targetRate = 22050

function Ensure-Model([string]$model, [string]$lang, [string]$voice, [string]$quality) {
  if (Test-Path $model) { return }
  $base = 'https://hf-mirror.com/rhasspy/piper-voices/resolve/main/' + $lang + '/' + $voice + '/' + $quality + '/' + ([IO.Path]::GetFileNameWithoutExtension($model))
  Write-Host ('DOWNLOAD ' + $base + '.onnx')
  & curl.exe -L -s -o $model ($base + '.onnx')
  & curl.exe -L -s -o ($model + '.json') ($base + '.onnx.json')
}

if ($Ensure) {
  Ensure-Model $ModelZh 'zh/zh_CN' 'zh_CN-huayan' 'medium'
  Ensure-Model $ModelEn 'en/en_US' 'en_US-lessac' 'medium'
}
foreach ($m in @($ModelZh, $ModelEn)) {
  if (-not (Test-Path $m)) { Write-Host ('MODEL_MISSING ' + $m); exit 3 }
  if (-not (Test-Path ($m + '.json'))) { Write-Host ('CONFIG_MISSING ' + ($m + '.json')); exit 3 }
}
if (-not $Text) {
  Write-Host 'usage: voice-hybrid-tts.ps1 -Text "..." [-SaveWav x.wav] [-LengthScale 1.0] [-NoPlay] [-Ensure]'
  exit 0
}

function Read-Wav([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  $i = 12; $fmt = $null; $data = $null
  while ($i -lt $b.Length - 8) {
    $id = [Text.Encoding]::ASCII.GetString($b, $i, 4)
    $sz = [BitConverter]::ToInt32($b, $i + 4)
    $off = $i + 8
    if ($id -eq 'fmt ') {
      $fmt = @{ ch = [BitConverter]::ToInt16($b, $off + 2); rate = [BitConverter]::ToInt32($b, $off + 4); bits = [BitConverter]::ToInt16($b, $off + 14) }
    }
    if ($id -eq 'data') { $data = New-Object byte[] $sz; [Array]::Copy($b, $off, $data, 0, $sz); break }
    $i += 8 + $sz + ($sz % 2)
  }
  if (-not $fmt -or -not $data) { throw ('bad wav: ' + $path) }
  return @{ fmt = $fmt; data = $data }
}

function To-Samples($wav) {
  $ch = $wav.fmt.ch; $bits = $wav.fmt.bits; $data = $wav.data
  $n = [int]($data.Length / (2 * $ch))
  $s = New-Object double[] $n
  for ($k = 0; $k -lt $n; $k++) {
    $sum = 0.0
    for ($c = 0; $c -lt $ch; $c++) {
      $idx = ($k * $ch + $c) * 2
      if ($bits -eq 16) { $sum += [BitConverter]::ToInt16($data, $idx) } else { $sum += ([BitConverter]::ToInt32($data, $idx) / 65536.0) }
    }
    $s[$k] = $sum / $ch
  }
  return @{ rate = $wav.fmt.rate; samples = $s }
}

function Resample($src, [int]$from, [int]$to) {
  $n = [int][Math]::Floor($src.Length * $to / $from)
  $out = New-Object double[] $n
  for ($k = 0; $k -lt $n; $k++) {
    $pos = $k * $from / $to
    $i0 = [int][Math]::Floor($pos)
    $i1 = [Math]::Min($i0 + 1, $src.Length - 1)
    $f = $pos - $i0
    $out[$k] = $src[$i0] * (1 - $f) + $src[$i1] * $f
  }
  return $out
}

function Synth-Piper([string]$text, [string]$model) {
  $in = Join-Path $env:TEMP ('hyb-in-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
  $out = Join-Path $env:TEMP ('hyb-out-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wav')
  [IO.File]::WriteAllText($in, $text + "`n", [Text.UTF8Encoding]::new($false))
  & py -3 -m piper -m $model -c ($model + '.json') -i $in -f $out --length-scale $LengthScale 2>&1 | Out-Null
  $code = $LASTEXITCODE
  Remove-Item $in -Force -ErrorAction SilentlyContinue
  if ($code -ne 0 -or -not (Test-Path $out)) { throw ('piper failed: ' + $text) }
  $w = Read-Wav $out
  Remove-Item $out -Force -ErrorAction SilentlyContinue
  return $w
}

# split into zh / en runs
$runs = New-Object System.Collections.ArrayList
$cur = ''
$mode = ''
foreach ($ch in $Text.ToCharArray()) {
  $isZh = ($ch -match '[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]')
  $m = if ($isZh) { 'zh' } else { 'en' }
  if ($mode -eq '') { $mode = $m }
  if ($m -ne $mode -and $ch -ne ' ') {
    if ($cur.Trim()) { [void]$runs.Add(@{ mode = $mode; text = $cur }) }
    $cur = ''
    $mode = $m
  }
  $cur += $ch
}
if ($cur.Trim()) { [void]$runs.Add(@{ mode = $mode; text = $cur }) }

$all = New-Object System.Collections.Generic.List[double]
foreach ($r in $runs) {
  $model = if ($r.mode -eq 'zh') { $ModelZh } else { $ModelEn }
  $wav = Synth-Piper $r.text $model
  $sm = To-Samples $wav
  $rs = Resample $sm.samples $sm.rate $targetRate
  $all.AddRange([double[]]$rs)
  $sil = New-Object double[] ([int]($targetRate * 0.12))
  $all.AddRange($sil)
}

$outFile = $SaveWav
if (-not $outFile) { $outFile = Join-Path $env:TEMP ('hybrid-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wav') }
$outDir = Split-Path $outFile -Parent
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

$writer = New-Object IO.BinaryWriter ([IO.File]::Create($outFile))
try {
  $dataBytes = New-Object byte[] ($all.Count * 2)
  for ($k = 0; $k -lt $all.Count; $k++) {
    $v = [Math]::Max(-32768, [Math]::Min(32767, [int][Math]::Round($all[$k])))
    $dataBytes[2 * $k] = [byte]($v -band 0xFF)
    $dataBytes[2 * $k + 1] = [byte](($v -shr 8) -band 0xFF)
  }
  $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
  $writer.Write([BitConverter]::GetBytes([int](36 + $dataBytes.Length)))
  $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
  $writer.Write([BitConverter]::GetBytes([int]16))
  $writer.Write([BitConverter]::GetBytes([int16]1))
  $writer.Write([BitConverter]::GetBytes([int16]1))
  $writer.Write([BitConverter]::GetBytes([int]$targetRate))
  $writer.Write([BitConverter]::GetBytes([int]($targetRate * 2)))
  $writer.Write([BitConverter]::GetBytes([int16]2))
  $writer.Write([BitConverter]::GetBytes([int16]16))
  $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
  $writer.Write([BitConverter]::GetBytes([int]$dataBytes.Length))
  $writer.Write($dataBytes)
} finally {
  $writer.Dispose()
}

$voices = @()
foreach ($r in $runs) { $voices += $r.mode }
Write-Host ('VOICE hybrid piper zh+en runs=' + ($voices -join ','))
Write-Host ('TTS_OK ' + $Text)
Write-Host ('WAV ' + $outFile)
if (-not $NoPlay) {
  try { (New-Object System.Media.SoundPlayer $outFile).PlaySync() } catch { Write-Host ('PLAY_FAIL ' + $_.Exception.Message) }
}
