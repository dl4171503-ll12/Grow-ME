# voice-edge-tts.ps1 - Edge neural TTS (online, no API key) with emoji-aware prosody
# - emojis are NOT read by default; their meaning/count changes rate+pitch of nearby text
# Usage:
#   powershell -File scripts/voice-edge-tts.ps1 -ListPresets
#   powershell -File scripts/voice-edge-tts.ps1 -Text "Carol，您好，我是David的AI，六君！"
#   powershell -File scripts/voice-edge-tts.ps1 -Text "太棒了😊😊！" [-NoEmotion] [-SpeakEmoji]
#   [-Preset a|b|c] [-Voice ...] [-Rate +0%] [-Pitch +0Hz] [-SaveMp3 x.mp3] [-NoPlay]
param(
  [string]$Text,
  [string]$Voice = 'zh-CN-YunxiNeural',
  [ValidateSet('a', 'b', 'c')][string]$Preset,
  [string]$Rate = '+0%',
  [string]$Pitch = '+0Hz',
  [string]$SaveMp3,
  [switch]$NoPlay,
  [switch]$ListVoices,
  [switch]$ListPresets,
  [switch]$NoEmotion,
  [switch]$SpeakEmoji
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
  Write-Host 'usage: voice-edge-tts.ps1 -Text "..." [-Preset a|b|c] [-Rate +0%] [-Pitch +0Hz] [-NoEmotion] [-NoPlay]'
  exit 0
}

$dir = Join-Path $env:USERPROFILE '.grow-me\tts\edge'
$work = Join-Path $env:USERPROFILE '.grow-me\tts\edge\work'
New-Item -ItemType Directory -Force -Path $dir, $work | Out-Null

# ---------------- helpers ----------------
function Parse-Offset([string]$s) {
  if ($s -match '([+-]?\d+(?:\.\d+)?)') { return [double]$Matches[1] }
  return 0.0
}
function Format-Rate([double]$v) {
  $sign = if ($v -lt 0) { '-' } else { '+' }
  return ("{0}{1:0}%" -f $sign, [Math]::Abs([Math]::Round($v)))
}
function Format-Pitch([double]$v) {
  $sign = if ($v -lt 0) { '-' } else { '+' }
  return ("{0}{1:0}Hz" -f $sign, [Math]::Abs([Math]::Round($v)))
}

