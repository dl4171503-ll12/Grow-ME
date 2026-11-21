<#
 voice-offline.ps1 - offline voice shell for the grow-me voice agent (no API keys)
 Uses offline neural TTS (Piper zh+en hybrid by default, WinRT/SAPI fallback) and
 Windows SAPI offline speech recognition, and calls the local voice-agent engine.

 Modes:
   -Text "..."        speak text offline
   -SaveWav path      when used with -Text, write WAV instead of playing (evidence)
   -Loop              mic -> offline SAPI recognizer -> POST /api/turn -> TTS speak
   -Voice name        WinRT voice fallback name (default "Microsoft Yaoyao")
   -TtsEngine hybrid|piper|winrt|sapi  TTS backend (default hybrid)
   -LengthScale n     Piper speaking speed (default 1.0; >1 slower)
   -EngineUrl url     engine base url (default http://127.0.0.1:8180)
   -Seconds n         recognition timeout per turn (default 10)
#>
param(
  [string]$Text,
  [switch]$Loop,
  [string]$SaveWav,
  [string]$Voice = 'Microsoft Yaoyao',
  [ValidateSet('hybrid', 'piper', 'winrt', 'sapi')][string]$TtsEngine = 'hybrid',
  [double]$LengthScale = 1.0,
  [string]$EngineUrl = 'http://127.0.0.1:8180',
  [int]$Seconds = 10
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$ttsDir = Join-Path $env:USERPROFILE '.grow-me\tts\piper'
$winrtScript = Join-Path $PSScriptRoot 'voice-winrt-tts.ps1'
$piperScript = Join-Path $PSScriptRoot 'voice-piper-tts.ps1'
$hybridScript = Join-Path $PSScriptRoot 'voice-hybrid-tts.ps1'
$piperModel = Join-Path $ttsDir 'zh_CN-huayan-medium.onnx'
$enModel = Join-Path $ttsDir 'en_US-lessac-medium.onnx'
$piperReady = (Test-Path $piperModel) -and (Test-Path $piperScript)
$hybridReady = $piperReady -and (Test-Path $enModel) -and (Test-Path $hybridScript)

$syn = New-Object System.Speech.Synthesis.SpeechSynthesizer
$sapiVoice = $syn.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
if (-not $sapiVoice) { $sapiVoice = $syn.GetInstalledVoices() | Select-Object -First 1 }
if ($sapiVoice) { try { $syn.SelectVoice($sapiVoice.VoiceInfo.Name) } catch {} }
$syn.Rate = 0
$syn.Volume = 100
if ($TtsEngine -eq 'hybrid' -and $hybridReady) { Write-Host 'VOICE piper hybrid (zh huayan + en lessac, mixed language)' }
elseif ($TtsEngine -eq 'piper' -and $piperReady) { Write-Host 'VOICE piper:zh_CN-huayan-medium (neural)' }
elseif ($TtsEngine -eq 'hybrid' -or $TtsEngine -eq 'piper') { Write-Host ('PIPER_NOT_READY -> fallback winrt') }
elseif ($TtsEngine -eq 'winrt') { Write-Host ("VOICE " + $Voice + " (winrt natural)") }
elseif ($sapiVoice) { Write-Host ("VOICE " + $sapiVoice.VoiceInfo.Name + " " + $sapiVoice.VoiceInfo.Culture) }

function Speak-Text([string]$t) {
  if ($TtsEngine -eq 'hybrid' -and $hybridReady) {
    try {
      if ($SaveWav) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $hybridScript -Text $t -SaveWav $SaveWav -NoPlay -LengthScale $LengthScale | Out-Null
      } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $hybridScript -Text $t -LengthScale $LengthScale | Out-Null
      }
      return
    } catch {
      Write-Host ('HYBRID_FALLBACK ' + $_.Exception.Message)
    }
  }
  if ($TtsEngine -eq 'piper' -and $piperReady) {
    try {
      if ($SaveWav) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $piperScript -Text $t -SaveWav $SaveWav -NoPlay -LengthScale $LengthScale | Out-Null
      } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $piperScript -Text $t -LengthScale $LengthScale | Out-Null
      }
      return
    } catch {
      Write-Host ('PIPER_FALLBACK ' + $_.Exception.Message)
    }
  }
  if ($TtsEngine -eq 'winrt' -and (Test-Path $winrtScript)) {
    try {
      if ($SaveWav) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $winrtScript -Text $t -Voice $Voice -SaveWav $SaveWav -NoPlay | Out-Null
      } else {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $winrtScript -Text $t -Voice $Voice | Out-Null
      }
      return
    } catch {
      Write-Host ('WINRT_FALLBACK ' + $_.Exception.Message)
    }
  }
  if ($SaveWav) {
    $syn.SetOutputToWaveFile($SaveWav)
    $syn.Speak($t)
    $syn.SetOutputToNull()
  } else {
    $syn.Speak($t)
  }
}

if ($Text) {
  Speak-Text $Text
  Write-Host ("TTS_OK " + $Text)
  if ($SaveWav) { Write-Host ("WAV " + $SaveWav) }
  exit 0
}

if (-not $Loop) {
  Write-Host 'usage: voice-offline.ps1 -Text "..." [-SaveWav file.wav] | -Loop [-EngineUrl url] [-Seconds n]'
  exit 0
}

try {
  $h = Invoke-RestMethod -Uri ($EngineUrl + '/api/health') -TimeoutSec 5
} catch {
  Write-Host ("ENGINE_DOWN " + $EngineUrl + " (start: node scripts/voice-agent.mjs serve --port 8180)")
  exit 2
}
Write-Host ("ENGINE_OK " + $h.agent + " / " + $h.llm)

$recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Where-Object { $_.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
if (-not $recognizer) { $recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Select-Object -First 1 }
if (-not $recognizer) { Write-Host 'NO_RECOGNIZER (install a Windows speech language pack)'; exit 3 }
$rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine $recognizer
$rec.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
$rec.SetInputToDefaultAudioDevice()
Write-Host ("RECOGNIZER " + $recognizer.Name + " " + $recognizer.Culture)
Write-Host 'LISTENING (say the stop word or press Ctrl+C)'

while ($true) {
  $r = $rec.Recognize([TimeSpan]::FromSeconds($Seconds))
  if (-not $r) { continue }
  $said = $r.Text
  if (-not $said) { continue }
  Write-Host ("YOU " + $said)
  if ($said -match 'exit|quit|stop' -or $said -match '\u9000\u51fa|\u7ed3\u675f') { break }
  $body = @{ text = $said } | ConvertTo-Json -Compress
  try {
    $turn = Invoke-RestMethod -Uri ($EngineUrl + '/api/turn') -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
  } catch {
    Write-Host 'TURN_FAIL'
    continue
  }
  $reply = [string]$turn.reply
  Write-Host ("BOT " + $reply)
  if ($reply) { Speak-Text $reply }
}

$rec.Dispose()
$syn.Dispose()
Write-Host 'BYE'
