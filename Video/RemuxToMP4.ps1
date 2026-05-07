param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

# 🔸 Configuration
$FFmpegPath = "ffmpeg"
$FFprobePath = "ffprobe"

# 🔸 Path Validation
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Host "Error: File not found!" -ForegroundColor Red
    Start-Sleep -Seconds 3
    exit
}

$OutputFile = [System.IO.Path]::ChangeExtension($InputFile, ".mp4")
Write-Host "Processing: $InputFile" -ForegroundColor Cyan

# 🔵 Step 1: Probe Audio Codec
Write-Host "Analyzing audio stream..." -ForegroundColor Yellow
$audioCodec = & $FFprobePath -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 $InputFile

# 🔵 Step 2: Build Argument Array
# Χρησιμοποιούμε λίστα (Array) για να μην σπάνε τα paths με κενά
$ffmpegArgs = @(
    "-hide_banner",
    "-loglevel", "error",
    "-stats",
    "-i", $InputFile,
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-c:v", "copy"
)

# 🔵 Step 3: Decide Audio Strategy
$safeCodecs = @("aac", "mp3", "ac3", "eac3")

if (-not $audioCodec) {
    Write-Host "⚠️ Warning: No audio stream found." -ForegroundColor Yellow
} elseif ($safeCodecs -contains $audioCodec) {
    Write-Host "✅ Audio ($audioCodec) is compatible. Copying." -ForegroundColor Green
    $ffmpegArgs += "-c:a"
    $ffmpegArgs += "copy"
} else {
    Write-Host "⚠️ Audio ($audioCodec) incompatible. Converting to AAC." -ForegroundColor Magenta
    $ffmpegArgs += "-c:a"
    $ffmpegArgs += "aac"
    $ffmpegArgs += "-profile:a"
    $ffmpegArgs += "aac_low"
    $ffmpegArgs += "-b:a"
    $ffmpegArgs += "256k"
    $ffmpegArgs += "-ar"
    $ffmpegArgs += "48000"
}

# Add final flags
$ffmpegArgs += "-sn"
$ffmpegArgs += "-avoid_negative_ts"
$ffmpegArgs += "make_zero"
$ffmpegArgs += "-movflags"
$ffmpegArgs += "+faststart"
$ffmpegArgs += $OutputFile

# 🔵 Step 4: Execute FFmpeg
Write-Host "Running FFmpeg..." -ForegroundColor Cyan

# Τρέχουμε το FFmpeg περνώντας το Array. Το PowerShell χειρίζεται τα quotes αυτόματα.
& $FFmpegPath $ffmpegArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ DONE! Created: $OutputFile" -ForegroundColor Green
} else {
    Write-Host "⚠️ Error during conversion." -ForegroundColor Red
}

Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Gray
[void][System.Console]::ReadKey($true)