function Synth-Mp3([string]$text, [string]$rate, [string]$pitch, [string]$outMp3) {
  & py -3 -m edge_tts --voice $Voice "--rate=$rate" "--pitch=$pitch" --text $text --write-media $outMp3 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outMp3) -or (Get-Item $outMp3).Length -lt 500) { throw ('edge synth failed: ' + $text) }
}
function Mp3-To-Wav([string]$mp3, [string]$wav) {
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
  Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path $wav)) { throw ('decode failed: ' + $mp3) }
}
function Read-Wav([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  $i = 12; $fmt = $null; $data = $null
  while ($i -lt $b.Length - 8) {
    $id = [Text.Encoding]::ASCII.GetString($b, $i, 4)
    $sz = [BitConverter]::ToInt32($b, $i + 4); $off = $i + 8
    if ($id -eq 'fmt ') { $fmt = @{ ch = [BitConverter]::ToInt16($b, $off + 2); rate = [BitConverter]::ToInt32($b, $off + 4); bits = [BitConverter]::ToInt16($b, $off + 14) } }
    if ($id -eq 'data') { $data = New-Object byte[] $sz; [Array]::Copy($b, $off, $data, 0, $sz); break }
    $i += 8 + $sz + ($sz % 2)
  }
  if (-not $fmt -or -not $data) { throw ('bad wav: ' + $path) }
  return @{ fmt = $fmt; data = $data }
}
function Write-Wav([string]$path, [double[]]$samples, [int]$rate) {
  $w = New-Object IO.BinaryWriter ([IO.File]::Create($path))
  try {
    $n = $samples.Length
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $w.Write([BitConverter]::GetBytes([int](36 + $n * 2)))
    $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([BitConverter]::GetBytes([int]16))
    $w.Write([BitConverter]::GetBytes([int16]1))
    $w.Write([BitConverter]::GetBytes([int16]1))
    $w.Write([BitConverter]::GetBytes([int]$rate))
    $w.Write([BitConverter]::GetBytes([int]($rate * 2)))
    $w.Write([BitConverter]::GetBytes([int16]2))
    $w.Write([BitConverter]::GetBytes([int16]16))
    $w.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $w.Write([BitConverter]::GetBytes([int]($n * 2)))
    $bytes = New-Object byte[] ($n * 2)
    for ($k = 0; $k -lt $n; $k++) {
      $v = [Math]::Max(-32768, [Math]::Min(32767, [int][Math]::Round($samples[$k])))
      $bytes[2 * $k] = [byte]($v -band 0xFF)
      $bytes[2 * $k + 1] = [byte](($v -shr 8) -band 0xFF)
    }
    $w.Write($bytes)
  } finally { $w.Dispose() }
}

# ---------------- emoji -> emotion table (codepoints only; this file stays pure ASCII) ----------------
# base rate/pitch deltas, scaled by emoji count (1..3)
$emojiClasses = @{
  cheerful  = @(0x1F600..0x1F60F) + @(0x1F929, 0x1F970, 0x1F60D, 0x1F618, 0x1F63A, 0x1F389, 0x1F38A, 0x1F44D, 0x1F44C, 0x1F525, 0x2728, 0x2764, 0x1F31F, 0x1F496, 0x1F49B, 0x1F609)
  sad       = @(0x1F62D, 0x1F622, 0x1F61E, 0x1F614, 0x1F97A, 0x1F62B, 0x1F630, 0x1F625)
  angry     = @(0x1F621, 0x1F620, 0x1F92C, 0x1F4A2, 0x1F624)
  surprised = @(0x1F62E, 0x1F632, 0x1F631, 0x1F92F, 0x1F633, 0x1F628)
  curious   = @(0x2753, 0x2754, 0x2755, 0x2757)
  neutral   = @(0x1F610, 0x1F611)
}
$emojiRegex = '(?:[\uD83C-\uD83E][\uDC00-\uDFFF])|[\u2600-\u27BF]|[\u2B00-\u2BFF]|\uFE0F|\u200D'

function Get-Codepoint([string]$s) {
  if ($s.Length -ge 2 -and [char]::IsHighSurrogate($s[0])) { return [char]::ConvertToUtf32($s, 0) }
  return [int][char]$s[0]
}
function Get-Emotion([string[]]$emojiList) {
  if (-not $emojiList -or $emojiList.Count -eq 0) { return @{ rate = 0; pitch = 0; name = 'none'; count = 0 } }
  foreach ($e in $emojiList) {
    $cp = Get-Codepoint $e
    foreach ($name in $emojiClasses.Keys) {
      if ($cp -in $emojiClasses[$name]) {
        $c = [Math]::Min($emojiList.Count, 3)
        $scale = 1.0 + 0.3 * ($c - 1)
        $rateBase = switch ($name) { 'cheerful' { 6 } 'sad' { -8 } 'angry' { 10 } 'surprised' { 8 } 'curious' { 2 } default { 0 } }
        $pitchBase = switch ($name) { 'cheerful' { 4 } 'sad' { -4 } 'angry' { -6 } 'surprised' { 8 } 'curious' { 5 } default { 0 } }
        return @{ rate = $rateBase * $scale; pitch = $pitchBase * $scale; name = $name; count = $c }
      }
    }
  }
  return @{ rate = 0; pitch = 0; name = 'none'; count = 0 }
}

# ---------------- split text into segments with emoji emotion ----------------
$segments = New-Object System.Collections.ArrayList
$pendingEmoji = @()
if (-not $NoEmotion -and -not $SpeakEmoji) {
  $matches = [regex]::Matches($Text, $emojiRegex)
  $last = 0
  foreach ($m in $matches) {
    $chunk = $Text.Substring($last, $m.Index - $last)
    if ($chunk.Trim()) {
      [void]$segments.Add(@{ text = $chunk; emojis = @() })
      if ($pendingEmoji.Count -gt 0) { $segments[$segments.Count - 1].emojis += $pendingEmoji; $pendingEmoji = @() }
      $segments[$segments.Count - 1].emojis += $m.Value
    } else {
      # consecutive emoji: attach to the previous text segment when possible
      if ($segments.Count -gt 0) { $segments[$segments.Count - 1].emojis += $m.Value }
      else { $pendingEmoji += $m.Value }
    }
    $last = $m.Index + $m.Length
  }
  $tail = $Text.Substring($last)
  if ($tail.Trim()) {
    [void]$segments.Add(@{ text = $tail; emojis = @() })
    if ($pendingEmoji.Count -gt 0) { $segments[$segments.Count - 1].emojis += $pendingEmoji; $pendingEmoji = @() }
  } elseif ($segments.Count -gt 0 -and $pendingEmoji.Count -gt 0) {
    $segments[$segments.Count - 1].emojis += $pendingEmoji; $pendingEmoji = @()
  }
} else {
  [void]$segments.Add(@{ text = $Text; emojis = @() })
}

$baseRate = Parse-Offset $Rate
$basePitch = Parse-Offset $Pitch
$all = New-Object System.Collections.Generic.List[double]
$rateInfo = New-Object System.Collections.ArrayList
$sampleRate = 24000
$tmpWavs = New-Object System.Collections.ArrayList
foreach ($seg in $segments) {
  $em = Get-Emotion $seg.emojis
  $r = $baseRate + $em.rate
  $p = $basePitch + $em.pitch
  $line = ("[{0}] rate={1} pitch={2} :: {3}" -f $em.name, (Format-Rate $r), (Format-Pitch $p), $seg.text.Trim())
  [void]$rateInfo.Add($line)
  $mp3 = Join-Path $work ('seg-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.mp3')
  $wav = [IO.Path]::ChangeExtension($mp3, '.wav')
  Synth-Mp3 $seg.text.Trim() (Format-Rate $r) (Format-Pitch $p) $mp3
  Mp3-To-Wav $mp3 $wav
  $w = Read-Wav $wav
  $ch = $w.fmt.ch; $bits = $w.fmt.bits; $data = $w.data
  if ($bits -ne 16) { throw 'only 16-bit wav supported' }
  $n = [int]($data.Length / (2 * $ch))
  $arr = New-Object double[] $n
  for ($k = 0; $k -lt $n; $k++) {
    $sum = 0.0
    for ($c = 0; $c -lt $ch; $c++) { $sum += [BitConverter]::ToInt16($data, ($k * $ch + $c) * 2) }
    $arr[$k] = $sum / $ch
  }
  $all.AddRange([double[]]$arr)
  $sil = New-Object double[] ([int]($sampleRate * 0.12))
  $all.AddRange($sil)
  [void]$tmpWavs.Add(@{ mp3 = $mp3; wav = $wav })
}

$outWav = $SaveWav
if (-not $outWav) {
  $outWav = $SaveMp3
  if ($outWav) { $outWav = [IO.Path]::ChangeExtension($outWav, '.wav') }
  else { $outWav = Join-Path $dir ('edge-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.wav') }
}
Write-Wav $outWav ([double[]]$all) $sampleRate

$spoken = ($segments | ForEach-Object { $_.text.Trim() }) -join ''
Write-Host ('VOICE edge:' + $Voice + ' rate=' + $Rate)
if ($rateInfo.Count -gt 0) { $rateInfo | ForEach-Object { Write-Host ('EMOTION ' + $_) } }
Write-Host ('EMOJI_READ aloud=' + $(if ($SpeakEmoji) { 'yes' } else { 'no' }))
Write-Host ('TTS_OK ' + $spoken)
Write-Host ('WAV ' + $outWav)

if (-not $NoPlay) {
  try { (New-Object System.Media.SoundPlayer $outWav).PlaySync(); Write-Host 'PLAYED local wav' }
  catch { Write-Host ('PLAY_FAIL ' + $_.Exception.Message) }
}
Get-ChildItem $work -Filter '*.mp3' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $work -Filter '*.wav' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
