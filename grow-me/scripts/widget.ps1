# widget.ps1 - floating command/voice bar (collapsible to a ball), always on top, follows desktops
# - draggable anywhere, clamped to the working area (never over the taskbar)
# - X collapses the bar into a small ball; click the ball to expand again (default: ball)
# - buttons send fixed messages to the DeepSeek Harness window (clipboard paste + Enter)
# - mic: click to record, click again to stop -> local SAPI ASR -> send
# Run: powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/widget.ps1
param(
  [string]$AsrTest
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
# make Python/console output UTF-8 so ASR text is not mojibake
try {
  [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
  $OutputEncoding = [Text.UTF8Encoding]::new($false)
  $env:PYTHONIOENCODING = 'utf-8'
  $env:PYTHONUTF8 = '1'
} catch {}

$root = Join-Path $env:USERPROFILE '.grow-me\widget'
$recDir = Join-Path $root 'rec'
$posFile = Join-Path $root 'pos.json'
$stateFile = Join-Path $root 'state.json'
$instanceFile = Join-Path $root 'instance.json'
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
$ackVoice = ''
if ($cfg -and $cfg.ackVoice) { $ackVoice = [string]$cfg.ackVoice }

. (Join-Path $PSScriptRoot 'widget-native.ps1')

# ---------------- helpers ----------------
function Ch([int[]]$codes) { return (-join ($codes | ForEach-Object { [char]$_ })) }
$ackSent = Ch 0x5DF2, 0x53D1, 0x9001
$ackAudio = Ch 0x6CA1, 0x542C, 0x6E05, 0xFF0C, 0x5DF2, 0x628A, 0x97F3, 0x9891, 0x53D1, 0x8FC7, 0x53BB
$msgAudioOnly = '[voice] ' + (Ch 0x672C, 0x5730, 0x8BC6, 0x522B, 0x4E3A, 0x7A7A, 0xFF0C, 0x97F3, 0x9891, 0x6587, 0x4EF6, 0xFF1A)
$exitLabel = Ch 0x9000, 0x51FA
$logFile = Join-Path $root 'widget.log'
function Write-WLog([string]$m) {
  try { Add-Content -Path $logFile -Value ((Get-Date).ToString('HH:mm:ss') + ' ' + $m) -Encoding UTF8 } catch {}
}
Write-WLog 'widget start'

# ---------------- single instance: keep only the newest widget ----------------
$buildHash = ''
try {
  $parts = @()
  foreach ($f in @((Join-Path $PSScriptRoot 'widget.ps1'), (Join-Path $PSScriptRoot 'widget-native.ps1'), (Join-Path $PSScriptRoot 'widget-commands.json'))) {
    if (Test-Path $f) { $parts += (Get-FileHash -Algorithm SHA256 $f).Hash } else { $parts += 'missing' }
  }
  $buildHash = (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes(($parts -join '|'))))).Hash
} catch { $buildHash = 'unknown' }

