<#
.SYNOPSIS
    Detects bad keyframe cuts/joins in MP4 video files using GPU decoding or instant keyframe matching.
.DESCRIPTION
    Supports two modes:
    1. Proactive Cut Checker (-Cuts): Instantly checks if proposed cut timestamps (e.g. "01:47", "02:12")
       align with keyframes in the source video. Runs in under a second and suggests the nearest keyframes.
    2. Video Analyzer: Decodes the video using GPU acceleration (-UseGPU) to scan for scene cuts that landed
       on non-keyframes in real-time, showing live progress.
.PARAMETER Path
    The path to the input MP4 video file.
.PARAMETER Cuts
    An array of proposed cut timestamps (e.g., "01:47", "02:12", "05:56", or in raw seconds like "132.0").
    If specified, the script instantly verifies if these points are on keyframes.
.PARAMETER UseGPU
    Enables hardware-accelerated decoding (-hwaccel auto) for the live scanning mode.
.PARAMETER SceneThreshold
    Visual scene change sensitivity threshold. Default is 0.12.
.EXAMPLE
    # Proactive Cut Check (Instant)
    .\Detect-BadCuts.ps1 -Path "D:\Videos\source.mp4" -Cuts "01:47", "02:12", "05:56"

    # Full Scan Check (Live Progress)
    .\Detect-BadCuts.ps1 -Path "D:\Videos\saved.mp4" -UseGPU
#>
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [string[]]$Cuts,

    [Parameter(Mandatory = $false)]
    [switch]$UseGPU,

    [Parameter(Mandatory = $false)]
    [double]$SceneThreshold = 0.12
)

$resolvedPath = (Resolve-Path $Path).Path

