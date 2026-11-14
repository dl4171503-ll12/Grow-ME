param([string]$OutDir = '')
# Build a distributable .skill package (zip with a top-level grow-me/ folder)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$v = (Get-Content (Join-Path $root 'VERSION') -Raw).Trim()
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$dst = Join-Path $OutDir ("grow-me-{0}.skill" -f $v)
if (Test-Path $dst) { Remove-Item $dst -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  (Join-Path $root 'grow-me'), $dst,
  [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host ("packed: {0} ({1:N1} KB)" -f $dst, ((Get-Item $dst).Length / 1KB))