$mutex = New-Object System.Threading.Mutex($false, 'Local\GrowMeWidgetSingleton')
# newest wins: kill every other widget process (match by script path, not window title)
$others = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '-File\s+.*widget\.ps1' -and $_.ProcessId -ne $PID }
foreach ($o in $others) { try { Stop-Process -Id $o.ProcessId -Force -ErrorAction Stop; Write-WLog ('killed old widget pid=' + $o.ProcessId) } catch {} }
if ($others) { Start-Sleep -Milliseconds 800 }
$haveLock = $false
$deadline = (Get-Date).AddSeconds(12)
while (-not $haveLock -and (Get-Date) -lt $deadline) {
  try { $haveLock = $mutex.WaitOne(600) }
  catch [System.Threading.AbandonedMutexException] { $haveLock = $true }
  catch { Start-Sleep -Milliseconds 300 }
}
if (-not $haveLock) { Write-WLog 'cannot get widget singleton lock; exit'; exit 0 }
$instData = @{ pid = $PID; buildHash = $buildHash; started = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
Set-Content -Path $instanceFile -Value $instData -Encoding UTF8
Write-WLog ('singleton acquired pid=' + $PID + ' hash=' + $buildHash.Substring(0, 12))
function Get-DshWindows {
  $dshPids = @{}
  Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | ForEach-Object { $dshPids[$_.Id] = $true }
  $list = @()
  foreach ($line in [GmWin]::Windows()) {
    $parts = $line -split '\|', 3
    if ($parts.Count -lt 3) { continue }
    $wpid = [int]$parts[1]
    if (-not $dshPids.ContainsKey($wpid)) { continue }
    $list += [pscustomobject]@{ hwnd = [IntPtr]([int64]$parts[0]); title = $parts[2]; pid = $wpid }
  }
  return $list
}

function Get-HarnessWindow {
  $wins = Get-DshWindows
  if (-not $wins -or $wins.Count -eq 0) { return $null }
  $fg = [GmWin]::GetForegroundWindow()
  $hit = $wins | Where-Object { $_.hwnd -eq $fg } | Select-Object -First 1
  if ($hit) { return $hit }
  if ($script:dshLast -and $script:dshLast -ne [IntPtr]::Zero) {
    $hit = $wins | Where-Object { $_.hwnd -eq $script:dshLast } | Select-Object -First 1
    if ($hit) { return $hit }
  }
  return ($wins | Select-Object -First 1)
}

function Send-Harness([string]$text, [switch]$DryRun) {
  $t = Get-HarnessWindow
  if (-not $t) { Write-WLog 'send: no harness window'; return $false }
  if ($DryRun) { Write-WLog ('send dryrun to [' + $t.title + ']'); return $true }
  try {
    # the DSH window may live on another virtual desktop (DWM cloaked) -> bring it here first
    [void][GmVd]::FollowCurrent($t.hwnd)
    Start-Sleep -Milliseconds 150
    [void][GmWin]::ShowWindow($t.hwnd, 9)
    [void][GmWin]::SetForegroundWindow($t.hwnd)
    Start-Sleep -Milliseconds 400
    $fg = [GmWin]::GetForegroundWindow()
    if ($fg -ne $t.hwnd) {
      [void][GmVd]::FollowCurrent($t.hwnd)
      Start-Sleep -Milliseconds 250
      [void][GmWin]::SetForegroundWindow($t.hwnd)
      Start-Sleep -Milliseconds 400
      $fg = [GmWin]::GetForegroundWindow()
    }
    if ($fg -ne $t.hwnd) {
      Write-WLog ('abort: target not foreground fg=' + $fg + ' target=' + $t.hwnd)
      return $false
    }
    Write-WLog ('target foreground ok: ' + $t.title)
    # click into this conversation's input box (bottom-centre) so it does not go elsewhere
    $r = [GmWin+RECT]::new()
    if ([GmWin]::GetWindowRect($t.hwnd, [ref]$r)) {
      $cx = $r.L + [int](($r.R - $r.L) / 2)
      $cy = $r.B - 80
      [void][GmWin]::SetCursorPos($cx, $cy)
      Start-Sleep -Milliseconds 150
      [GmWin]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds 60
      [GmWin]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
      Start-Sleep -Milliseconds 250
    }
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
    Write-WLog ('sent to [' + $t.title + ']: ' + $text)
    return $true
  } catch {
    Write-WLog ('send error: ' + $_.Exception.Message)
    return $false
  }
}

function Speak-Ack([string]$text) {
  if (-not $ackVoice) { return }   # quiet by default: no "sent" voice confirmation
  $edge = Join-Path $PSScriptRoot 'voice-edge-tts.ps1'
  if (-not (Test-Path $edge)) { return }
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $edge, '-Preset', $ackVoice, '-Text', $text) -WindowStyle Hidden | Out-Null
}

