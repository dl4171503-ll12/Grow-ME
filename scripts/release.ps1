param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$Message = ''
)
# Grow Me release helper. Repo push is the FIRST step of a release.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$v = $Version.TrimStart('v', 'V')
if ($v -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid version: $Version (expect Vx.y.z)" }
$tag = "v$v"
$skill = Join-Path $root 'grow-me'

Write-Host "== Grow Me release $tag =="

# 1) version consistency (VERSION / SKILL.md / evals.json)
$sm = Get-Content (Join-Path $skill 'SKILL.md') -Raw
if ($sm -notmatch [regex]::Escape("version: V$v")) {
  throw "grow-me/SKILL.md metadata.version is not V$v - bump it before running release"
}
$ev = Get-Content (Join-Path $skill 'evals\evals.json') -Raw
if ($ev -notmatch ('"version":\s*"V' + [regex]::Escape($v) + '"')) {
  throw "grow-me/evals/evals.json version is not V$v"
}
Set-Content -Path (Join-Path $root 'VERSION') -Value "V$v" -NoNewline
Write-Host "version files: OK (V$v)"

# 2) validate the skill
Write-Host '-- validate-skill --'
node (Join-Path $skill 'scripts\validate-skill.mjs') $skill
if ($LASTEXITCODE -ne 0) { throw 'validate-skill failed - fix the errors above' }

# 3) commit + tag + push (push is the real release step)
Write-Host '-- git commit / tag / push --'
git -C $root add -A
$msg = if ($Message) { $Message } else { "release V$v" }
git -C $root commit -m $msg
if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
git -C $root tag -a $tag -m "Grow Me V$v"
git -C $root push origin HEAD --follow-tags
if ($LASTEXITCODE -ne 0) { throw 'git push failed - check network/proxy/credentials' }

Write-Host ''
Write-Host "REPO UPDATED: $tag" -ForegroundColor Green
Write-Host 'NEXT (only after the repo push): sync the local installed copy'
Write-Host ('  Copy-Item "{0}\*" "$env:USERPROFILE\.agents\skills\grow-me\" -Recurse -Force' -f $skill)
Write-Host '  node "$env:USERPROFILE\.agents\skills\grow-me\scripts\validate-skill.mjs" "$env:USERPROFILE\.agents\skills\grow-me"'
