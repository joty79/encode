param (
    [string]$TargetPath = (Get-Location),
    [switch]$Batch
)

# ===============================
# DEFAULTS
# ===============================
$defaultNvencQP = 22
$defaultX264CRF = 19
$defaultGOPSeconds = 1

$nvencQP = $defaultNvencQP
$x264CRF = $defaultX264CRF
$encoderPreference = "auto"
$resizeWidth = $null
$gopSeconds = $defaultGOPSeconds

# ===============================
# BATCH SETTINGS FILE
# ===============================
$batchSettingsFile = Join-Path $PSScriptRoot "queue\batch_settings.json"


# ===============================
# FUNCTIONS
# ===============================

function Test-H264NvencAvailable {
    $ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpegCommand) {
        return $false
    }

    $probeArgs = @(
        "-hide_banner",
        "-loglevel", "error",
        "-f", "lavfi",
        "-i", "color=c=black:s=256x256:r=1:d=0.04",
        "-frames:v", "1",
        "-an",
        "-c:v", "h264_nvenc",
        "-f", "null",
        "NUL"
    )

    & ffmpeg @probeArgs 2>&1 | Out-Null
    $ffmpegExitCode = $LASTEXITCODE
    return ($ffmpegExitCode -eq 0)
}

function Resolve-VideoEncoder {
    param(
        [Parameter(Mandatory)][ValidateSet("auto", "nvenc", "x264")][string]$Preference,
        [Parameter(Mandatory)][bool]$NvencAvailable
    )

    if ($Preference -eq "x264") {
        return "x264"
    }

    if ($NvencAvailable) {
        return "nvenc"
    }

    return "x264"
}

function Get-VideoEncoderArguments {
    param(
        [Parameter(Mandatory)][ValidateSet("nvenc", "x264")][string]$Encoder,
        [Parameter(Mandatory)][ValidateRange(0, 51)][int]$NvencQP,
        [Parameter(Mandatory)][ValidateRange(0, 51)][int]$X264CRF,
        [Parameter(Mandatory)][ValidateRange(1, 100000)][int]$MaxMbps,
        [Parameter(Mandatory)][ValidateRange(1, 100000)][int]$GopFrames
    )

    if ($Encoder -eq "nvenc") {
        return @(
            "-c:v", "h264_nvenc", "-rc", "constqp", "-qp", "$NvencQP",
            "-maxrate", "$($MaxMbps)M", "-bufsize", "$($MaxMbps * 2)M",
            "-preset", "p5", "-profile:v", "high", "-pix_fmt", "yuv420p",
            "-g", "$GopFrames", "-bf", "0"
        )
    }

    return @(
        "-c:v", "libx264", "-crf", "$X264CRF",
        "-preset", "fast", "-profile:v", "high", "-pix_fmt", "yuv420p",
        "-g", "$GopFrames", "-bf", "3"
    )
}

function Get-ValidatedIntegerSetting {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory)][int]$Minimum,
        [Parameter(Mandatory)][int]$Maximum,
        [Parameter(Mandatory)][int]$DefaultValue,
        [Parameter(Mandatory)][string]$Name
    )

    $parsedValue = 0
    if ([int]::TryParse([string]$Value, [ref]$parsedValue) -and
        $parsedValue -ge $Minimum -and
        $parsedValue -le $Maximum) {
        return $parsedValue
    }

    Write-Host "Invalid saved $Name value. Using default $DefaultValue." -ForegroundColor Yellow
    return $DefaultValue
}

