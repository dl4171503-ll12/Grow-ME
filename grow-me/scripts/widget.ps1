# widget.ps1 - floating always-on-top command/voice bar for grow-me (Windows, no deps)
# - draggable anywhere on screen, never over the taskbar (clamped to working area)
# - command buttons send fixed messages to the DeepSeek Harness window (clipboard paste + Enter)
# - mic button: click to record, click again to stop -> local SAPI ASR -> send text to Harness
# Run: powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/widget.ps1
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$root = Join-Path $env:USERPROFILE '.grow-me\widget'
$recDir = Join-Path $root 'rec'
$posFile = Join-Path $root 'pos.json'
New-Item -ItemType Directory -Force -Path $recDir | Out-Null
$cmdFile = Join-Path $PSScriptRoot 'widget-commands.json'
$cfg = $null
if (Test-Path $cmdFile) { $cfg = (Get-Content -Raw -Encoding UTF8 $cmdFile | ConvertFrom-Json) }
$commands = @()
if ($cfg -and $cfg.buttons) { $commands = $cfg.buttons } else {
  $commands = @(@{ label = 'Command A'; text = 'Command A' }, @{ label = 'Command B'; text = 'Command B' })
}
$micSeconds = 60
if ($cfg -and $cfg.micSeconds) { $micSeconds = [int]$cfg.micSeconds }
$ackVoice = 'youth'
if ($cfg -and $cfg.ackVoice) { $ackVoice = [string]$cfg.ackVoice }

. (Join-Path $PSScriptRoot 'widget-native.ps1')

# ---------------- helpers ----------------
function Ch([int[]]$codes) { return (-join ($codes | ForEach-Object { [char]$_ })) }
$ackSent = Ch 0x5DF2, 0x53D1, 0x9001                                   # 已发送
$ackAudio = Ch 0x6CA1, 0x542C, 0x6E05, 0xFF0C, 0x5DF2, 0x628A, 0x97F3, 0x9891, 0x53D1, 0x8FC7, 0x53BB  # 没听清，已把音频发过去
$msgAudioOnly = '[voice] ' + (Ch 0x672C, 0x5730, 0x8BC6, 0x522B, 0x4E3A, 0x7A7A, 0xFF0C, 0x97F3, 0x9891, 0x6587, 0x4EF6, 0xFF1A)
$logFile = Join-Path $root 'widget.log'
function Write-WLog([string]$m) {
  try { Add-Content -Path $logFile -Value ((Get-Date).ToString('HH:mm:ss') + ' ' + $m) -Encoding UTF8 } catch {}
}
Write-WLog 'widget start'

function Get-HarnessHandle {
  $procs = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
  if ($procs) { return ($procs | Select-Object -First 1).MainWindowHandle }
  return [IntPtr]::Zero
}

function Send-Harness([string]$text, [switch]$DryRun) {
  $h = Get-HarnessHandle
  if ($h -eq [IntPtr]::Zero) { Write-WLog 'send: no harness window'; return $false }
  if ($DryRun) { Write-WLog ('send dryrun: ' + $text); return $true }
  try {
    [void][GmWin]::ShowWindow($h, 9)
    [void][GmWin]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 300
    $fg = [GmWin]::GetForegroundWindow()
    if ($fg -ne $h) { Write-WLog ('focus mismatch fg=' + $fg + ' target=' + $h) }
    $okClip = $false
    for ($i = 0; $i -lt 3 -and -not $okClip; $i++) {
      try { [System.Windows.Forms.Clipboard]::SetText($text); $okClip = $true }
      catch { Start-Sleep -Milliseconds 150 }
    }
    if (-not $okClip) { Write-WLog 'send: clipboard fail'; return $false }
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 220
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 250
    Write-WLog ('sent: ' + $text)
    return $true
  } catch {
    Write-WLog ('send error: ' + $_.Exception.Message)
    return $false
  }
}

function Speak-Ack([string]$text) {
  $edge = Join-Path $PSScriptRoot 'voice-edge-tts.ps1'
  if (-not (Test-Path $edge)) { return }
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $edge, '-Preset', $ackVoice, '-Text', $text) -WindowStyle Hidden | Out-Null
}

function Run-Asr([string]$wav) {
  $asr = Join-Path $PSScriptRoot 'widget-asr.ps1'
  if (-not (Test-Path $asr)) { return '' }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $asr -Wav $wav 2>&1
  $line = ($out | Where-Object { $_ -like 'ASR_TEXT *' } | Select-Object -First 1)
  if ($line) { return ($line -replace '^ASR_TEXT ', '').Trim() }
  return ''
}