function Run-Asr([string]$wav) {
  # 1) SenseVoice (sherpa-onnx, Chinese-optimised, best local accuracy)
  $sv = Join-Path $PSScriptRoot 'asr-sensevoice.py'
  $svDir = Join-Path $env:USERPROFILE '.grow-me\asr\sensevoice'
  if ((Test-Path $sv) -and (Test-Path (Join-Path $svDir 'model.int8.onnx'))) {
    try {
      $out = & py -3 -X utf8 $sv $wav $svDir 2>&1
      $line = ($out | Where-Object { $_ -like 'ASR_TEXT *' } | Select-Object -First 1)
      if ($line) {
        $text = ($line -replace '^ASR_TEXT ', '').Trim()
        Write-WLog ('asr(sensevoice): ' + $text)
        return $text
      }
      Write-WLog 'asr(sensevoice): empty'
    } catch {
      Write-WLog ('asr(sensevoice) error: ' + $_.Exception.Message)
    }
  }
  # 2) Whisper (local, offline fallback)
  $whisper = Join-Path $PSScriptRoot 'asr-whisper.py'
  $modelDir = Join-Path $env:USERPROFILE '.grow-me\asr\faster-whisper-base'
  if ((Test-Path $whisper) -and (Test-Path (Join-Path $modelDir 'model.bin'))) {
    try {
      $out = & py -3 -X utf8 $whisper $wav $modelDir 2>&1
      $line = ($out | Where-Object { $_ -like 'ASR_TEXT *' } | Select-Object -First 1)
      if ($line) {
        $text = ($line -replace '^ASR_TEXT ', '').Trim()
        Write-WLog ('asr(whisper): ' + $text)
        return $text
      }
      Write-WLog 'asr(whisper): empty'
    } catch {
      Write-WLog ('asr(whisper) error: ' + $_.Exception.Message)
    }
  }
  # 3) SAPI fallback (raw -> peak -> compressed)
  $asr = Join-Path $PSScriptRoot 'widget-asr.ps1'
  if (-not (Test-Path $asr)) { return '' }
  function Try-Asr([string]$target, [string]$tag) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $asr -Wav $target 2>&1
    $line = ($out | Where-Object { $_ -like 'ASR_TEXT *' } | Select-Object -First 1)
    if ($line) {
      $text = ($line -replace '^ASR_TEXT ', '').Trim()
      Write-WLog ('asr(' + $tag + '): ' + $text)
      return $text
    }
    return ''
  }
  $text = Try-Asr $wav 'raw'
  if ($text) { return $text }
  $loud = Join-Path $PSScriptRoot 'voice-loudness.py'
  if (Test-Path $loud) {
    $peakWav = $wav -replace '\.wav$', '-peak.wav'
    try { & py -3 -X utf8 $loud $wav $peakWav peak 2>&1 | Out-Null } catch {}
    if ((Test-Path $peakWav) -and ((Get-Item $peakWav).Length -gt 1000)) {
      $text = Try-Asr $peakWav 'peak'
      if ($text) { return $text }
    }
    $procWav = $wav -replace '\.wav$', '-proc.wav'
    try { & py -3 -X utf8 $loud $wav $procWav 2>&1 | Out-Null } catch {}
    if ((Test-Path $procWav) -and ((Get-Item $procWav).Length -gt 1000)) {
      $text = Try-Asr $procWav 'compressed'
      if ($text) { return $text }
    }
  }
  Write-WLog 'asr: empty (whisper+sapi all failed)'
  return ''
}

# ---------------- position / state ----------------
if ($AsrTest) {
  $text = Run-Asr $AsrTest
  Write-Output ('ASR: ' + $text)
  exit 0
}
$baseX = 80; $baseY = 80
if (Test-Path $posFile) {
  try { $p = Get-Content -Raw $posFile | ConvertFrom-Json; $baseX = [int]$p.x; $baseY = [int]$p.y } catch {}
}
$screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
$wa = $screen.WorkingArea
$baseX = [Math]::Max($wa.Left, [Math]::Min($baseX, $wa.Right - 380))
$baseY = [Math]::Max($wa.Top, [Math]::Min($baseY, $wa.Bottom - 90))

# always start collapsed (the ball is the default; expanded state is not persisted on purpose)
$collapsedDefault = $true

function Save-Pos {
  try {
    $pos = @{ x = [int]$win.Left; y = [int]$win.Top } | ConvertTo-Json -Compress
    Set-Content -Path $posFile -Value $pos -Encoding UTF8
  } catch {}
}
function Save-State([bool]$collapsed) {
  try {
    $s = @{ collapsed = $collapsed } | ConvertTo-Json -Compress
    Set-Content -Path $stateFile -Value $s -Encoding UTF8
  } catch {}
}

# ---------------- UI ----------------
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
    <Grid>
      <Border x:Name="BarPanel">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <StackPanel x:Name="CmdPanel" Orientation="Horizontal" VerticalAlignment="Center"/>
          <Border Width="1" Height="20" Background="#FF3A3F47" Margin="4,0"/>
          <Button x:Name="MicBtn" Content="Mic" Width="52" Background="#FF1F6F4A"/>
          <TextBlock x:Name="Status" Text="" Foreground="#FFB8C0CC" FontSize="11" VerticalAlignment="Center" Margin="6,0" MaxWidth="220"/>
          <Button x:Name="MinBtn" Content="X" Width="24" Background="#FF3A2020" Margin="2,0"/>
        </StackPanel>
      </Border>
      <Border x:Name="BallPanel" Width="30" Height="30" CornerRadius="15" Background="#E61F6F4A" BorderBrush="#FF3A3F47" BorderThickness="1" Visibility="Collapsed">
        <TextBlock Text="G" Foreground="#FFF0F0F0" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
    </Grid>
  </Border>
