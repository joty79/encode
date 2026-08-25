param (
    [Parameter(Mandatory = $true)]
    [string]$VideoFile,

    [switch]$PauseAtEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForUserIfRequested {
    if ($PauseAtEnd) {
        Write-Host ''
        Write-Host 'Press any key to close...' -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
    }
}

# 🔸 TRAP: Κρατάει το παράθυρο ανοιχτό αν σκάσει κάτι
trap {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Wait-ForUserIfRequested
    exit 1
}

# Καθαρισμός quotes
$VideoFile = $VideoFile -replace '"', ''

# Basic validation (.NET Safe)
if (-not [System.IO.File]::Exists($VideoFile)) {
    throw "Video file not found: $VideoFile"
}

$VideoFile = (Resolve-Path -LiteralPath $VideoFile -ErrorAction Stop).Path

# Paths (.NET Safe)
$dir  = [System.IO.Path]::GetDirectoryName($VideoFile)
$base = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)
$fileName = [System.IO.Path]::GetFileName($VideoFile)

$srt = [System.IO.Path]::Combine($dir, $base + '.srt')
$out = [System.IO.Path]::Combine($dir, $base + '.mkv')

if (-not [System.IO.File]::Exists($srt)) {
    throw "No matching subtitle found. Expected exactly: $($base).srt"
}

# 🔒 OVERWRITE PROTECTION
if ([System.IO.File]::Exists($out)) {
    throw "Output file already exists; nothing was overwritten: $out"
}

$mkvmerge = "C:\Program Files\MKVToolNix\mkvmerge.exe"

if (-not [System.IO.File]::Exists($mkvmerge)) {
    $mkvmergeCommand = Get-Command -Name 'mkvmerge' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $mkvmergeCommand) {
        throw 'mkvmerge.exe was not found at the standard installation path or in PATH.'
    }
    $mkvmerge = $mkvmergeCommand.Source
}

# Run merge (Arguments array helps avoid quoting issues)
$mergeArgs = @("-o", $out, $VideoFile, $srt)
$mergeOutput = & $mkvmerge $mergeArgs 2>&1
$mergeExitCode = $LASTEXITCODE

if ($mergeExitCode -ne 0) {
    if (Test-Path -LiteralPath $out) {
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    }
    throw "mkvmerge failed with exit code $mergeExitCode. $($mergeOutput -join [Environment]::NewLine)"
}

if (-not (Test-Path -LiteralPath $out -PathType Leaf) -or (Get-Item -LiteralPath $out).Length -le 0) {
    if (Test-Path -LiteralPath $out) {
        Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    }
    throw 'mkvmerge returned success but did not create a non-empty output file.'
}

$identifyOutput = & $mkvmerge -J $out 2>&1
$identifyExitCode = $LASTEXITCODE
if ($identifyExitCode -ne 0) {
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    throw "Output validation failed with mkvmerge exit code $identifyExitCode."
}

try {
    $outputInfo = ($identifyOutput -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    throw 'Output validation returned invalid JSON.'
}

$trackTypes = @($outputInfo.tracks | ForEach-Object { $_.type })
if ($trackTypes -notcontains 'video' -or $trackTypes -notcontains 'subtitles') {
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    throw 'Output validation did not find both video and subtitle tracks.'
}

# ---- CLEAN SUCCESS OUTPUT ----
Write-Host ""
Write-Host "MKVToolNix merge completed successfully" -ForegroundColor Cyan
Write-Host ""

Write-Host "Input video : " -NoNewline
Write-Host $fileName -ForegroundColor Green

Write-Host "Subtitle    : " -NoNewline
Write-Host ([System.IO.Path]::GetFileName($srt)) -ForegroundColor Red

Write-Host "Output MKV  : " -NoNewline
Write-Host ([System.IO.Path]::GetFileName($out)) -ForegroundColor Blue

Wait-ForUserIfRequested