# ---------------- UI ----------------
$baseX = 80; $baseY = 80
if (Test-Path $posFile) {
  try { $p = Get-Content -Raw $posFile | ConvertFrom-Json; $baseX = [int]$p.x; $baseY = [int]$p.y } catch {}
}
$screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
$wa = $screen.WorkingArea
$baseX = [Math]::Max($wa.Left, [Math]::Min($baseX, $wa.Right - 380))
$baseY = [Math]::Max($wa.Top, [Math]::Min($baseY, $wa.Bottom - 90))

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="grow-me widget" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize"
        Left="$baseX" Top="$baseY" SizeToContent="WidthAndHeight">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="3,0"/>
      <Setter Property="Padding" Value="8,4"/>
      <Setter Property="Background" Value="#FF2B2F36"/>
      <Setter Property="Foreground" Value="#FFF0F0F0"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Border x:Name="RootBorder" CornerRadius="12" Background="#E614161B" BorderBrush="#FF3A3F47" BorderThickness="1" Padding="6,4">
    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
      <StackPanel x:Name="CmdPanel" Orientation="Horizontal" VerticalAlignment="Center"/>
      <Border Width="1" Height="20" Background="#FF3A3F47" Margin="4,0"/>
      <Button x:Name="MicBtn" Content="Mic" Width="52" Background="#FF1F6F4A"/>
      <TextBlock x:Name="Status" Text="" Foreground="#FFB8C0CC" FontSize="11" VerticalAlignment="Center" Margin="6,0" MaxWidth="220"/>
      <Button x:Name="CloseBtn" Content="X" Width="24" Background="#FF3A2020" Margin="2,0"/>
    </StackPanel>
  </Border>
</Window>
"@
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$win = [Windows.Markup.XamlReader]::Load($reader)
$rootBorder = $win.FindName('RootBorder')
$cmdPanel = $win.FindName('CmdPanel')
$micBtn = $win.FindName('MicBtn')
$status = $win.FindName('Status')
$win.Topmost = $true

$rootBorder.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$win.Add_MouseLeftButtonUp({
    try {
      $pos = @{ x = [int]$win.Left; y = [int]$win.Top } | ConvertTo-Json -Compress
      Set-Content -Path $posFile -Value $pos -Encoding UTF8
    } catch {}
  })

foreach ($c in $commands) {
  $btn = New-Object System.Windows.Controls.Button
  $btn.Content = [string]$c.label
  $btn.Tag = [string]$c.text
  $btn.Add_Click({
      param($sender, $e)
      try {
        $cmd = [string]$sender.Tag
        $ok = Send-Harness $cmd
        $status.Text = $(if ($ok) { 'sent' } else { 'no window' })
        if ($ok) { Speak-Ack $ackSent }
      } catch {
        Write-WLog ('cmd handler error: ' + $_.Exception.Message)
        try { $status.Text = 'error' } catch {}
      }
    })
  [void]$cmdPanel.Children.Add($btn)
}

$script:recWav = $null
$script:recStart = $null
$micBtn.Add_Click({
    try {
    if (-not [GmRec]::IsRecording) {
      $script:recWav = Join-Path $recDir ('rec-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.wav')
      $r = [GmRec]::Start()
      if ($r -like 'RECORDING*') {
        $script:recStart = Get-Date
        $micBtn.Content = 'Stop'
        $micBtn.Background = '#FF8A2B2B'
        $status.Text = 'listening...'
      } else {
        $status.Text = $r
      }
    } else {
      $r = [GmRec]::Stop($script:recWav)
      $micBtn.Content = 'Mic'
      $micBtn.Background = '#FF1F6F4A'
      if ($r -like 'SAVED*') {
        $status.Text = 'recognizing...'
        $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
        $text = Run-Asr $script:recWav
        if ($text) {
          $sent = Send-Harness $text
          $status.Text = $(if ($sent) { 'sent: ' + $text } else { 'no window: ' + $text })
          if ($sent) { Speak-Ack $ackSent }
        } else {
          $msg = $msgAudioOnly + ' ' + $script:recWav
          $sent = Send-Harness $msg
          $status.Text = $(if ($sent) { 'sent (audio only)' } else { 'no window' })
          if ($sent) { Speak-Ack $ackAudio }
        }
      } else {
        $status.Text = $r
      }
    }
    } catch {
      Write-WLog ('mic handler error: ' + $_.Exception.Message)
      try { $status.Text = 'mic error'; $micBtn.Content = 'Mic' } catch {}
    }
  })

$win.FindName('CloseBtn').Add_Click({
    try {
      $pos = @{ x = [int]$win.Left; y = [int]$win.Top } | ConvertTo-Json -Compress
      Set-Content -Path $posFile -Value $pos -Encoding UTF8
    } catch {}
    if ([GmRec]::IsRecording) { try { [void][GmRec]::Stop((Join-Path $recDir 'last.wav')) } catch {} }
    $win.Close()
  })

[void]$win.ShowDialog()