function Get-InterlaceInfo {
    param([string]$InputPath)

    $idetOut = & ffmpeg -hide_banner -loglevel info -i "$InputPath" `
        -filter:v idet -frames:v 300 -an -f rawvideo -y NUL 2>&1
    $ffmpegExitCode = $LASTEXITCODE

    if ($ffmpegExitCode -ne 0) {
        return @{
            Succeeded  = $false
            ExitCode   = $ffmpegExitCode
            Interlaced = $false
            Field      = $null
        }
    }

    $text = $idetOut | Out-String

    $matches = [regex]::Matches(
        $text,
        'Multi frame detection:\s*TFF:\s*(\d+)\s*BFF:\s*(\d+)\s*Progressive:\s*(\d+)\s*Undetermined:\s*(\d+)'
    )

    if ($matches.Count -eq 0) {
        return @{ Succeeded = $true; ExitCode = 0; Interlaced = $false; Field = $null }
    }

    # TAKE LAST BLOCK (IMPORTANT)
    $m = $matches[$matches.Count - 1]

    $tff = [int]$m.Groups[1].Value
    $bff = [int]$m.Groups[2].Value

    if (($tff + $bff) -gt 0) {
        return @{
            Succeeded  = $true
            ExitCode   = 0
            Interlaced = $true
            Field      = if ($bff -gt $tff) { "BFF" } else { "TFF" }
        }
    }

    return @{ Succeeded = $true; ExitCode = 0; Interlaced = $false; Field = $null }
}

function New-QTGMCAvs {
    param (
        [string]$InputPath,
        [string]$Field
    )

    $avs = Join-Path $env:TEMP ("qtgmc_" + [guid]::NewGuid() + ".avs")
    $assume = if ($Field -eq "BFF") { "AssumeBFF()" } else { "AssumeTFF()" }

    # Προσθήκη Prefetch για τον Ryzen 9700X
    @"
FFVideoSource("$InputPath")
$assume
QTGMC(Preset="Slow", TR2=2, FPSDivisor=2)
Prefetch(14) 
"@ | Set-Content -Encoding ASCII $avs

    return $avs
}

# === [NEW] AUDIO SYNC ANALYSIS FUNCTION ===
function Get-AudioSyncAnalysis {
    param([string]$InputPath)

    # Run FFprobe for Video & Audio Streams (JSON)
    $ffprobeArgs = @(
        "-v", "error",
        "-show_entries", "stream=codec_type,codec_name,start_time,duration,sample_rate",
        "-show_entries", "format=duration",
        "-of", "json",
        $InputPath
    )
    
    try {
        $ffprobeOutput = & ffprobe @ffprobeArgs
        $ffprobeExitCode = $LASTEXITCODE
        if ($ffprobeExitCode -ne 0) {
            return @{ Text = "Error reading stream info (ffprobe exit $ffprobeExitCode)"; IsRisky = $false }
        }

        $jsonObj = ($ffprobeOutput -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @{ Text = "Error reading stream info"; IsRisky = $false }
    }

    # 1. Find Video & Audio Streams
    $vStream = $jsonObj.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $aStream = $jsonObj.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1

    if (-not $aStream) {
        return @{ Text = "No Audio Stream"; IsRisky = $false }
    }

    # 2. Extract Data
    $codec  = $aStream.codec_name.ToUpper()
    $hz     = $aStream.sample_rate
    
    $vStart = if ($vStream.start_time) { [double]$vStream.start_time } else { 0.0 }
    $vDur   = if ($vStream.duration) { [double]$vStream.duration } else { [double]$jsonObj.format.duration }
    
    $aStart = if ($aStream.start_time) { [double]$aStream.start_time } else { 0.0 }
    $aDur   = if ($aStream.duration) { [double]$aStream.duration } else { $vDur }

    # 3. Calculate Differences (Sync Logic)
    $startDiff = $aStart - $vStart
    $durDiff   = $aDur - $vDur

    # 4. Format Output
    # Start Time Check (> 60ms is risky)
    if ([math]::Abs($startDiff) -gt 0.06) { 
        $startStr = "⚠️ Offset: $($startDiff.ToString('N3'))s"
        $risk = $true
    } else {
        $startStr = "Start: OK"
        $risk = $false
    }

    # Duration Check (> 0.5s is risky)
    if ([math]::Abs($durDiff) -gt 0.5) {
        $durStr = "⚠️ Dur Diff: $($durDiff.ToString('N1'))s"
        $risk = $true
    } else {
        $durStr = "Dur: Match"
    }

    # Return formatted object
    return @{
        Text    = "Audio: $codec | $hz Hz | $startStr | $durStr"
        IsRisky = $risk
    }
}
# ==========================================

# === UI helpers + Video info + Resize helpers (BEGIN) ===

function Write-LabelValue {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Value
    )
    Write-Host ($Label) -NoNewline
    Write-Host ($Value) -ForegroundColor Green
}

function Read-LineOrEsc {
    param(
        [string]$Prompt = ""
    )

    if ($Prompt) { Write-Host $Prompt }

    $sb = New-Object System.Text.StringBuilder
    while ($true) {
        $k = [Console]::ReadKey($true)

        if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Subtract) {
            Write-Host ""
            return $null
        }

        if ($k.Key -eq [ConsoleKey]::Enter) {
            Write-Host ""
            return $sb.ToString()
        }

        if ($k.Key -eq [ConsoleKey]::Backspace) {
            if ($sb.Length -gt 0) {
                $null = $sb.Remove($sb.Length - 1, 1)
                # erase char from console
                Write-Host "`b `b" -NoNewline
            }
            continue
        }

        # accept printable characters
        if ($k.KeyChar -ne [char]0) {
            $null = $sb.Append($k.KeyChar)
            Write-Host $k.KeyChar -NoNewline
        }
    }
}

function Get-VideoInfo {
    param([string]$InputPath)

    $info = & ffprobe -v error `
        -select_streams v:0 `
        -show_entries stream=width,height,r_frame_rate,sample_aspect_ratio,display_aspect_ratio `
        -of default=nw=1 "$InputPath"
    $ffprobeExitCode = $LASTEXITCODE

    if ($ffprobeExitCode -ne 0) {
        return @{
            Succeeded = $false
            ExitCode  = $ffprobeExitCode
            Error     = 'ffprobe could not read the first video stream.'
        }
    }

    $metadata = @{}
    foreach ($line in @($info)) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $metadata[$parts[0]] = $parts[1]
        }
    }

    $width = 0
    $height = 0
    $fpsNumerator = 0.0
    $fpsDenominator = 0.0
    $fpsParts = @($metadata['r_frame_rate'] -split '/', 2)

    $metadataIsValid =
        [int]::TryParse($metadata['width'], [ref]$width) -and
        [int]::TryParse($metadata['height'], [ref]$height) -and
        $fpsParts.Count -eq 2 -and
        [double]::TryParse($fpsParts[0], [ref]$fpsNumerator) -and
        [double]::TryParse($fpsParts[1], [ref]$fpsDenominator) -and
        $width -gt 0 -and
        $height -gt 0 -and
        $fpsDenominator -ne 0

    if (-not $metadataIsValid) {
        return @{
            Succeeded = $false
            ExitCode  = 0
            Error     = 'ffprobe returned incomplete or invalid video metadata.'
        }
    }

    return @{
        Succeeded = $true
        ExitCode  = 0
        Error     = $null
        Width     = $width
        Height    = $height
        FPS       = [math]::Round(($fpsNumerator / $fpsDenominator), 2)
        SAR       = if ($metadata.ContainsKey('sample_aspect_ratio')) { $metadata['sample_aspect_ratio'] } else { 'N/A' }
        DAR       = if ($metadata.ContainsKey('display_aspect_ratio')) { $metadata['display_aspect_ratio'] } else { 'N/A' }
    }
}

