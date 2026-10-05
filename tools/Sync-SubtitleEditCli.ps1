<#
.SYNOPSIS
    Checks Subtitle Edit versions and synchronizes/installs the matching official SeConv CLI.

.DESCRIPTION
    Queries the installed Subtitle Edit GUI version (or latest GitHub release),
    checks the current CLI (seconv.exe) installation, queries the GitHub API for
    the matching SeConv package, downloads and preserves the archive in D:\Programs\Video,
    and updates C:\Program Files\Subtitle Edit CLI.

.PARAMETER CheckOnly
    Only check and display versions without downloading or installing anything.

.PARAMETER Latest
    Check GitHub for the latest release instead of matching the installed GUI.

.PARAMETER Force
    Re-download and re-install even if the CLI version already matches.

.EXAMPLE
    .\Sync-SubtitleEditCli.ps1 -CheckOnly
    Checks current GUI, CLI, and online versions.

.EXAMPLE
    .\Sync-SubtitleEditCli.ps1
    Syncs SeConv CLI to match the installed Subtitle Edit GUI version.
#>

[CmdletBinding()]
param(
    [string]$TargetDir = 'C:\Program Files\Subtitle Edit CLI',
    [string]$GuiPath   = 'C:\Program Files\Subtitle Edit\SubtitleEdit.exe',
    [string]$BackupDir = 'D:\Programs\Video',
    [switch]$CheckOnly,
    [switch]$Latest,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-GuiVersion {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $info = (Get-Item -LiteralPath $Path).VersionInfo
    $raw = $info.ProductVersion
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $info.FileVersion }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw -replace '\+.*$', '').Trim('v')
}

function Get-CliVersion {
    param([string]$Dir)
    $exe = Join-Path $Dir 'seconv.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $null }
    try {
        $out = & $exe --version 2>$null
        $clean = ($out | Select-Object -First 1).ToString().Trim()
        if ($clean -match '^\d+\.\d+') { return $clean }
    } catch { }
    $info = (Get-Item -LiteralPath $exe).VersionInfo
    $raw = $info.ProductVersion
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = $info.FileVersion }
    return ($raw -replace '\+.*$', '').Trim('v')
}

function Get-GitHubRelease {
    param([string]$TargetVersion, [bool]$GetLatest)

    $headers = @{
        'User-Agent' = 'PowerShell-SubtitleEdit-Sync'
        'Accept'     = 'application/vnd.github.v3+json'
    }

    if ($GetLatest -or [string]::IsNullOrWhiteSpace($TargetVersion)) {
        Write-Host "Fetching latest release info from GitHub..." -ForegroundColor Cyan
        return Invoke-RestMethod -Uri "https://api.github.com/repos/SubtitleEdit/subtitleedit/releases/latest" -Headers $headers
    }

    $tag = "v$TargetVersion"
    Write-Host "Querying GitHub release for tag '$tag'..." -ForegroundColor Cyan
    try {
        return Invoke-RestMethod -Uri "https://api.github.com/repos/SubtitleEdit/subtitleedit/releases/tags/$tag" -Headers $headers
    } catch {
        Write-Host "Direct tag lookup failed; searching recent releases..." -ForegroundColor Yellow
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/SubtitleEdit/subtitleedit/releases?per_page=20" -Headers $headers
        $matched = $releases | Where-Object { $_.tag_name -eq $tag -or $_.tag_name -like "*$TargetVersion*" } | Select-Object -First 1
        if ($null -ne $matched) { return $matched }
        throw "Could not find a GitHub release matching version '$TargetVersion'."
    }
}

# --- Step 1: Detect installed versions ---
$installedGui = Get-GuiVersion -Path $GuiPath
$installedCli = Get-CliVersion -Dir $TargetDir

Write-Host "========================================" -ForegroundColor DarkCyan
Write-Host " Subtitle Edit Version Synchronization  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor DarkCyan
Write-Host ("Installed GUI Version : " + $(if ($installedGui) { $installedGui } else { "(Not installed)" })) -ForegroundColor White
Write-Host ("Installed CLI Version : " + $(if ($installedCli) { $installedCli } else { "(Not installed)" })) -ForegroundColor White
Write-Host "Target Directory      : $TargetDir" -ForegroundColor Gray
Write-Host "Backup Directory      : $BackupDir" -ForegroundColor Gray
Write-Host ""

# Determine target version to look for
$versionToFind = if ($Latest -or [string]::IsNullOrWhiteSpace($installedGui)) { $null } else { $installedGui }

