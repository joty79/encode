<#
.SYNOPSIS
    Checks proposed copy-mode cuts against keyframes and can run a full decode integrity scan.
.DESCRIPTION
    Supports two modes:
    1. Proactive Cut Checker (-Cuts): Instantly checks if proposed cut timestamps (e.g. "01:47", "02:12")
       align with keyframes in the source video. Runs in under a second and suggests the nearest keyframes.
    2. Video Analyzer: Decodes the video, optionally using GPU acceleration (-UseGPU), reports decoding
       warnings/errors, and lists scene transitions on non-keyframes as informational observations.
       A natural scene transition on a non-keyframe is not by itself proof of a bad edit.
.PARAMETER Path
    The path to the input MP4 video file.
.PARAMETER Cuts
    An array of proposed cut timestamps (e.g., "01:47", "02:12", "05:56", or in raw seconds like "132.0").
    If specified, the script instantly verifies if these points are on keyframes.
.PARAMETER UseGPU
    Enables hardware-accelerated decoding (-hwaccel auto) for the live scanning mode.
.PARAMETER SceneThreshold
    Sensitivity for the informational scene-transition report. Default is 0.12.
.EXAMPLE
    # Proactive Cut Check (Instant)
    .\Detect-BadCuts.ps1 -Path "D:\Videos\source.mp4" -Cuts "01:47", "02:12", "05:56"

    # Full Scan Check (Live Progress)
    .\Detect-BadCuts.ps1 -Path "D:\Videos\saved.mp4" -UseGPU
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [string[]]$Cuts,

    [Parameter(Mandatory = $false)]
    [switch]$UseGPU,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0.0, 1.0)]
    [double]$SceneThreshold = 0.12
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
    throw "Input path is not a file: $resolvedPath"
}

try {
    $ffprobePath = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
} catch {
    throw "ffprobe was not found on PATH. $($_.Exception.Message)"
}