# Helper function to parse time formats (HH:MM:SS, MM:SS, or seconds)
function Convert-TimeToSeconds ([string]$timeStr) {
    $timeStr = $timeStr.Trim()
    if ($timeStr -match "^(\d+):(\d+):([\d\.]+)$") {
        return ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [double]$Matches[3]
    } elseif ($timeStr -match "^(\d+):([\d\.]+)$") {
        return ([int]$Matches[1] * 60) + [double]$Matches[2]
    } elseif ($timeStr -match "^[\d\.]+$") {
        return [double]$timeStr
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
    $keyframesOutput = ffprobe -loglevel error -select_streams v:0 -skip_frame nokey -show_entries frame=pts_time -of csv=print_section=0 $resolvedPath
    $keyframes = [System.Collections.Generic.List[double]]::new()

    foreach ($kf in $keyframesOutput) {
        $val = 0.0
        if ([double]::TryParse($kf, [ref]$val)) {
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

    foreach ($cutStr in $Cuts) {
        $cutSec = Convert-TimeToSeconds $cutStr
        if ($null -eq $cutSec) {
            Write-Host "⚠️ Invalid time format: $cutStr (Use 'MM:SS', 'HH:MM:SS', or seconds)" -ForegroundColor Yellow
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
        Write-Host "✅ All specified cuts are properly aligned with keyframes! You can safely save in Copy mode." -ForegroundColor Green
    } else {
        Write-Host "⚠️ Warning: Found $badCutsCount misaligned cuts. Adjust markers to the suggested timestamps in Avidemux." -ForegroundColor Red
    }
    return
}

# ---------------------------------------------------------
# MODE B: Full Video Decoding Scan
# ---------------------------------------------------------
Write-Host "🔍 Initializing video scan: $resolvedPath" -ForegroundColor Cyan

# Fetch metadata
$totalFrames = 0
$totalFramesInfo = ffprobe -loglevel error -select_streams v:0 -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 $resolvedPath
[int]::TryParse($totalFramesInfo, [ref]$totalFrames) | Out-Null

$duration = 0.0
$durationInfo = ffprobe -loglevel error -select_streams v:0 -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $resolvedPath
[double]::TryParse($durationInfo, [ref]$duration) | Out-Null

Write-Host "📊 Duration: $duration s | Est. Frames: $totalFrames" -ForegroundColor Gray

$hwaccelArgs = @()
if ($UseGPU) {
    Write-Host "🚀 Hardware acceleration enabled (-hwaccel auto)" -ForegroundColor Green
    $hwaccelArgs = @("-hwaccel", "auto")
}

$escapedPath = $resolvedPath.Replace(':', '\:').Replace('\', '/')
$ffmpegArgs = $hwaccelArgs + @("-i", "`"$resolvedPath`"", "-vf", "select=gt(scene\,$SceneThreshold),showinfo", "-f", "null", "-")

$processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = "ffmpeg"
$processStartInfo.Arguments = $ffmpegArgs -join " "
$processStartInfo.RedirectStandardError = $true
$processStartInfo.UseShellExecute = $false
$processStartInfo.CreateNoWindow = $true

Write-Host "🎬 Decoding stream and scanning for bad cuts in real-time..." -ForegroundColor Cyan

$process = [System.Diagnostics.Process]::Start($processStartInfo)
$reader = $process.StandardError

$badCuts = [System.Collections.Generic.List[PSObject]]::new()
$decodeErrors = [System.Collections.Generic.List[string]]::new()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    if ($line -match "Parsed_showinfo") {
        $pts = 0.0
        if ($line -match "pts_time:([\d\.-]+)") { $pts = [double]$Matches[1] }

        $isKey = $true
        if ($line -match "iskey:(\d+)") { $isKey = $Matches[1] -eq "1" }

        $type = "Unknown"
        if ($line -match "type:(\w+)") { $type = $Matches[1] }

        if (-not $isKey) {
            $formattedTime = Format-SecondsToTime $pts
            $badCuts.Add([PSCustomObject]@{
                Timestamp = $pts
                Formatted = $formattedTime
                Type      = $type
            })

            Write-Progress -Activity "Scanning Video for Bad Cuts" -Completed
            Write-Host "❌ Bad Cut detected at $formattedTime ($pts s) -> Scene change landed on a non-keyframe ($type-frame)" -ForegroundColor Red
        }
    }
    elseif ($line -match "frame=\s*(\d+)") {
        $frameNum = [int]$Matches[1]

        $currentTimeStr = "00:00:00"
        if ($line -match "time=([\d\:\.]+) ") { $currentTimeStr = $Matches[1] }

        $currentPts = 0.0
        if ($currentTimeStr -match "(\d+):(\d+):([\d\.]+)") {
            $currentPts = ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [double]$Matches[3]
        }

        $fps = 0.0
        if ($line -match "fps=\s*([\d\.]+)") { $fps = [double]$Matches[1] }

        $percent = 0
        if ($totalFrames -gt 0) {
            $percent = [math]::Min(100, [int](($frameNum / $totalFrames) * 100))
        } elseif ($duration -gt 0) {
            $percent = [math]::Min(100, [int](($currentPts / $duration) * 100))
        }

        Write-Progress -Activity "Scanning Video for Bad Cuts" -Status "Frame: $frameNum | Time: $currentTimeStr | Speed: $fps FPS" -PercentComplete $percent
    }
    else {
        if ($line -match "error|corrupt|missing|invalid|failed|slice|pps|sps|poc|reference") {
            $isIgnore = $line -match "configuration:|libavutil|libavcodec|libavformat|libswscale|libswresample|libpostproc" -or
                        $line -match "Failed setup for format" -or
                        $line -match "hwaccel" -or
                        $line -match "device creation"

            if (-not $isIgnore) {
                Write-Progress -Activity "Scanning Video for Bad Cuts" -Completed
                Write-Host "⚠️ Decoding Warning/Error: $line" -ForegroundColor Orange
                $decodeErrors.Add($line)
            }
        }
    }
}

$process.WaitForExit()
$stopwatch.Stop()
Write-Progress -Activity "Scanning Video for Bad Cuts" -Completed

Write-Host "`n📊 Scan Summary for: $(Split-Path $resolvedPath -Leaf)" -ForegroundColor Cyan
Write-Host "🔸 Processing Time: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds" -ForegroundColor Gray

if ($badCuts.Count -eq 0 -and $decodeErrors.Count -eq 0) {
    Write-Host "✅ No decoding errors or visual bad cuts found!" -ForegroundColor Green
} else {
    if ($badCuts.Count -gt 0) {
        Write-Host "`n❌ Found $($badCuts.Count) visual cuts not aligned with keyframes:" -ForegroundColor Red
        foreach ($cut in $badCuts) {
            Write-Host "  📍 At $($cut.Formatted) ($($cut.Timestamp) s) -> transition frame type: $($cut.Type)" -ForegroundColor Yellow
        }
    }

    if ($decodeErrors.Count -gt 0) {
        Write-Host "`n⚠️ Found $($decodeErrors.Count) minor bitstream warnings/errors:" -ForegroundColor Orange
        $decodeErrors | Select-Object -Unique | ForEach-Object {
            Write-Host "  $_" -ForegroundColor DarkYellow
        }
    }
}
