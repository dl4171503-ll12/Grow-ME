# widget-asr.ps1 - offline ASR for a WAV file using Windows SAPI (zh-CN recognizer)
# usage: powershell -File scripts/widget-asr.ps1 -Wav rec.wav [-Seconds 15]
param(
  [Parameter(Mandatory = $true)][string]$Wav,
  [int]$Seconds = 15
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
if (-not (Test-Path $Wav)) { Write-Host 'ASR_WAV_MISSING'; exit 2 }
$recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Where-Object { $_.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
if (-not $recognizer) { $recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers() | Select-Object -First 1 }
if (-not $recognizer) { Write-Host 'ASR_NO_RECOGNIZER'; exit 3 }
$rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine $recognizer
$rec.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
$rec.SetInputToWaveFile((Resolve-Path $Wav).Path)
$text = ''
try {
  $r = $rec.Recognize([TimeSpan]::FromSeconds($Seconds))
  if ($r) { $text = $r.Text }
} catch {
  Write-Host ('ASR_ERROR ' + $_.Exception.Message)
  $rec.Dispose()
  exit 4
}
$rec.Dispose()
if (-not $text) { Write-Host 'ASR_EMPTY'; exit 5 }
Write-Host ('ASR_TEXT ' + $text)
