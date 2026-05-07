param(
    [string]$InputFile,
    [switch]$Batch,
    [switch]$NoPause
)

# ===============================
# DEFAULTS
# ===============================
$defaultFormat = "extract"  # or format name for audio input
$batchSettingsFile = "D:\Users\joty79\scripts\encode\audio\queue\batch_settings.json"

# ===============================
# SUPPORTED FORMATS
# ===============================
$videoExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.mpg', '.mpeg', 
    '.vob', '.webm', '.flv', '.m2ts', '.ts')
$audioExtensions = @('.aac', '.mp3', '.flac', '.wav', '.ogg', '.opus', 
    '.m4a', '.wma', '.ac3', '.dts')

# ===============================
# FUNCTIONS
# ===============================

function Get-AudioInfo {
    param([string]$InputPath)
    
    try {
        # Run ffprobe and capture output
        $probeOutput = & ffprobe -v error -select_streams a:0 `
            -show_entries stream=codec_name,channels,sample_rate,bit_rate,duration,index `
            -show_entries format=duration `
            -of json "$InputPath" 2>&1
        
        # Check if ffprobe succeeded
        if ($LASTEXITCODE -ne 0) {
            return $null
        }
        
        # Parse JSON
        $probe = $probeOutput | ConvertFrom-Json
        
        if (-not $probe.streams -or $probe.streams.Count -eq 0) {
            return $null
        }
        
        $stream = $probe.streams[0]
        $duration = if ($stream.duration) { $stream.duration } else { $probe.format.duration }
        
        return @{
            Codec       = $stream.codec_name
            Channels    = [int]$stream.channels
            SampleRate  = [int]$stream.sample_rate
            Bitrate     = $stream.bit_rate
            Duration    = $duration
            Index       = if ($stream.index -ne $null) { $stream.index } else { 0 }
        }
    }
    catch {
        return $null
    }
}

function Get-ChannelName {
    param([int]$Channels)
    
    switch ($Channels) {
        1 { return "Mono" }
        2 { return "Stereo" }
        6 { return "5.1 Surround" }
        8 { return "7.1 Surround" }
        default { return "$Channels channels" }
    }
}

function Get-DurationString {
    param([string]$Seconds)
    
    if (-not $Seconds -or $Seconds -eq "N/A") { return "Unknown" }
    
    try {
        $ts = [TimeSpan]::FromSeconds([double]$Seconds)
        return $ts.ToString("hh\:mm\:ss")
    }
    catch {
        return "Unknown"
    }
}

function Get-OutputExtension {
    param(
        [string]$Codec,
        [string]$Format
    )
    
    if ($Format -eq "extract") {
        # Map codec to extension for stream copy
        switch ($Codec.ToLower()) {
            'aac' { return '.aac' }
            'mp3' { return '.mp3' }
            'ac3' { return '.ac3' }
            'eac3' { return '.eac3' }
            'dts' { return '.dts' }
            'flac' { return '.flac' }
            'pcm_s16le' { return '.wav' }
            'pcm_s24le' { return '.wav' }
            'pcm_dvd' { return '.wav' }
            'opus' { return '.opus' }
            'vorbis' { return '.ogg' }
            'wmav2' { return '.wma' }
            default { return '.audio' }
        }
    }
    else {
        # Use selected format extension
        switch ($Format.ToLower()) {
            'aac' { return '.aac' }
            'mp3' { return '.mp3' }
            'ac3' { return '.ac3' }
            'flac' { return '.flac' }
            'wav' { return '.wav' }
            'opus' { return '.opus' }
        }
    }
}

function Print-IntroScreen {
    param(
        [hashtable]$AudioInfo,
        [string]$InputType,
        [string]$FileName,
        [string]$SelectedFormat
    )
    
    Clear-Host
    Write-Host ""
    Write-Host "Input file information:" -ForegroundColor Cyan
    Write-Host "-----------------------------"
    
    $typeDisplay = if ($InputType -eq 'video') { "Video file" } else { "Audio file" }
    $ext = [System.IO.Path]::GetExtension($FileName).ToUpper().TrimStart('.')
    Write-Host "Type: " -NoNewline
    Write-Host "$typeDisplay ($ext)" -ForegroundColor Green
    
    Write-Host "Codec: " -NoNewline
    Write-Host $AudioInfo.Codec.ToUpper() -ForegroundColor Green
    
    Write-Host "Channels: " -NoNewline
    Write-Host (Get-ChannelName -Channels $AudioInfo.Channels) -ForegroundColor Green
    
    Write-Host "Sample Rate: " -NoNewline
    Write-Host "$($AudioInfo.SampleRate) Hz" -ForegroundColor Green
    
    if ($AudioInfo.Bitrate) {
        $bitrateKbps = [math]::Round([double]$AudioInfo.Bitrate / 1000)
        Write-Host "Bitrate: " -NoNewline
        Write-Host "$bitrateKbps kbps" -ForegroundColor Green
    }
    
    if ($AudioInfo.Duration) {
        Write-Host "Duration: " -NoNewline
        Write-Host (Get-DurationString -Seconds $AudioInfo.Duration) -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Output options:" -ForegroundColor Cyan
    Write-Host "--------------------------"
    
    # Display current selection
    if ($InputType -eq 'video') {
        if ($SelectedFormat -eq "extract") {
            Write-Host "Press " -NoNewline -ForegroundColor DarkGray
            Write-Host "ENTER" -NoNewline -ForegroundColor Green
            Write-Host " to extract audio (stream copy - original format)" -ForegroundColor DarkGray
            Write-Host "  → No re-encoding, lossless and instant" -ForegroundColor Gray
        }
        else {
            $formatDesc = Get-FormatDescription -Format $SelectedFormat
            Write-Host "Press " -NoNewline -ForegroundColor DarkGray
            Write-Host "ENTER" -NoNewline -ForegroundColor Green
            Write-Host " to convert to $formatDesc" -ForegroundColor DarkGray
        }
        
        Write-Host ""
        Write-Host "Or press number to select:" -ForegroundColor DarkGray
        Write-Host "1) AAC (192 kbps - Avidemux safe)" -ForegroundColor Gray
        Write-Host "2) MP3 (192 kbps - universal)" -ForegroundColor Gray
        Write-Host "3) AC3 (384 kbps - DVD/theater)" -ForegroundColor Gray
        Write-Host "4) FLAC (lossless archival)" -ForegroundColor Gray
        Write-Host "5) WAV (uncompressed - pro editing)" -ForegroundColor Gray
        Write-Host "6) Opus (96 kbps - modern efficient)" -ForegroundColor Gray
    }
    else {
        # Audio input
        if ($SelectedFormat -eq "extract") {
            Write-Host "Press " -NoNewline -ForegroundColor DarkGray
            Write-Host "ENTER" -NoNewline -ForegroundColor Green
            Write-Host " to convert to AAC (192 kbps - Avidemux safe)" -ForegroundColor DarkGray
            Write-Host "  → Standard conversion for audio replacement" -ForegroundColor Gray
        }
        else {
            $formatDesc = Get-FormatDescription -Format $SelectedFormat
            Write-Host "Press " -NoNewline -ForegroundColor DarkGray
            Write-Host "ENTER" -NoNewline -ForegroundColor Green
            Write-Host " to convert to $formatDesc" -ForegroundColor DarkGray
        }
        
        Write-Host ""
        Write-Host "Or press number to select:" -ForegroundColor DarkGray
        Write-Host "1) MP3 (192 kbps - universal)" -ForegroundColor Gray
        Write-Host "2) AC3 (384 kbps - DVD/theater)" -ForegroundColor Gray
        Write-Host "3) FLAC (lossless archival)" -ForegroundColor Gray
        Write-Host "4) WAV (uncompressed - pro editing)" -ForegroundColor Gray
        Write-Host "5) Opus (96 kbps - modern efficient)" -ForegroundColor Gray
    }
}

function Get-FormatDescription {
    param([string]$Format)
    
    switch ($Format) {
        "aac" { return "AAC (192 kbps - Avidemux safe)" }
        "mp3" { return "MP3 (192 kbps - universal)" }
        "ac3" { return "AC3 (384 kbps - DVD/theater)" }
        "flac" { return "FLAC (lossless archival)" }
        "wav" { return "WAV (uncompressed - pro editing)" }
        "opus" { return "Opus (96 kbps - modern efficient)" }
    }
}

function Invoke-AudioConversion {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [hashtable]$AudioInfo,
        [string]$Format
    )
    
    Write-Host ""
    Write-Host "Starting conversion..." -ForegroundColor Yellow
    Write-Host ""
    
    $sampleRate = $AudioInfo.SampleRate
    
    # Check for codecs that can't be stream-copied
    $noStreamCopyCodecs = @('pcm_dvd')
    $forceConvert = $noStreamCopyCodecs -contains $AudioInfo.Codec.ToLower()
    
    if ($Format -eq "extract" -and -not $forceConvert) {
        # Stream copy
        $args = @(
            '-hide_banner', '-loglevel', 'error', '-stats',
            '-i', $InputPath,
            '-map', "0:$($AudioInfo.Index)",
            '-vn', '-sn',
            '-c:a', 'copy',
            '-y', $OutputPath
        )
    }
    elseif ($Format -eq "extract" -and $forceConvert) {
        # Force convert to WAV (stream copy not supported for this codec)
        Write-Host "[INFO] $($AudioInfo.Codec) requires conversion (stream copy not supported)" -ForegroundColor Yellow
        $args = @(
            '-hide_banner', '-loglevel', 'error', '-stats',
            '-i', $InputPath,
            '-map', "0:$($AudioInfo.Index)",
            '-vn', '-sn',
            '-c:a', 'pcm_s16le',
            '-y', $OutputPath
        )
    }
    else {
        # Format-specific encoding with sync-safe parameters
        switch ($Format) {
            "aac" {
                $args = @(
                    '-hide_banner', '-loglevel', 'error', '-stats',
                    '-i', $InputPath,
                    '-vn', '-sn',
                    '-c:a', 'aac',
                    '-profile:a', 'aac_low',
                    '-b:a', '192k',
                    '-ar', $sampleRate,
                    '-avoid_negative_ts', 'make_zero',
                    '-y', $OutputPath
                )
            }
            "mp3" {
                $args = @(
                    '-hide_banner', '-loglevel', 'error', '-stats',
                    '-i', $InputPath,
                    '-vn', '-sn',
                    '-c:a', 'libmp3lame',
                    '-b:a', '192k',
                    '-ar', $sampleRate,
                    '-avoid_negative_ts', 'make_zero',
                    '-y', $OutputPath
                )
            }
            "ac3" {
                $args = @(
                    '-hide_banner', '-loglevel', 'error', '-stats',
                    '-i', $InputPath,
                    '-vn', '-sn',
                    '-c:a', 'ac3',
                    '-b:a', '384k',
                    '-ar', $sampleRate,
                    '-avoid_negative_ts', 'make_zero',
                    '-y', $OutputPath
                )
            }
            "flac" {
                $args = @(
                    '-hide_banner', '-loglevel', 'error', '-stats',
                    '-i', $InputPath,
                    '-vn', '-sn',
                    '-c:a', 'flac',
                    '-y', $OutputPath
                )
            }
            "wav" {
                $args = @(
                    '-hide_banner', '-loglevel', 'error', '-stats',
                    '-i', $InputPath,
                    '-vn', '-sn',
                    '-c:a', 'pcm_s16le',
                    '-y', $OutputPath
                )
            }
            "opus" {
                $args = @(
                    '-hide_banner', '-loglevel', 'error', '-stats',
                    '-i', $InputPath,
                    '-vn', '-sn',
                    '-c:a', 'libopus',
                    '-b:a', '96k',
                    '-ar', $sampleRate,
                    '-avoid_negative_ts', 'make_zero',
                    '-y', $OutputPath
                )
            }
        }
    }
    
    & ffmpeg @args
    
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutputPath)) {
        Write-Host ""
        Write-Host "✓ Success!" -ForegroundColor Green
        Write-Host "Output: " -NoNewline -ForegroundColor Gray
        Write-Host $OutputPath -ForegroundColor Cyan
        return $true
    }
    else {
        Write-Host ""
        Write-Host "✗ Conversion failed" -ForegroundColor Red
        return $false
    }
}

# ===============================
# MAIN
# ===============================

Clear-Host
Write-Host ""
Write-Host "=====================================" -ForegroundColor DarkCyan
Write-Host " Audio Encoding System" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor DarkCyan
Write-Host ""

# Validate input
if (-not $InputFile) {
    Write-Host "[ERROR] No input path received." -ForegroundColor Red
    Pause
    exit 1
}

# 🔸 FIX 1: Use -LiteralPath for the initial check
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Host "[ERROR] Path not found:" -ForegroundColor Red
    Write-Host " $InputFile" -ForegroundColor Gray
    Pause
    exit 1
}

# ===============================
# FILE COLLECTION (folder or single file)
# ===============================
$allExtensions = $videoExtensions + $audioExtensions

# 🔸 FIX 2: Use -LiteralPath for file/folder detection
if (Test-Path -LiteralPath $InputFile -PathType Leaf) {
    # Single file
    $files = @((Get-Item -LiteralPath $InputFile))
    $workDir = Split-Path $InputFile -Parent
}
else {
    # Folder - collect all supported files
    $workDir = $InputFile
    $files = @()
    foreach ($ext in $allExtensions) {
        $pattern = "*$ext"
        # 🔸 FIX 3: Use -LiteralPath inside the loop for the folder path
        $found = Get-ChildItem -LiteralPath $workDir -Filter $pattern -File -ErrorAction SilentlyContinue
        if ($found) { $files += $found }
    }
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "[ERROR] No supported video/audio files found." -ForegroundColor Red
    Pause
    exit 1
}

Write-Host "Found $($files.Count) file(s) to process" -ForegroundColor Gray
Write-Host ""

# ===============================
# GET INFO FROM FIRST FILE
# ===============================
$firstFile = $files[0].FullName
$extension = [System.IO.Path]::GetExtension($firstFile).ToLower()

if ($extension -in $videoExtensions) {
    $inputType = 'video'
}
elseif ($extension -in $audioExtensions) {
    $inputType = 'audio'
}
else {
    Write-Host "[ERROR] Unsupported file format: $extension" -ForegroundColor Red
    Pause
    exit 1
}

# Get audio info from first file
Write-Host "Detecting audio stream..." -ForegroundColor Yellow

$audioInfo = Get-AudioInfo -InputPath $firstFile

if (-not $audioInfo) {
    Write-Host ""
    Write-Host "[WARNING] No audio stream detected in first file!" -ForegroundColor Yellow
    Write-Host "Skipping files without audio." -ForegroundColor Gray
    Write-Host ""
}

# Set initial format based on input type
if ($inputType -eq 'video') {
    $selectedFormat = "extract"
}
else {
    $selectedFormat = "aac"
}

# ===============================
# BATCH MODE HANDLING
# ===============================
if (-not $Batch) {
    # Interactive mode - show UI
    while ($true) {
        Print-IntroScreen -AudioInfo $audioInfo -InputType $inputType `
            -FileName (Split-Path $firstFile -Leaf) `
            -SelectedFormat $selectedFormat
        
        # Show file count if batch
        if ($files.Count -gt 1) {
            Write-Host ""
            Write-Host "Batch mode: " -NoNewline -ForegroundColor Cyan
            Write-Host "$($files.Count) files" -ForegroundColor Green
            Write-Host "Settings from first file will apply to all." -ForegroundColor DarkGray
        }
        
        Write-Host ""
        
        $key = [Console]::ReadKey($true)
        
        if ($key.Key -eq [ConsoleKey]::Enter) {
            break
        }
        
        if ($key.Key -eq [ConsoleKey]::Escape) {
            Write-Host "Cancelled." -ForegroundColor Gray
            exit 0
        }
        
        # Handle number selections
        if ($inputType -eq 'video') {
            switch ($key.KeyChar) {
                '1' { $selectedFormat = "aac" }
                '2' { $selectedFormat = "mp3" }
                '3' { $selectedFormat = "ac3" }
                '4' { $selectedFormat = "flac" }
                '5' { $selectedFormat = "wav" }
                '6' { $selectedFormat = "opus" }
            }
        }
        else {
            switch ($key.KeyChar) {
                '1' { $selectedFormat = "mp3" }
                '2' { $selectedFormat = "ac3" }
                '3' { $selectedFormat = "flac" }
                '4' { $selectedFormat = "wav" }
                '5' { $selectedFormat = "opus" }
            }
        }
    }
    
    # SAVE SETTINGS FOR BATCH
    $settings = @{
        Format = $selectedFormat
    }
    $settings | ConvertTo-Json | Set-Content $batchSettingsFile -Encoding UTF8
}
else {
    # BATCH MODE - LOAD SETTINGS
    if (Test-Path -LiteralPath $batchSettingsFile) {
        $s = Get-Content -LiteralPath $batchSettingsFile -Raw | ConvertFrom-Json
        $selectedFormat = $s.Format
        Write-Host "[Batch Mode] Using format: $selectedFormat" -ForegroundColor Gray
    }
}

# ===============================
# PROCESS ALL FILES
# ===============================

# Create output folder
$outDir = Join-Path $workDir "encoded"
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -Path $outDir -ItemType Directory | Out-Null }

$successCount = 0
$failCount = 0
$skipCount = 0

for ($i = 0; $i -lt $files.Count; $i++) {
    $f = $files[$i]
    $inputPath = $f.FullName
    $name = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    
    Write-Host ""
    Write-Host "[$($i + 1) / $($files.Count)] " -NoNewline -ForegroundColor White
    Write-Host $f.Name -ForegroundColor Cyan
    
    # Get audio info for this file
    $fileAudioInfo = Get-AudioInfo -InputPath $inputPath
    
    if (-not $fileAudioInfo) {
        Write-Host "  ⚠ No audio stream - skipping" -ForegroundColor Yellow
        $skipCount++
        continue
    }
    
    # Determine output extension
    if ($selectedFormat -eq "extract") {
        $ext = Get-OutputExtension -Codec $fileAudioInfo.Codec -Format "extract"
    }
    else {
        $ext = Get-OutputExtension -Codec $fileAudioInfo.Codec -Format $selectedFormat
    }
    
    $outputFile = Join-Path $outDir "$name$ext"
    
    # Execute conversion
    $success = Invoke-AudioConversion -InputPath $inputPath -OutputPath $outputFile `
        -AudioInfo $fileAudioInfo -Format $selectedFormat
    
    if ($success) {
        $successCount++
    }
    else {
        $failCount++
    }
}

# ===============================
# SUMMARY
# ===============================

# Only show summary if NOT a single-file batch job
# (Folder batch jobs or interactive jobs should show summary)
if (-not $Batch -or $files.Count -gt 1) {
    Write-Host ""
    Write-Host "=====================================" -ForegroundColor DarkCyan
    Write-Host " Batch Complete" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Success: " -NoNewline -ForegroundColor Gray
    Write-Host $successCount -ForegroundColor Green
    Write-Host "  Failed: " -NoNewline -ForegroundColor Gray
    Write-Host $failCount -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
    Write-Host "  Skipped: " -NoNewline -ForegroundColor Gray
    Write-Host $skipCount -ForegroundColor $(if ($skipCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""
}

# Only pause if NOT in batch mode AND pauses allowed
if (-not $Batch -and -not $NoPause) {
    Write-Host "Press any key to exit..." -ForegroundColor DarkGray
    Pause
}