# --- Step 2: Query GitHub ---
$release = Get-GitHubRelease -TargetVersion $versionToFind -GetLatest $Latest
$releaseTag = $release.tag_name
$releaseVer = ($releaseTag -replace '^v', '').Trim()
Write-Host "GitHub Release Found  : $($release.name) ($releaseTag)" -ForegroundColor Green

$asset = $release.assets | Where-Object { $_.name -eq 'SeConv-Windows-x64.zip' }
if ($null -eq $asset) {
    throw "Release '$releaseTag' does not have 'SeConv-Windows-x64.zip' attached."
}

Write-Host "Matching Asset        : $($asset.name) ($([math]::Round($asset.size / 1MB, 2)) MB)" -ForegroundColor Gray

if ($CheckOnly) {
    Write-Host "`n[-CheckOnly specified; exiting without making changes.]" -ForegroundColor Yellow
    if ($installedCli -eq $releaseVer) {
        Write-Host "Status: SeConv CLI is already matching and up to date." -ForegroundColor Green
    } else {
        Write-Host "Status: Update available ($installedCli -> $releaseVer)." -ForegroundColor Yellow
    }
    return
}

# --- Step 3: Check if update is needed ---
if (-not $Force -and $installedCli -eq $releaseVer) {
    Write-Host "`nSeConv CLI is already at version $releaseVer. No update needed." -ForegroundColor Green
    Write-Host "(Use -Force if you want to re-download and reinstall)." -ForegroundColor Gray
    return
}

# --- Step 4: Download & Preserve archive ---
if (-not (Test-Path -LiteralPath $BackupDir)) {
    [void](New-Item -ItemType Directory -Path $BackupDir -Force)
}

$destZipName = "SeConv-Windows-x64-$releaseVer.zip"
$destZipPath = Join-Path $BackupDir $destZipName

Write-Host "`nDownloading SeConv package to '$destZipPath'..." -ForegroundColor Cyan
$webClient = [System.Net.WebClient]::new()
$webClient.Headers.Add('User-Agent', 'PowerShell-SubtitleEdit-Sync')
$webClient.DownloadFile($asset.browser_download_url, $destZipPath)

$sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $destZipPath).Hash
Write-Host "Downloaded: $destZipName" -ForegroundColor Green
Write-Host "SHA-256   : $sha256" -ForegroundColor Gray

# --- Step 5: Extract to temporary location ---
$tempExtract = Join-Path ([IO.Path]::GetTempPath()) ("seconv-install-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempExtract -Force)

try {
    Write-Host "Extracting package contents..." -ForegroundColor Cyan
    Expand-Archive -LiteralPath $destZipPath -DestinationPath $tempExtract -Force

    # --- Step 6: Deploy to Target Directory ---
    $isAdmin = Get-IsAdmin

    if ($isAdmin) {
        Write-Host "Copying files to '$TargetDir' (Elevated)..." -ForegroundColor Cyan
        if (-not (Test-Path -LiteralPath $TargetDir)) {
            [void](New-Item -ItemType Directory -Path $TargetDir -Force)
        }
        Copy-Item -Path "$tempExtract\*" -Destination $TargetDir -Recurse -Force
    } else {
        Write-Host "Copying to '$TargetDir' requires Administrator permissions. Requesting elevation..." -ForegroundColor Yellow
        $copyCommand = @"
`$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath '$TargetDir')) {
    [void](New-Item -ItemType Directory -Path '$TargetDir' -Force)
}
Copy-Item -Path '$tempExtract\*' -Destination '$TargetDir' -Recurse -Force
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($copyCommand))
        $proc = Start-Process -FilePath "powershell.exe" `
                              -ArgumentList @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) `
                              -Verb RunAs `
                              -PassThru `
                              -Wait

        if ($proc.ExitCode -ne 0) {
            throw "Elevated file copy failed with exit code $($proc.ExitCode)."
        }
    }

    # --- Step 7: Verification ---
    $cliExe = Join-Path $TargetDir 'seconv.exe'
    if (Test-Path -LiteralPath $cliExe) {
        $newVer = Get-CliVersion -Dir $TargetDir
        Write-Host "`nSuccessfully installed SeConv v$newVer to '$TargetDir'!" -ForegroundColor Green
        & $cliExe --version
    } else {
        throw "Verification failed: '$cliExe' not found after installation."
    }

} finally {
    if (Test-Path -LiteralPath $tempExtract) {
        Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}