</Window>
"@
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
$win = [Windows.Markup.XamlReader]::Load($reader)
$rootBorder = $win.FindName('RootBorder')
$barPanel = $win.FindName('BarPanel')
$ballPanel = $win.FindName('BallPanel')
$cmdPanel = $win.FindName('CmdPanel')
$micBtn = $win.FindName('MicBtn')
$status = $win.FindName('Status')
$minBtn = $win.FindName('MinBtn')
$win.Topmost = $true
$win.Add_Closed({
    try { if ($script:haveLock) { $mutex.ReleaseMutex() } } catch {}
    try { if (Test-Path $instanceFile) { Remove-Item -LiteralPath $instanceFile -Force } } catch {}
    Write-WLog 'widget closed'
  })

function Set-Collapsed([bool]$collapsed) {
  if ($collapsed) {
    $barPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $ballPanel.Visibility = [System.Windows.Visibility]::Visible
  } else {
    $ballPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $barPanel.Visibility = [System.Windows.Visibility]::Visible
  }
  Save-State $collapsed
}
Set-Collapsed $collapsedDefault
Write-WLog ('start collapsed=' + $collapsedDefault)

# drag: move window; a click without movement on the ball expands it
$dragState = @{ left = 0.0; top = 0.0 }
$rootBorder.Add_MouseLeftButtonDown({
    try {
      $dragState.left = $win.Left; $dragState.top = $win.Top
      $win.DragMove()
      $dx = [Math]::Abs($win.Left - $dragState.left)
      $dy = [Math]::Abs($win.Top - $dragState.top)
      if (($dx + $dy) -gt 3) { Save-Pos } else { Save-Pos }
    } catch {}
  })
$ballPanel.Add_MouseLeftButtonDown({
    try {
      $dragState.left = $win.Left; $dragState.top = $win.Top
      $win.DragMove()
      $dx = [Math]::Abs($win.Left - $dragState.left)
      $dy = [Math]::Abs($win.Top - $dragState.top)
      if (($dx + $dy) -le 3) { Set-Collapsed $false } else { Save-Pos }
    } catch {}
  })

# command buttons
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
$micBtn.Add_Click({
    try {
    if (-not [GmRec]::IsRecording) {
      $script:recWav = Join-Path $recDir ('rec-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.wav')
      $r = [GmRec]::Start()
      if ($r -like 'RECORDING*') {
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
          $msg = '[voice] ' + $text + ' | audio: ' + $script:recWav
          $sent = Send-Harness $msg
          $status.Text = $(if ($sent) { 'sent: ' + $text } else { 'no window: ' + $text })
          if ($sent) { Speak-Ack $ackSent }
        } else {
          $msg = '[voice] (asr empty) | audio: ' + $script:recWav
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

# X = collapse into ball (not exit)
$minBtn.Add_Click({
    try { Set-Collapsed $true } catch { Write-WLog ('min error: ' + $_.Exception.Message) }
  })

# right click -> Exit
$menu = New-Object System.Windows.Controls.ContextMenu
$exitItem = New-Object System.Windows.Controls.MenuItem
$exitItem.Header = $exitLabel
$exitItem.Add_Click({
    try { Save-Pos; Save-State ([bool]($ballPanel.Visibility -eq [System.Windows.Visibility]::Visible)); if ([GmRec]::IsRecording) { [void][GmRec]::Stop((Join-Path $recDir 'last.wav')) }; $win.Close() } catch {}
  })
[void]$menu.Items.Add($exitItem)
$rootBorder.ContextMenu = $menu

# keep-on-top watchdog + follow active virtual desktop + remember last DSH window
$script:dshLast = [IntPtr]::Zero
$script:watchLogged = $false
$script:topTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:topTimer.Interval = [TimeSpan]::FromMilliseconds(1200)
$script:topTimer.Add_Tick({
    try {
      $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
      if ($hwnd -eq [IntPtr]::Zero) { return }
      [void][GmWin]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, 0x0013)
      [void][GmVd]::FollowCurrent($hwnd)
      $fg = [GmWin]::GetForegroundWindow()
      $wins = Get-DshWindows
      if ($wins | Where-Object { $_.hwnd -eq $fg }) { $script:dshLast = $fg }
      if (-not $script:watchLogged) {
        $script:watchLogged = $true
        Write-WLog ('watchdog: topmost=' + [GmVd]::IsTopmost($hwnd) + ' vd=' + [GmVd]::Status($hwnd) + ' dsh_windows=' + @($wins).Count)
      }
    } catch {}
  })
$script:topTimer.Start()

[void]$win.ShowDialog()
