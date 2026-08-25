[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

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

trap {
    Write-Host ''
    Write-Host ('ERROR: {0}' -f $_.Exception.Message) -ForegroundColor Red
    Wait-ForUserIfRequested
    exit 1
}

$resolvedInput = (Resolve-Path -LiteralPath $InputFile -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedInput -PathType Leaf)) {
    throw "Input path is not a file: $resolvedInput"
}

$outputFile = [System.IO.Path]::ChangeExtension($resolvedInput, '.mp4')
if ([string]::Equals($resolvedInput, $outputFile, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Input is already an MP4 file; refusing to overwrite it.'
}

if (Test-Path -LiteralPath $outputFile) {
    throw "Output already exists; nothing was overwritten: $outputFile"
}

$ffmpegCommand = Get-Command -Name 'ffmpeg' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$ffprobeCommand = Get-Command -Name 'ffprobe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $ffmpegCommand) { throw 'Required command ffmpeg was not found in PATH.' }
if (-not $ffprobeCommand) { throw 'Required command ffprobe was not found in PATH.' }

$ffmpeg = $ffmpegCommand.Source
$ffprobe = $ffprobeCommand.Source

Write-Host "Processing: $resolvedInput" -ForegroundColor Cyan
Write-Host 'Analyzing audio stream...' -ForegroundColor Yellow

$audioProbe = & $ffprobe -v error -select_streams a:0 -show_entries stream=codec_name `
    -of default=noprint_wrappers=1:nokey=1 $resolvedInput 2>&1
$audioProbeExitCode = $LASTEXITCODE
if ($audioProbeExitCode -ne 0) {
    throw "Audio probe failed with exit code $audioProbeExitCode. $($audioProbe -join [Environment]::NewLine)"
}

$audioCodec = @($audioProbe | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) | Select-Object -First 1
$ffmpegArguments = @(
    '-hide_banner',
    '-loglevel', 'error',
    '-stats',
    '-n',
    '-i', $resolvedInput,
    '-map', '0:v:0',
    '-map', '0:a:0?',
    '-c:v', 'copy'
)

$safeAudioCodecs = @('aac', 'mp3', 'ac3', 'eac3')
if (-not $audioCodec) {
    Write-Host 'No audio stream found.' -ForegroundColor Yellow
}
elseif ($safeAudioCodecs -contains $audioCodec) {
    Write-Host "Audio ($audioCodec) is MP4-compatible. Copying." -ForegroundColor Green
    $ffmpegArguments += @('-c:a', 'copy')
}
else {
    Write-Host "Audio ($audioCodec) is not MP4-compatible. Converting to AAC." -ForegroundColor Magenta
    $ffmpegArguments += @('-c:a', 'aac', '-profile:a', 'aac_low', '-b:a', '256k', '-ar', '48000')
}

$ffmpegArguments += @(
    '-sn',
    '-avoid_negative_ts', 'make_zero',
    '-movflags', '+faststart',
    $outputFile
)

Write-Host 'Running FFmpeg...' -ForegroundColor Cyan
& $ffmpeg @ffmpegArguments
$ffmpegExitCode = $LASTEXITCODE

if ($ffmpegExitCode -ne 0) {
    if (Test-Path -LiteralPath $outputFile) {
        Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
    }
    throw "FFmpeg remux failed with exit code $ffmpegExitCode."
}

if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf) -or (Get-Item -LiteralPath $outputFile).Length -le 0) {
    if (Test-Path -LiteralPath $outputFile) {
        Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
    }
    throw 'FFmpeg returned success but did not create a non-empty output file.'
}

$outputProbe = & $ffprobe -v error -select_streams v:0 -show_entries stream=codec_name `
    -of default=noprint_wrappers=1:nokey=1 $outputFile 2>&1
$outputProbeExitCode = $LASTEXITCODE
if ($outputProbeExitCode -ne 0 -or -not (@($outputProbe | Where-Object { $_.ToString().Trim() }).Count -gt 0)) {
    Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
    throw "Output validation failed with ffprobe exit code $outputProbeExitCode."
}

Write-Host ''
Write-Host "DONE! Created: $outputFile" -ForegroundColor Green
Wait-ForUserIfRequested
