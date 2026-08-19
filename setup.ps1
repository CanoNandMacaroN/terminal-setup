[CmdletBinding()]
param(
    [string]$Repo = "",
    [string]$AgeKeyFile = "",
    [switch]$Prune,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "Native Windows setup requires PowerShell 7 or newer (pwsh)."
}
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = if ($env:CHEZMOI_SOURCE_DIR) {
    $env:CHEZMOI_SOURCE_DIR
} else {
    Join-Path $env:LOCALAPPDATA "chezmoi"
}
$BackupBase = if ($env:TERMINAL_SETUP_BACKUP_DIR) {
    $env:TERMINAL_SETUP_BACKUP_DIR
} else {
    Join-Path $HOME ".terminal-setup\backups"
}
$PixiHome = if ($env:PIXI_HOME) { $env:PIXI_HOME } else { Join-Path $HOME ".pixi" }
$env:PIXI_HOME = $PixiHome
$env:PATH = "$(Join-Path $PixiHome 'bin');$env:PATH"

function Write-Section([string]$Message) {
    Write-Host "`n== $Message =="
}

function Test-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-External([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Install-Pixi {
    Write-Section "Platform prerequisites"
    if (Test-Command "pixi") {
        Write-Host "[OK] Pixi already installed"
        return
    }
    if ($DryRun) {
        Write-Host "[WARN] Would install Pixi into $PixiHome\bin"
        return
    }
    $env:PIXI_NO_PATH_UPDATE = "1"
    $Installer = Invoke-RestMethod -UseBasicParsing "https://pixi.sh/install.ps1"
    Invoke-Expression $Installer
    $env:PATH = "$(Join-Path $PixiHome 'bin');$env:PATH"
    if (-not (Test-Command "pixi")) {
        throw "Pixi installation failed"
    }
}

function Install-BootstrapCommands {
    if ($DryRun) {
        Write-Host "[WARN] Would bootstrap Git and chezmoi through Pixi"
        return
    }
    Invoke-External "pixi" @("global", "install", "--environment", "git", "--expose", "git=git", "git")
    Invoke-External "pixi" @("global", "install", "--environment", "chezmoi", "--expose", "chezmoi=chezmoi", "chezmoi")
}

function Initialize-Source {
    Write-Section "Chezmoi source"
    if ($DryRun) {
        if ($Repo) {
            Write-Host "[WARN] Would initialize $Repo into $SourceDir"
        } else {
            Write-Host "[WARN] Would copy the public starter into $SourceDir"
        }
        return
    }
    if ((Test-Path $SourceDir) -and (Get-ChildItem -Force $SourceDir | Select-Object -First 1)) {
        Write-Host "[OK] Reusing existing chezmoi source: $SourceDir"
        return
    }
    New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null
    if ($Repo) {
        Invoke-External "chezmoi" @("-S", $SourceDir, "init", $Repo)
        return
    }
    Get-ChildItem -Force (Join-Path $ScriptDir "starter") | Copy-Item -Destination $SourceDir -Recurse -Force
    Invoke-External "git" @("-C", $SourceDir, "init", "-b", "main")
}

function Install-AgeKey {
    if ($DryRun -or -not (Test-Path $SourceDir)) { return }
    $Encrypted = Get-ChildItem -Recurse -File $SourceDir -Filter "encrypted_*.age" | Select-Object -First 1
    if (-not $Encrypted) { return }
    $KeyTarget = Join-Path $HOME ".config\chezmoi\key.txt"
    if (Test-Path $KeyTarget) { return }
    if (-not $AgeKeyFile) {
        throw "Encrypted source files require -AgeKeyFile on native Windows"
    }
    $FirstSecretLine = Get-Content $AgeKeyFile | Where-Object { $_ -like "AGE-SECRET-KEY-1*" } | Select-Object -First 1
    if (-not $FirstSecretLine) { throw "Invalid age identity file" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $KeyTarget) | Out-Null
    Copy-Item $AgeKeyFile $KeyTarget
}

function Backup-ManagedTargets {
    if ($DryRun) { return }
    Write-Section "Existing configuration backup"
    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupDir = Join-Path $BackupBase "$Timestamp\home"
    $Targets = & chezmoi -S $SourceDir managed --include files,symlinks 2>$null
    foreach ($Target in $Targets) {
        if (-not $Target) { continue }
        $Source = Join-Path $HOME $Target
        if (-not (Test-Path $Source)) { continue }
        $Destination = Join-Path $BackupDir $Target
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
        Copy-Item $Source $Destination -Recurse -Force
    }
    if (Test-Path $BackupDir) { Write-Host "[OK] Existing targets backed up to $BackupDir" }
}

function Apply-Dotfiles {
    Write-Section "Apply dotfiles and manifests"
    if ($DryRun) {
        if ($Repo -and -not (Test-Path $SourceDir)) {
            Write-Host "[WARN] Repository mode cannot render before cloning"
            return
        }
        $PreviewSource = if (Test-Path $SourceDir) { $SourceDir } else { Join-Path $ScriptDir "starter" }
        if (Test-Command "chezmoi") {
            Invoke-External "chezmoi" @("-S", $PreviewSource, "apply", "--dry-run", "--verbose", "--no-tty", "--exclude", "scripts")
        } else {
            Write-Host "[WARN] Would preview the rendered dotfiles after chezmoi is installed"
        }
        return
    }
    $env:TERMINAL_SETUP_PRUNE = "0"
    Invoke-External "chezmoi" @("-S", $SourceDir, "apply", "--no-tty", "--exclude", "scripts")
    Invoke-External "chezmoi" @("-S", $SourceDir, "verify", "--exclude", "scripts")
    $SyncTools = Join-Path $HOME ".myshell\bin\sync-tools.ps1"
    if (-not (Test-Path $SyncTools)) { throw "Missing Windows tool sync script: $SyncTools" }
    & $SyncTools
}

function Get-DeclaredNames([string]$Manifest, [string]$Field) {
    $Pattern = '^{0} = "([^"]+)"$' -f [regex]::Escape($Field)
    return Get-Content $Manifest | ForEach-Object {
        if ($_ -match $Pattern) { $Matches[1] }
    } | Sort-Object -Unique
}

function Get-DeclaredPixiEnvironments([string]$Manifest, [string]$Platform) {
    $Names = [System.Collections.Generic.List[string]]::new()
    $CurrentEnvironment = ""
    $CurrentPlatforms = ""
    foreach ($Line in Get-Content $Manifest) {
        if ($Line -eq "[[tool]]") {
            if ($CurrentEnvironment -and
                (-not $CurrentPlatforms -or ",$CurrentPlatforms," -like "*,$Platform,*")) {
                $Names.Add($CurrentEnvironment)
            }
            $CurrentEnvironment = ""
            $CurrentPlatforms = ""
            continue
        }
        if ($Line -match '^environment = "([^"]+)"$') {
            $CurrentEnvironment = $Matches[1]
        } elseif ($Line -match '^platforms = "([^"]+)"$') {
            $CurrentPlatforms = $Matches[1]
        }
    }
    if ($CurrentEnvironment -and
        (-not $CurrentPlatforms -or ",$CurrentPlatforms," -like "*,$Platform,*")) {
        $Names.Add($CurrentEnvironment)
    }
    return $Names | Sort-Object -Unique
}

function Prune-Manifests {
    if (-not $Prune -or $DryRun) { return }
    Write-Section "Manifest pruning"
    $PixiTools = Join-Path $HOME ".myshell\pixi-tools.toml"
    $GlobalManifest = Join-Path $PixiHome "manifests\pixi-global.toml"
    $DesiredPixi = @(Get-DeclaredPixiEnvironments $PixiTools "windows")
    if ($DesiredPixi.Count -eq 0) { throw "pixi-tools.toml contains no environments; refusing to prune" }
    if (Test-Path $GlobalManifest) {
        $CurrentPixi = Get-Content $GlobalManifest | ForEach-Object {
            if ($_ -match '^\[envs\.([A-Za-z0-9_][A-Za-z0-9_.-]*)\]$') { $Matches[1] }
        } | Sort-Object -Unique
        foreach ($Environment in $CurrentPixi) {
            if ($Environment -notin $DesiredPixi) {
                Invoke-External "pixi" @("global", "uninstall", $Environment)
            }
        }
    }

    $UvTools = Join-Path $HOME ".myshell\uv-tools.toml"
    $DesiredUv = @(Get-DeclaredNames $UvTools "name")
    if ($DesiredUv.Count -eq 0) { throw "uv-tools.toml contains no tools; refusing to prune" }
    $CurrentUv = & uv tool list | ForEach-Object {
        if ($_ -match '^([A-Za-z0-9_.-]+) v') { $Matches[1] }
    }
    foreach ($Tool in $CurrentUv) {
        if ($Tool -notin $DesiredUv) { Invoke-External "uv" @("tool", "uninstall", $Tool) }
    }
}

function Initialize-Node {
    Write-Section "fnm, Node.js, Corepack, and pnpm"
    if ($DryRun) {
        Write-Host "[WARN] Would install Node LTS and enable pnpm"
        return
    }
    (& fnm env --shell powershell) | Out-String | Invoke-Expression
    Invoke-External "fnm" @("install", "--lts")
    Invoke-External "fnm" @("default", "lts-latest")
    Invoke-External "fnm" @("use", "lts-latest")
    Invoke-External "corepack" @("enable")
    Invoke-External "corepack" @("prepare", "pnpm@latest", "--activate")
}

Install-Pixi
Install-BootstrapCommands
Initialize-Source
Install-AgeKey
Backup-ManagedTargets
Apply-Dotfiles
Prune-Manifests
Initialize-Node

Write-Host "`n[OK] Terminal setup completed"
Write-Host "[INFO] Run .\doctor.ps1 for a detailed health check"
