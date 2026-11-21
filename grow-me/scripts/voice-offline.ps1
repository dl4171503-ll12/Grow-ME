<#
 voice-offline.ps1 - offline voice shell for the grow-me voice agent (no API keys)
 Uses Windows SAPI (System.Speech) for offline TTS and offline speech recognition,
 and calls the local voice-agent HTTP engine for the LLM/tools/events.

 Modes:
   -Text "..."        speak text via Windows SAPI (offline TTS)
   -SaveWav path      when used with -Text, write WAV instead of playing (evidence)
   -Loop              mic -> offline SAPI recognizer -> POST /api/turn -> SAPI speak
   -EngineUrl url     engine base url (default http://127.0.0.1:8180)
   -Seconds n         recognition timeout per turn (default 10)
#>
param(
  [string]$Text,
  [switch]$Loop,
  [string]$SaveWav,
  [string]$EngineUrl = 'http://127.0.0.1:8180',
  [int]$Seconds = 10
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech

$syn = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice = $syn.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
if (-not $voice) { $voice = $syn.GetInstalledVoices() | Select-Object -First 1 }
if ($voice) {
  try { $syn.SelectVoice($voice.VoiceInfo.Name) } catch {}
  Write-Host ("VOICE " + $voice.VoiceInfo.Name + " " + $voice.VoiceInfo.Culture)
}
$syn.Rate = 0
$syn.Volume = 100

function Speak-Text([string]$t) {
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