function Show-LimitWidthMenu {
    param([int]$InputWidth)

    $candidates = @(1280, 960, 640) | Where-Object { $_ -lt $InputWidth }

    while ($true) {
        Write-Host ""
        Write-Host "--- Resize: Limit width ---" -ForegroundColor Cyan
        Write-Host "--------------------------"
        
        Write-LabelValue "Input width: " "$InputWidth px"
        Write-Host ""        

        Write-Host "0) Keep original"
        for ($i = 0; $i -lt $candidates.Count; $i++) {
            Write-Host "$($i + 1)) $($candidates[$i])"
        }
        Write-Host "$($candidates.Count + 1)) Custom"
        Write-Host ""
        Write-Host "Press a " -ForegroundColor DarkGray -NoNewline
        Write-Host "number" -NoNewline
        Write-Host " to choose. Press " -ForegroundColor DarkGray -NoNewline
        Write-Host "ESC/-" -ForegroundColor Red -NoNewline
        Write-Host " to go back." -ForegroundColor DarkGray


        $k = [Console]::ReadKey($true)

        if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Subtract) {
            return $null
        }

        # digits
        if ($k.KeyChar -ge '0' -and $k.KeyChar -le '9') {
            $choice = [int]([string]$k.KeyChar)

            if ($choice -eq 0) { return $null }

            if ($choice -ge 1 -and $choice -le $candidates.Count) {
                return $candidates[$choice - 1]
            }

            if ($choice -eq ($candidates.Count + 1)) {
                Write-Host ""
                Write-Host "Custom width:" -ForegroundColor Cyan
                Write-Host "--------------------------"
            
                Write-Host "New Width: " -NoNewline
                $line = Read-LineOrEsc
                Write-Host ""                
                if ($null -eq $line) { continue }

                if ($line -match '^\d+$') {
                    $cw = [int]$line
                    if ($cw -ge $InputWidth) {
                        Write-Host "Width >= input width. Resize will be skipped." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 600
                        return $null
                    }
                    return $cw
                }
                else {
                    Write-Host "Invalid value." -ForegroundColor Yellow
                    Start-Sleep -Milliseconds 600
                    continue
                }
            }
        }
    }
}

