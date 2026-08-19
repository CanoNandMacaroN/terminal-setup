$ErrorActionPreference = "Continue"
$Failures = 0
$Warnings = 0

function Test-Required([string]$Name) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($Command) { Write-Host "[OK] $Name`: $($Command.Source)" }
    else { Write-Host "[WARN] $Name is missing"; $script:Failures++ }
}

function Test-Optional([string]$Name) {
    if (Get-Command $Name -ErrorAction SilentlyContinue) { Write-Host "[OK] $Name`: available" }
    else { Write-Host "[WARN] $Name`: optional, not installed"; $script:Warnings++ }
}

Write-Host "== Platform =="
Write-Host "[INFO] Native Windows / $env:PROCESSOR_ARCHITECTURE / workstation profile"

Write-Host "`n== Required commands =="
@("git", "chezmoi", "pixi") | ForEach-Object { Test-Required $_ }

Write-Host "`n== Workflow tools =="
@("starship", "fnm", "node", "corepack", "pnpm", "uv", "fzf", "zoxide", "jq", "rg", "fd", "bat", "eza", "lazygit", "yazi") |
    ForEach-Object { Test-Optional $_ }

Write-Host "`n== Package manifests =="
@(".myshell\pixi-tools.toml", ".myshell\uv-tools.toml") | ForEach-Object {
    $Manifest = Join-Path $HOME $_
    if (Test-Path $Manifest) { Write-Host "[OK] $Manifest`: present" }
    else { Write-Host "[WARN] $Manifest`: missing"; $script:Warnings++ }
}

Write-Host "`n== Chezmoi =="
if (-not (Get-Command chezmoi -ErrorAction SilentlyContinue)) {
    Write-Host "[WARN] chezmoi source directory cannot be checked"
    $Failures++
} else {
    $SourceDir = (& chezmoi source-path 2>$null)
}
if ($SourceDir -and (Test-Path $SourceDir)) {
    Write-Host "[OK] source: $SourceDir"
    & chezmoi verify --exclude scripts *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "[OK] managed file state verified" }
    else { Write-Host "[WARN] managed files differ"; $Warnings++ }
} elseif (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    Write-Host "[WARN] chezmoi source directory is not initialized"
    $Failures++
}

Write-Host ""
if ($Failures -gt 0) {
    Write-Host "[ERROR] $Failures required checks failed; $Warnings optional warnings"
    exit 1
}
Write-Host "[OK] Doctor passed with $Warnings optional warnings"
