<#
.SYNOPSIS
    Verifies MP4/H.264 video file packet and container integrity instantly without decoding.
.DESCRIPTION
    Runs ffmpeg in copy-mode to null (-c copy -f null -) to parse packet headers and NAL unit sizes.
    Detects corruptions (like 'Invalid NAL unit size' and 'missing picture') that crash editing tools like Avidemux.
.PARAMETER Path
    The path to the input video file.
.EXAMPLE
    .\Verify-VideoIntegrity.ps1 -Path "D:\Users\joty79\Desktop\1.mp4"
#>
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$Path
)

$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
    throw "Input path is not a file: $resolvedPath"
}

try {
    $ffmpegPath = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
} catch {
    throw "ffmpeg was not found on PATH. $($_.Exception.Message)"
}

Write-Host "🔍 Analyzing packet headers and NAL sizes for: $resolvedPath" -ForegroundColor Cyan
Write-Host "🔸 Fast check mode active (no decoding, reading packet structure)..." -ForegroundColor Gray

# Configure process info
$processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = $ffmpegPath
$processStartInfo.Arguments = "-v warning -i `"$resolvedPath`" -c copy -f null -"
$processStartInfo.RedirectStandardError = $true
$processStartInfo.UseShellExecute = $false
$processStartInfo.CreateNoWindow = $true

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $process = [System.Diagnostics.Process]::Start($processStartInfo)
} catch {
    throw "Failed to start ffmpeg: $($_.Exception.Message)"
}
$reader = $process.StandardError

$corruptions = [System.Collections.Generic.List[string]]::new()
$stderrLines = [System.Collections.Generic.List[string]]::new()

# Stream reader loop
while (-not $reader.EndOfStream) {
    $line = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $stderrLines.Add($line)

    # Capture H.264 stream packet and slice validation warnings/errors
    if ($line -match "Invalid NAL unit size|missing picture|corrupt|error|invalid|failed") {
        # Ignore hwaccel or device warnings if they slip through
        if ($line -notmatch "hwaccel|device|format") {
            Write-Host "❌ CORRUPTION: $line" -ForegroundColor Red
            $corruptions.Add($line)
        }
    }
}

$process.WaitForExit()
$ffmpegExitCode = $process.ExitCode
$stopwatch.Stop()

Write-Host "------------------------------------------------------------------"
Write-Host "📊 Scan complete in $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds." -ForegroundColor Gray

if ($ffmpegExitCode -ne 0) {
    Write-Host "❌ ffmpeg failed with exit code $ffmpegExitCode. Diagnostic output:" -ForegroundColor Red
    $stderrLines | Select-Object -Unique | ForEach-Object {
        Write-Host "  $_" -ForegroundColor DarkYellow
    }
    throw "Video integrity verification failed because ffmpeg exited with code $ffmpegExitCode."
}

if ($corruptions.Count -eq 0) {
    Write-Host "✅ No packet or container corruptions detected! The file structure is healthy." -ForegroundColor Green
} else {
    Write-Host "⚠️ Warning: Found $($corruptions.Count) packet corruption errors!" -ForegroundColor DarkYellow
    Write-Host "💡 Avidemux will likely crash when opening this file." -ForegroundColor Yellow
    Write-Host "💡 Suggestion: Run remuxing or NVENC transcode on this file to clean/repair it." -ForegroundColor Yellow
}