function Invoke-FFmpegWithProgress {
    param(
        [Parameter(Mandatory)][string[]]$FFmpegArgs,
        [Parameter(Mandatory)][double]$TotalSec
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $lastPercent = -1
    $speed = "?"
    $percent = 0

    & ffmpeg @FFmpegArgs 2>&1 | ForEach-Object {

        $line = $_.ToString().Trim()

        if ($line -match '^out_time_ms=(\d+)$') {
            $outSec = [double]$matches[1] / 1000000.0
            if ($TotalSec -gt 0) {
                $percent = [math]::Min(100, [math]::Floor(($outSec / $TotalSec) * 100))
            }
        }
        elseif ($line -match '^speed=([\d\.]+)x$') {
            $speed = $matches[1]
        }
        elseif ($line -eq 'progress=continue') {

            if ($percent -ne $lastPercent) {
                $elapsed = [TimeSpan]::FromMilliseconds($sw.ElapsedMilliseconds).ToString("hh\:mm\:ss")
                Write-Host "`rProgress: " -NoNewline -ForegroundColor White
                Write-Host "$percent%" -NoNewline -ForegroundColor Cyan
                Write-Host " | speed " -NoNewline -ForegroundColor White
                Write-Host "$speed"x"" -NoNewline -ForegroundColor Cyan
                Write-Host " | elapsed " -NoNewline -ForegroundColor White
                Write-Host "$elapsed   " -NoNewline -ForegroundColor Cyan

                $lastPercent = $percent
            }
        }
        elseif ($line -eq 'progress=end') {
            $elapsed = [TimeSpan]::FromMilliseconds($sw.ElapsedMilliseconds).ToString("hh\:mm\:ss")
            Write-Host "`rProgress: " -NoNewline -ForegroundColor White
            Write-Host "100%" -NoNewline -ForegroundColor Green
            Write-Host " | speed " -NoNewline -ForegroundColor White
            Write-Host "$speed"x"" -NoNewline -ForegroundColor Green
            Write-Host " | elapsed= " -NoNewline -ForegroundColor White
            Write-Host "$elapsed    " -ForegroundColor Green

        }

        # Αν θες να βλέπεις ffmpeg errors, άφησέ το έτσι (δεν τυπώνει τίποτα από μόνο του).
        # Οι γραμμές progress είναι αυτές που μας νοιάζουν.
    }
    $ffmpegExitCode = $LASTEXITCODE

    $sw.Stop()
    return $ffmpegExitCode
}


# === UI helpers + Video info + Resize helpers (END) ===

$nvencAvailable = Test-H264NvencAvailable

function Get-ActiveEncoder {
    return Resolve-VideoEncoder -Preference $encoderPreference -NvencAvailable $nvencAvailable
}

function Get-EncoderName {
    $activeEncoder = Get-ActiveEncoder
    if ($activeEncoder -eq "nvenc") {
        return "NVIDIA H.264 (NVENC)"
    }
    return "H.264 (x264 software)"
}

function Get-EncoderSelectionDisplay {
    $activeName = Get-EncoderName
    if ($encoderPreference -eq "auto") {
        return "Auto -> $activeName"
    }
    if ($encoderPreference -eq "nvenc" -and -not $nvencAvailable) {
        return "NVIDIA requested -> x264 fallback (NVENC unavailable)"
    }
    return $activeName
}

function Get-QualityLabel {
    if ((Get-ActiveEncoder) -eq "nvenc") {
        return "NVENC QP"
    }
    return "x264 CRF"
}

function Get-QualityValue {
    if ((Get-ActiveEncoder) -eq "nvenc") {
        return $nvencQP
    }
    return $x264CRF
}

# ===============================
# FILE COLLECTION
# ===============================
$extensions = "*.mp4", "*.mkv", "*.avi", "*.mov", "*.wmv", "*.mpg", "*.mpeg", "*.vob", "*.ts"

# 🔸 FIX: LiteralPath
if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
    $files = @((Get-Item -LiteralPath $TargetPath))
    Set-Location -LiteralPath (Split-Path $TargetPath)
}
else {
    Set-Location -LiteralPath $TargetPath
    $files = foreach ($e in $extensions) { Get-ChildItem $e -ErrorAction SilentlyContinue }
}

if (-not $files) {
    Write-Host "No video files found." -ForegroundColor Yellow
    exit
}

# ===============================
# INFO + DEFAULTS SCREEN + SETTINGS
# ===============================
$first = $files[0].FullName
$vi = Get-VideoInfo $first

if (-not $vi.Succeeded) {
    if ($vi.ExitCode -ne 0) {
        Write-Host "FFprobe video analysis failed with exit code $($vi.ExitCode)." -ForegroundColor Red
    }
    else {
        Write-Host $vi.Error -ForegroundColor Red
    }
    exit 1
}

$interlaceInfo = Get-InterlaceInfo $first

if (-not $interlaceInfo.Succeeded) {
    Write-Host "FFmpeg interlace analysis failed with exit code $($interlaceInfo.ExitCode)." -ForegroundColor Red
    exit 1
}

