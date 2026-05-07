param (
    [string]$MkvFile
)

# ==================================================
# Global error handling
# ==================================================
$ErrorActionPreference = "Stop"

# 🔸 TRAP: Keep window open on crash
trap {
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    Pause
    exit
}

# ==================================================
# Validate input
# ==================================================
# Clean quotes just in case
$MkvFile = $MkvFile -replace '"', ''

# 🔸 FIX: .NET Check
if (-not [System.IO.File]::Exists($MkvFile)) {
    Write-Host ""
    Write-Host "MKV file not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    Pause
    exit
}

$base = [System.IO.Path]::GetFileNameWithoutExtension($MkvFile)
# 🔸 FIX: .NET Directory
$dir  = [System.IO.Path]::GetDirectoryName($MkvFile)

# ==================================================
# Read MKV structure via JSON (CORRECT way)
# ==================================================
# mkvmerge handles quotes fine
$json = & mkvmerge -J "$MkvFile" | ConvertFrom-Json

$subtitleTracks = $json.tracks | Where-Object {
    $_.type -eq "subtitles"
}

if (-not $subtitleTracks) {
    Write-Host ""
    Write-Host "No subtitle tracks found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    Pause
    exit
}

if ($subtitleTracks.Count -gt 1) {
    Write-Host ""
    Write-Host "Multiple subtitle tracks detected." -ForegroundColor Yellow
    Write-Host "Automatic extraction aborted." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Use MKVToolNix GUI to choose the correct subtitle." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    Pause
    exit
}

# ==================================================
# Extract subtitle track ID
# ==================================================
$trackId = $subtitleTracks[0].id

# ==================================================
# Extract subtitle
# ==================================================
# 🔸 FIX: .NET Path Combine
$outFile = [System.IO.Path]::Combine($dir, $base + ".srt")

& mkvextract tracks "$MkvFile" ($trackId.ToString() + ":" + $outFile)

# ==================================================
# Verify result
# ==================================================
# 🔸 FIX: .NET Check
if (-not [System.IO.File]::Exists($outFile)) {
    Write-Host ""
    Write-Host "Subtitle extraction failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    Pause
    exit
}

# ==================================================
# Success output
# ==================================================
Write-Host ""
Write-Host "Subtitle extracted successfully" -ForegroundColor Cyan
Write-Host ""

Write-Host "MKV : " -NoNewline
# 🔸 FIX: .NET Display
Write-Host ([System.IO.Path]::GetFileName($MkvFile)) -ForegroundColor Green

Write-Host "SRT : " -NoNewline
# 🔸 FIX: .NET Display
Write-Host ([System.IO.Path]::GetFileName($outFile)) -ForegroundColor Blue

Write-Host "Path: " -NoNewline
Write-Host $dir -ForegroundColor DarkGray

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor DarkGray
Pause