# Helper function to parse time formats (HH:MM:SS, MM:SS, or seconds)
function Convert-TimeToSeconds ([string]$timeStr) {
    $timeStr = $timeStr.Trim()
    if ($timeStr -match "^(\d+):(\d+):([\d\.]+)$") {
        return ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
    } elseif ($timeStr -match "^(\d+):([\d\.]+)$") {
        return ([int]$Matches[1] * 60) + [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
    } elseif ($timeStr -match "^[\d\.]+$") {
        return [double]::Parse($timeStr, [Globalization.CultureInfo]::InvariantCulture)
    }
    return $null
}

# Helper function to format seconds to HH:MM:SS.ms
function Format-SecondsToTime ([double]$seconds) {
    $timeSpan = [Timespan]::FromSeconds($seconds)
    $ms = ($seconds - [math]::Truncate($seconds)) * 1000
    return "{0:d2}:{1:d2}:{2:d2}.{3:d3}" -f $timeSpan.Hours, $timeSpan.Minutes, $timeSpan.Seconds, [int]$ms
}

# ---------------------------------------------------------
# MODE A: Proactive Cut Check (Instant)
# ---------------------------------------------------------
if ($Cuts -and $Cuts.Count -gt 0) {
    Write-Host "🔍 Running Proactive Cut Alignment Check for: $resolvedPath" -ForegroundColor Cyan
    Write-Host "🔸 Fetching keyframe list (Instant)..." -ForegroundColor Gray

    # Fetch all keyframe timestamps instantly (demux only, no decoding)
    $keyframesOutput = & $ffprobePath -loglevel error -select_streams v:0 -skip_frame nokey -show_entries frame=pts_time -of csv=print_section=0 $resolvedPath 2>&1
    $ffprobeExitCode = $LASTEXITCODE
    if ($ffprobeExitCode -ne 0) {
        Write-Host "❌ ffprobe failed with exit code $ffprobeExitCode. Diagnostic output:" -ForegroundColor Red
        $keyframesOutput | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkYellow
        }
        throw "Cut alignment check failed because ffprobe exited with code $ffprobeExitCode."
    }

    $keyframes = [System.Collections.Generic.List[double]]::new()

    foreach ($kf in $keyframesOutput) {
        $val = 0.0
        if ([double]::TryParse($kf, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
            $keyframes.Add($val)
        }
    }

    if ($keyframes.Count -eq 0) {
        Write-Error "Could not find any keyframes. Verify file integrity."
        return
    }

    Write-Host "📊 Loaded $($keyframes.Count) keyframe timestamps. Verifying cut alignment..." -ForegroundColor Gray
    Write-Host "------------------------------------------------------------------"

    $tolerance = 0.08 # Tolerance in seconds (approx. 2 frames at 25fps)
    $badCutsCount = 0
    $invalidCutsCount = 0

    foreach ($cutStr in $Cuts) {
        $cutSec = Convert-TimeToSeconds $cutStr
        if ($null -eq $cutSec) {
            Write-Host "⚠️ Invalid time format: $cutStr (Use 'MM:SS', 'HH:MM:SS', or seconds)" -ForegroundColor Yellow
            $invalidCutsCount++
            continue
        }

        # Find closest keyframe
        $minDiff = [double]::MaxValue
        $closestKf = 0.0

        foreach ($kf in $keyframes) {
            $diff = [math]::Abs($kf - $cutSec)
            if ($diff -lt $minDiff) {
                $minDiff = $diff
                $closestKf = $kf
            }
        }

        $cutFormatted = Format-SecondsToTime $cutSec
        $kfFormatted = Format-SecondsToTime $closestKf

        if ($minDiff -le $tolerance) {
            Write-Host "✅ Cut at $cutStr ($cutFormatted) is aligned with keyframe at $kfFormatted (diff: $([math]::Round($minDiff, 3))s)" -ForegroundColor Green
        } else {
            Write-Host "❌ BAD CUT: Cut at $cutStr ($cutFormatted) is NOT on a keyframe! (diff: $([math]::Round($minDiff, 3))s)" -ForegroundColor Red
            Write-Host "   💡 Nearest keyframe is at: $kfFormatted ($closestKf seconds)" -ForegroundColor Yellow
            $badCutsCount++
        }
    }

    Write-Host "------------------------------------------------------------------"
    if ($badCutsCount -eq 0) {
        if ($invalidCutsCount -eq 0) {
            Write-Host "✅ All specified cuts are properly aligned with keyframes! You can safely save in Copy mode." -ForegroundColor Green
        }
    } else {
        Write-Host "⚠️ Warning: Found $badCutsCount misaligned cuts. Adjust markers to the suggested timestamps in Avidemux." -ForegroundColor Red
    }
    if ($invalidCutsCount -gt 0) {
        Write-Host "⚠️ Invalid cut timestamps: $invalidCutsCount." -ForegroundColor Red
    }
    if ($badCutsCount -gt 0 -or $invalidCutsCount -gt 0) {
        exit 2
    }
    return
}

# ---------------------------------------------------------
# MODE B: Full Video Decoding Scan
# ---------------------------------------------------------
Write-Host "🔍 Initializing video scan: $resolvedPath" -ForegroundColor Cyan

# Fetch metadata
$totalFrames = 0
$totalFramesInfo = & $ffprobePath -loglevel error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 $resolvedPath 2>&1
$ffprobeExitCode = $LASTEXITCODE
if ($ffprobeExitCode -ne 0) {
    Write-Host "❌ ffprobe failed while reading frame metadata (exit code $ffprobeExitCode). Diagnostic output:" -ForegroundColor Red
    $totalFramesInfo | ForEach-Object {
        Write-Host "  $_" -ForegroundColor DarkYellow
    }
    throw "Video scan failed because ffprobe exited with code $ffprobeExitCode."
}
[int]::TryParse($totalFramesInfo, [ref]$totalFrames) | Out-Null

$duration = 0.0
$durationInfo = & $ffprobePath -loglevel error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $resolvedPath 2>&1
$ffprobeExitCode = $LASTEXITCODE
if ($ffprobeExitCode -ne 0) {
    Write-Host "❌ ffprobe failed while reading duration metadata (exit code $ffprobeExitCode). Diagnostic output:" -ForegroundColor Red
    $durationInfo | ForEach-Object {
        Write-Host "  $_" -ForegroundColor DarkYellow
    }
    throw "Video scan failed because ffprobe exited with code $ffprobeExitCode."
}
[double]::TryParse([string]$durationInfo, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) | Out-Null

Write-Host "📊 Duration: $duration s | Est. Frames: $totalFrames" -ForegroundColor Gray

$hwaccelArgs = @()
if ($UseGPU) {
    Write-Host "🚀 Hardware acceleration enabled (-hwaccel auto)" -ForegroundColor Green
    $hwaccelArgs = @("-hwaccel", "auto")
}

$ffmpegArgs = $hwaccelArgs + @("-i", "`"$resolvedPath`"", "-vf", "select=gt(scene\,$SceneThreshold),showinfo", "-f", "null", "-")

try {
    $ffmpegPath = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
} catch {
    throw "ffmpeg was not found on PATH. $($_.Exception.Message)"
}

$processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = $ffmpegPath
$processStartInfo.Arguments = $ffmpegArgs -join " "
$processStartInfo.RedirectStandardError = $true
$processStartInfo.UseShellExecute = $false
$processStartInfo.CreateNoWindow = $true

Write-Host "🎬 Decoding stream and reporting scene transitions in real-time..." -ForegroundColor Cyan

try {
    $process = [System.Diagnostics.Process]::Start($processStartInfo)
} catch {
    throw "Failed to start ffmpeg: $($_.Exception.Message)"
}
$reader = $process.StandardError

$sceneTransitions = [System.Collections.Generic.List[PSObject]]::new()
$decodeErrors = [System.Collections.Generic.List[string]]::new()
$stderrLines = [System.Collections.Generic.List[string]]::new()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $stderrLines.Add($line)

    if ($line -match "Parsed_showinfo") {
        $pts = 0.0
        if ($line -match "pts_time:([\d\.-]+)") { $pts = [double]$Matches[1] }

        $isKey = $true
        if ($line -match "iskey:(\d+)") { $isKey = $Matches[1] -eq "1" }

        $type = "Unknown"
        if ($line -match "type:(\w+)") { $type = $Matches[1] }

        if (-not $isKey) {
            $formattedTime = Format-SecondsToTime $pts
            $sceneTransitions.Add([PSCustomObject]@{
                Timestamp = $pts
                Formatted = $formattedTime
                Type      = $type
            })

            Write-Progress -Activity "Decoding Video" -Completed
            Write-Host "ℹ️ Scene transition at $formattedTime ($pts s) is on a non-keyframe ($type-frame); informational only." -ForegroundColor Cyan
        }
    }
    elseif ($line -match "frame=\s*(\d+)") {
        $frameNum = [int]$Matches[1]

        $currentTimeStr = "00:00:00"
        if ($line -match "time=([\d\:\.]+) ") { $currentTimeStr = $Matches[1] }

        $currentPts = 0.0
        if ($currentTimeStr -match "(\d+):(\d+):([\d\.]+)") {
            $currentPts = ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
        }

        $fps = 0.0
        if ($line -match "fps=\s*([\d\.]+)") { $fps = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) }

        $percent = 0
        if ($totalFrames -gt 0) {
            $percent = [math]::Min(100, [int](($frameNum / $totalFrames) * 100))
        } elseif ($duration -gt 0) {
            $percent = [math]::Min(100, [int](($currentPts / $duration) * 100))
        }

        Write-Progress -Activity "Decoding Video" -Status "Frame: $frameNum | Time: $currentTimeStr | Speed: $fps FPS" -PercentComplete $percent
    }
    else {
        if ($line -match "error|corrupt|missing|invalid|failed|slice|pps|sps|poc|reference") {
            $isIgnore = $line -match "configuration:|libavutil|libavcodec|libavformat|libswscale|libswresample|libpostproc" -or
                        $line -match "Failed setup for format" -or
                        $line -match "hwaccel" -or
                        $line -match "device creation"

            if (-not $isIgnore) {
                Write-Progress -Activity "Decoding Video" -Completed
                Write-Host "⚠️ Decoding Warning/Error: $line" -ForegroundColor DarkYellow
                $decodeErrors.Add($line)
            }
        }
    }
}

$process.WaitForExit()
$ffmpegExitCode = $process.ExitCode
$stopwatch.Stop()
Write-Progress -Activity "Decoding Video" -Completed

if ($ffmpegExitCode -ne 0) {
    Write-Host "`n❌ ffmpeg scan failed with exit code $ffmpegExitCode. Diagnostic output:" -ForegroundColor Red
    $stderrLines | Select-Object -Unique | ForEach-Object {
        Write-Host "  $_" -ForegroundColor DarkYellow
    }
    throw "Bad-cut scan failed because ffmpeg exited with code $ffmpegExitCode."
}

Write-Host "`n📊 Scan Summary for: $(Split-Path $resolvedPath -Leaf)" -ForegroundColor Cyan
Write-Host "🔸 Processing Time: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor Gray

if ($sceneTransitions.Count -eq 0 -and $decodeErrors.Count -eq 0) {
    Write-Host "✅ Full decode completed without detected decoding errors." -ForegroundColor Green
} else {
    if ($sceneTransitions.Count -gt 0) {
        Write-Host "`nℹ️ Found $($sceneTransitions.Count) scene transitions on non-keyframes (informational; not proof of bad edits):" -ForegroundColor Cyan
        foreach ($cut in $sceneTransitions) {
            Write-Host "  📍 At $($cut.Formatted) ($($cut.Timestamp) s) -> transition frame type: $($cut.Type)" -ForegroundColor Yellow
        }
    }

    if ($decodeErrors.Count -gt 0) {
        Write-Host "`n⚠️ Found $($decodeErrors.Count) bitstream/decode warnings or errors:" -ForegroundColor DarkYellow
        $decodeErrors | Select-Object -Unique | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkYellow
        }
        exit 2
    }
}