# Avg bitrate for input (for UI only)
$firstBr = ffprobe -v error -show_entries format=bit_rate `
    -of default=nw=1:nk=1 "$first"

if (-not $firstBr) {
    $firstAvgMbps = "N/A"
}
else {
    $firstAvgMbps = [math]::Round(($firstBr / 1MB), 2)
}

function Get-ResizeDisplay {
    if ($resizeWidth) { return "$resizeWidth" }
    return "$($vi.Width) (input)"
}

function Print-IntroScreen {
    Write-Host ""
    Write-Host "Input file information:" -ForegroundColor Cyan
    Write-Host "-----------------------"
    Write-LabelValue "Resolution: " "$($vi.Width)x$($vi.Height)"
    Write-LabelValue "Frame rate: " "$($vi.FPS) fps"
    Write-LabelValue "Interlaced: " "$($interlaceInfo.Interlaced)"
    Write-LabelValue "Avg bitrate: " "$firstAvgMbps Mbps"

    # === [NEW] AUDIO SYNC DISPLAY IN MENU ===
    $aCheckMenu = Get-AudioSyncAnalysis -InputPath $first
    
    Write-Host "Audio Status: " -NoNewline
    if ($aCheckMenu.IsRisky) {
        Write-Host $aCheckMenu.Text -ForegroundColor Yellow
    } else {
        Write-Host $aCheckMenu.Text -ForegroundColor Green
    }
    # ========================================

    Write-Host ""
    Write-Host "Default encoding settings:" -ForegroundColor Cyan
    Write-Host "--------------------------"
    Write-LabelValue "Encoder: " "$(Get-EncoderSelectionDisplay)"
    Write-LabelValue "$(Get-QualityLabel): " "$(Get-QualityValue)"
    Write-LabelValue "Resize: " "Keep original resolution"
    Write-LabelValue "Keyframe (GOP): " "$defaultGOPSeconds second (approx)"
    Write-Host ""
    Write-Host "Press " -ForegroundColor DarkGray -NoNewline
    Write-Host "ENTER" -ForegroundColor Green -NoNewline
    Write-Host " to start encoding with defaults" -ForegroundColor DarkGray

    Write-Host "Press " -ForegroundColor DarkGray -NoNewline
    Write-Host "NUMPAD [+]" -ForegroundColor Red -NoNewline
    Write-Host " to change settings" -ForegroundColor DarkGray

}

function Show-EncoderMenu {
    while ($true) {
        Write-Host ""
        Write-Host "--- Video encoder ---" -ForegroundColor Cyan
        Write-Host "--------------------------"
        Write-Host "1) Auto (NVENC when available, otherwise x264)"
        Write-Host "2) NVIDIA H.264 (NVENC)" -NoNewline
        if (-not $nvencAvailable) {
            Write-Host " - unavailable" -ForegroundColor Yellow
        }
        else {
            Write-Host ""
        }
        Write-Host "3) H.264 (x264 software)"
        Write-Host ""
        Write-Host "Current: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$(Get-EncoderSelectionDisplay)" -ForegroundColor Green
        Write-Host "Press 1/2/3 to choose, or ESC/- to go back." -ForegroundColor DarkGray

        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::Escape -or $key.Key -eq [ConsoleKey]::Subtract) {
            return
        }

        switch ($key.KeyChar) {
            '1' {
                $script:encoderPreference = "auto"
                return
            }
            '2' {
                if (-not $nvencAvailable) {
                    Write-Host "NVENC is not functional on this system. Auto/x264 will be used." -ForegroundColor Yellow
                    Start-Sleep -Milliseconds 900
                    continue
                }
                $script:encoderPreference = "nvenc"
                return
            }
            '3' {
                $script:encoderPreference = "x264"
                return
            }
        }
    }
}

function Show-SettingsMenu {
    while ($true) {
        Write-Host ""
        Write-Host "Settings menu:" -ForegroundColor Cyan
        Write-Host "--------------------------"

        Write-Host "1) " -NoNewline
        Write-Host "$(Get-QualityLabel): " -NoNewline
        Write-Host "$(Get-QualityValue)" -ForegroundColor Green

        Write-Host "2) " -NoNewline
        Write-Host "Resize: " -NoNewline
        Write-Host "$(Get-ResizeDisplay)" -ForegroundColor Green

        Write-Host "3) " -NoNewline
        Write-Host "GOP: " -NoNewline
        Write-Host "$gopSeconds second(s)" -ForegroundColor Green

        Write-Host "4) " -NoNewline
        Write-Host "Encoder: " -NoNewline
        Write-Host "$(Get-EncoderSelectionDisplay)" -ForegroundColor Green

        Write-Host ""
        Write-Host "Press " -ForegroundColor DarkGray -NoNewline
        Write-Host "1/2/3/4" -NoNewline
        Write-Host " to edit. " -ForegroundColor DarkGray -NoNewline
        Write-Host "ENTER" -ForegroundColor Green -NoNewline
        Write-Host " to continue. " -ForegroundColor DarkGray



        $k = [Console]::ReadKey($true)

        if ($k.Key -eq [ConsoleKey]::Enter) {
            return $true
        }
        if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Subtract) {
            return $false
        }

        switch ($k.KeyChar) {
            '1' {
                while ($true) {
                    $qualityLabel = Get-QualityLabel
                    Write-Host ""
                    Write-Host "--- $qualityLabel ---" -ForegroundColor Cyan
                    Write-Host "--------------------------"                                     
                    Write-LabelValue "Current ${qualityLabel}: " "$(Get-QualityValue)"
                    Write-Host ""
                    Write-Host "Type new " -ForegroundColor DarkGray -NoNewline
                    Write-Host "$qualityLabel" -NoNewline
                    Write-Host " and press " -ForegroundColor DarkGray -NoNewline
                    Write-Host "ENTER " -ForegroundColor Green -NoNewline
                    Write-Host "Or " -ForegroundColor DarkGray -NoNewline
                    Write-Host "ESC/-" -ForegroundColor Red -NoNewline
                    Write-Host " to go back." -ForegroundColor DarkGray


                    Write-Host "New $qualityLabel value: " -NoNewline
                    $line = Read-LineOrEsc


                    if ($null -eq $line) { break }

                    if ($line -match '^\d+$' -and [int]$line -le 51) {
                        if ((Get-ActiveEncoder) -eq "nvenc") {
                            $script:nvencQP = [int]$line
                        }
                        else {
                            $script:x264CRF = [int]$line
                        }
                        break
                    }
                    else {
                        Write-Host "Invalid value." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 600
                    }
                }
            }
            '2' {
                $rw = Show-LimitWidthMenu -InputWidth $vi.Width
                if ($rw) { $script:resizeWidth = $rw } else { $script:resizeWidth = $null }
            }
            '3' {
                while ($true) {
                    Write-Host ""
                    Write-Host "--- GOP (seconds) ---" -ForegroundColor Cyan
                    Write-Host "--------------------------"                                                         
                    Write-LabelValue "Current GOP: " "$gopSeconds second(s)"
                    Write-Host ""
                    Write-Host "Type new " -ForegroundColor DarkGray -NoNewline
                    Write-Host "GOP" -NoNewline
                    Write-Host " seconds and press " -ForegroundColor DarkGray -NoNewline
                    Write-Host "ENTER " -ForegroundColor Green -NoNewline
                    Write-Host "Press " -ForegroundColor DarkGray -NoNewline
                    Write-Host "ESC/-" -ForegroundColor Red -NoNewline
                    Write-Host " to go back." -ForegroundColor DarkGray


                    Write-Host "New GOP value: " -NoNewline
                    $line = Read-LineOrEsc

                    if ($null -eq $line) { break }

                    if ($line -match '^\d+$') {
                        $script:gopSeconds = [int]$line
                        if ($script:gopSeconds -lt 1) { $script:gopSeconds = 1 }

                        break
                    }
                    else {
                        Write-Host "Invalid value." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 600
                    }
                }
            }
            '4' {
                Show-EncoderMenu
            }
        }
    }
}


if (-not $Batch) {
    # Intro loop: ENTER = defaults, NUMPAD + = settings
    while ($true) {
        Print-IntroScreen
        $k = [Console]::ReadKey($true)

        if ($k.Key -eq [ConsoleKey]::Enter) {
            break
        }

        if ($k.Key -eq [ConsoleKey]::Add -or $k.Key -eq [ConsoleKey]::OemPlus) {
            $go = Show-SettingsMenu
            if ($go) { break }
            continue
        }
    }

    # SAVE SETTINGS FOR BATCH
    $settings = @{
        EncoderPreference = $encoderPreference
        NvencQP           = $nvencQP
        X264CRF           = $x264CRF
        QP                = $nvencQP
        ResizeWidth       = $resizeWidth
        GOP               = $gopSeconds
    }
    $settings | ConvertTo-Json | Set-Content $batchSettingsFile -Encoding UTF8
}
else {
    # LOAD SETTINGS FOR BATCH
    if (Test-Path $batchSettingsFile) {
        $s = Get-Content $batchSettingsFile | ConvertFrom-Json

        if ($s.PSObject.Properties.Name -contains "EncoderPreference" -and
            @("auto", "nvenc", "x264") -contains $s.EncoderPreference) {
            $encoderPreference = [string]$s.EncoderPreference
        }
        if ($s.PSObject.Properties.Name -contains "NvencQP") {
            $nvencQP = Get-ValidatedIntegerSetting -Value $s.NvencQP -Minimum 0 -Maximum 51 `
                -DefaultValue $defaultNvencQP -Name "NVENC QP"
        }
        elseif ($s.PSObject.Properties.Name -contains "QP") {
            $nvencQP = Get-ValidatedIntegerSetting -Value $s.QP -Minimum 0 -Maximum 51 `
                -DefaultValue $defaultNvencQP -Name "NVENC QP"
        }
        if ($s.PSObject.Properties.Name -contains "X264CRF") {
            $x264CRF = Get-ValidatedIntegerSetting -Value $s.X264CRF -Minimum 0 -Maximum 51 `
                -DefaultValue $defaultX264CRF -Name "x264 CRF"
        }
        $resizeWidth = $s.ResizeWidth
        $gopSeconds = Get-ValidatedIntegerSetting -Value $s.GOP -Minimum 1 -Maximum 3600 `
            -DefaultValue $defaultGOPSeconds -Name "GOP"
    }
}

$activeEncoder = Get-ActiveEncoder
if ($encoderPreference -eq "nvenc" -and -not $nvencAvailable) {
    Write-Host "NVENC was requested but is unavailable. Falling back to x264 CRF $x264CRF." -ForegroundColor Yellow
}


# ===============================
# OUTPUT FOLDER
# ===============================
$outDir = Join-Path (Get-Location) "encoded"
# 🔸 FIX: LiteralPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

# ===============================
# PROCESS
# ===============================
$i = 0
$encodeFailureCount = 0
foreach ($f in $files) {
    $i++
    $input = $f.FullName
    $output = Join-Path $outDir ($f.BaseName + ".mp4")

    Write-Host ""
    Write-Host "[$i / $($files.Count)] Encoding: $($f.Name)" -ForegroundColor Cyan

    # bitrate cap
    $br = ffprobe -v error -show_entries format=bit_rate `
        -of default=nw=1:nk=1 "$input"
    $mbps = [math]::Max(2, [math]::Floor($br / 1MB))
    
    
    # Average Bitrate
    $avgMbps = [math]::Round(($br / 1MB), 2)

    Write-Host (
        "Input: {0}x{1} @ {2} fps | Interlaced: {3} | Avg: {4} Mbps" -f `
            $vi.Width, $vi.Height, $vi.FPS, $interlaceInfo.Interlaced, $avgMbps
    ) -ForegroundColor DarkGray -NoNewline

    if ($activeEncoder -eq "nvenc") {
        Write-Host " | Encoder: NVENC | Cap: $mbps Mbps | QP: $nvencQP" -ForegroundColor DarkGray
    }
    else {
        Write-Host " | Encoder: x264 | Preset: fast | CRF: $x264CRF" -ForegroundColor DarkGray
    }

    # === [NEW] AUDIO SYNC DISPLAY IN LOOP ===
    $aCheck = Get-AudioSyncAnalysis -InputPath $input
    Write-Host "Audio Check: " -NoNewline -ForegroundColor DarkGray
    if ($aCheck.IsRisky) {
        Write-Host $aCheck.Text -ForegroundColor Yellow
    } else {
        Write-Host $aCheck.Text -ForegroundColor Green
    }
    # ========================================

    # GOP (seconds -> frames, approximate)
    $gopFrames = [math]::Max(1, [math]::Round($gopSeconds * $vi.FPS))
    $videoEncoderArgs = Get-VideoEncoderArguments `
        -Encoder $activeEncoder `
        -NvencQP $nvencQP `
        -X264CRF $x264CRF `
        -MaxMbps $mbps `
        -GopFrames $gopFrames

    # ===============================
    # VIDEO FILTERS (resize / SAR fix)
    # ===============================

    $vfArgs = @()

    # Legacy DVD detection (anamorphic only)
    $isLegacyDVD = (
        $vi.Width -eq 720 -and
        ($vi.Height -eq 480 -or $vi.Height -eq 576) -and
        $vi.SAR -ne "1:1"
    )

    if ($isLegacyDVD) {

        # Parse DAR (e.g. "4:3", "16:9", "20:11")
        if ($vi.DAR -match '^(\d+):(\d+)$') {
            $darValue = [double]$matches[1] / [double]$matches[2]
        }
        else {
            $darValue = 0
        }

        # --- 16:9 DVD ---
        if ($darValue -gt 1.6) {

            Write-Host "Legacy DVD 16:9 detected – converting to square pixels" -ForegroundColor Red

            if ($vi.Height -eq 480) {
                # NTSC 16:9
                $vfArgs = @("-vf", "scale=854:480,setsar=1")
            }
            elseif ($vi.Height -eq 576) {
                # PAL 16:9
                $vfArgs = @("-vf", "scale=1024:576,setsar=1")
            }
        }
        else {
            # 4:3 DVD – DO NOT force 16:9
            Write-Host "Legacy DVD 4:3 detected – preserving aspect ratio" -ForegroundColor Green
            # no vfArgs → leave as-is
        }
    }
    elseif ($resizeWidth) {
        # User-selected resize
        $vfArgs = @("-vf", "scale=${resizeWidth}:-2")
    }



    $useQTGMC = $false
    $avs = $null

    if ($f.Extension -in ".mpg", ".mpeg", ".vob") {
        Write-Host "Checking interlacing (idet)..." -ForegroundColor DarkGray
        $info = Get-InterlaceInfo $input

        if (-not $info.Succeeded) {
            Write-Host "ERROR: FFmpeg interlace analysis failed with exit code $($info.ExitCode)." -ForegroundColor Red
            $encodeFailureCount++
            continue
        }

        if ($info.Interlaced) {
            Write-Host "✔ Needs deinterlacing ($($info.Field)) – using QTGMC" -ForegroundColor Green
            $useQTGMC = $true
            $avs = New-QTGMCAvs $input $info.Field
        }
        else {
            Write-Host "Progressive video – no deinterlacing needed" -ForegroundColor Gray
        }
    }
    
    $durationSec = [double](ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input")
    if (-not $durationSec -or $durationSec -le 0) { $durationSec = 0 }

    # Remove an older output before starting so it can never be mistaken for this attempt's result.
    if (Test-Path -LiteralPath $output) {
        try {
            Remove-Item -LiteralPath $output -Force -ErrorAction Stop
        }
        catch {
            Write-Host "ERROR: Existing output could not be replaced: $output" -ForegroundColor Red
            $encodeFailureCount++
            if ($avs -and (Test-Path -LiteralPath $avs)) { Remove-Item -LiteralPath $avs -Force }
            continue
        }
    }

    if ($useQTGMC) {

        $ffArgs = @(
            "-y",
            "-loglevel", "error",
            "-progress", "pipe:1",
            "-nostats",
            "-i", $avs,
            "-i", $input,
            "-map", "0:v:0",
            "-map", "1:a:0?",
            "-avoid_negative_ts", "make_zero"
        ) + $vfArgs + $videoEncoderArgs + @(
            "-c:a", "aac", "-b:a", "160k",
            "-shortest",
            "$output"
        )

        $ffmpegExitCode = Invoke-FFmpegWithProgress -FFmpegArgs $ffArgs -TotalSec $durationSec
    }

    else {

        $ffArgs = @(
            "-y",
            "-loglevel", "error",
            "-progress", "pipe:1",
            "-nostats",
            "-i", $input,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-avoid_negative_ts", "make_zero"
        ) + $vfArgs + $videoEncoderArgs + @(
            "-c:a", "aac", "-b:a", "160k",
            "$output"
        )

        $ffmpegExitCode = Invoke-FFmpegWithProgress -FFmpegArgs $ffArgs -TotalSec $durationSec
    }

    if ($ffmpegExitCode -ne 0) {
        Write-Host ""
        Write-Host "ERROR: FFmpeg encoding failed with exit code $ffmpegExitCode." -ForegroundColor Red
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue }
        if ($avs -and (Test-Path -LiteralPath $avs)) { Remove-Item -LiteralPath $avs -Force }
        $encodeFailureCount++
        continue
    }

    
    # ===============================
    # FINAL OUTPUT INFO (single line)
    # ===============================

    # 🔸 FIX: LiteralPath
    if (-not (Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -le 0) {
        Write-Host ""
        Write-Host "ERROR: FFmpeg returned success but did not create a non-empty output file." -ForegroundColor Red
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue }
        # 🔸 FIX: LiteralPath
        if ($avs -and (Test-Path -LiteralPath $avs)) { Remove-Item -LiteralPath $avs -Force }
        $encodeFailureCount++
        continue
    }

    $outRes = & ffprobe -v error -select_streams v:0 `
        -show_entries stream=width,height `
        -of csv=p=0 "$output"
    $outputProbeExitCode = $LASTEXITCODE

    if ($outputProbeExitCode -ne 0 -or -not $outRes) {
        Write-Host ""
        Write-Host "ERROR: Encoded output could not be validated by ffprobe (exit $outputProbeExitCode)." -ForegroundColor Red
        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
        if ($avs -and (Test-Path -LiteralPath $avs)) { Remove-Item -LiteralPath $avs -Force }
        $encodeFailureCount++
        continue
    }

    $outRes = $outRes -replace ',', 'x'


    # 🔸 FIX: LiteralPath
    $outSizeMB = [math]::Round((Get-Item -LiteralPath $output).Length / 1MB, 1)

    $outBr = ffprobe -v error -show_entries format=bit_rate `
        -of default=nw=1:nk=1 "$output"

    $outAvgMbps = if ($outBr) {
        [math]::Round(($outBr / 1MB), 2)
    }
    else {
        "N/A"
    }

    Write-Host ""
    Write-Host "DONE" -ForegroundColor Green -NoNewline
    Write-Host "  |  Resolution  :  " -NoNewline
    Write-Host "$outRes" -ForegroundColor Green -NoNewline
    Write-Host "  |  FileSize  :  " -NoNewline
    Write-Host "$outSizeMB MB" -ForegroundColor Green -NoNewline
    Write-Host "  |  BitRate  :  " -NoNewline
    Write-Host "$outAvgMbps Mbps" -ForegroundColor Green

    # 🔸 FIX: LiteralPath
    if ($avs -and (Test-Path -LiteralPath $avs)) { Remove-Item -LiteralPath $avs -Force }
}

if ($encodeFailureCount -gt 0) {
    Write-Host "`nEncoding completed with $encodeFailureCount failure(s)." -ForegroundColor Red
    if (-not $Batch -and -not $env:RUN_FROM_QUEUE) {
        Write-Host ""
        Read-Host "Press ENTER to close"
    }
    exit 1
}

if (-not $Batch -and -not $env:RUN_FROM_QUEUE) {
    Write-Host "`nAll encodes completed." -ForegroundColor Green
    Write-Host ""
    Read-Host "Press ENTER to close"
}
