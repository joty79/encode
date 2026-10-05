[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Verify-VideoIntegrity.ps1'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
. (Join-Path $repoRoot 'Video\lib\MediaTimeline.ps1')
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-integrity-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-IntegrityCheck {
    param([Parameter(Mandatory = $true)][string]$InputPath)

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $startInfo.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Path "{1}"' -f $scriptPath, $InputPath)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Combined = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    }
}

[void][IO.Directory]::CreateDirectory($tempRoot)
try {
    $healthy = Join-Path $tempRoot 'healthy.mp4'
    & $ffmpeg -hide_banner -loglevel error -y -f lavfi `
        -i 'testsrc2=size=160x90:rate=25' -t 1 -c:v libx264 -pix_fmt yuv420p $healthy
    if ($LASTEXITCODE -ne 0) { throw 'Healthy fixture creation failed.' }

    $healthyResult = Invoke-IntegrityCheck -InputPath $healthy
    Assert-Condition ($healthyResult.ExitCode -eq 0) 'Healthy H.264 MP4 must pass the fast integrity scan.'
    Assert-Condition ($healthyResult.Combined -match 'No packet or container warnings') 'Healthy H.264 MP4 must report a clean fast scan.'
    Assert-Condition ($healthyResult.Combined -match 'No suspicious timeline gaps') 'Healthy B-frame presentation reordering must not trigger a timing warning.'

    $gapped = Join-Path $tempRoot 'stretched duration.mp4'
    & $ffmpeg -hide_banner -loglevel error -n -f lavfi `
        -i 'testsrc2=size=160x90:rate=25:duration=1' -f lavfi `
        -i 'sine=frequency=440:sample_rate=48000:duration=1' `
        -vf "setpts='PTS+2/TB*gte(T,0.5)'" -af "asetpts='PTS+2/TB*gte(T,0.5)'" `
        -fps_mode vfr -c:v libx264 -bf 0 -c:a aac $gapped
    if ($LASTEXITCODE -ne 0) { throw 'Stretched-duration fixture creation failed.' }
    $gappedProbe = & $ffprobe -v error -select_streams v:0 -show_entries packet=duration_time -of json $gapped | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Stretched-duration fixture probe failed.' }
    $stretchedPackets = @(($gappedProbe | ConvertFrom-Json).packets | Where-Object { [double]$_.duration_time -gt 1.5 })
    Assert-Condition ($stretchedPackets.Count -gt 0) 'Fixture must contain inflated packet duration which conceals a gap from packet-end checks.'
    $timing = Get-MediaTimelineReport -Ffprobe $ffprobe -InputPath $gapped
    $videoTiming = $timing.Streams | Where-Object { $_.Type -eq 'video' }
    $audioTiming = $timing.Streams | Where-Object { $_.Type -eq 'audio' }
    Assert-Condition ($videoTiming.GapCount -eq 1 -and [Math]::Abs($videoTiming.GapExcessSeconds - 2.0) -lt 0.01) 'Video must report the two-second presentation gap despite inflated duration.'
    Assert-Condition ($audioTiming.GapCount -eq 1 -and $audioTiming.GapExcessSeconds -gt 1.9) 'Audio gaps must also be detected independently of declared packet duration.'
    $gappedResult = Invoke-IntegrityCheck -InputPath $gapped
    Assert-Condition ($gappedResult.ExitCode -eq 3) 'Decodable media with timing gaps must return timeline-review exit code 3.'
    Assert-Condition ($gappedResult.Combined -match 'TIMELINE REVIEW REQUIRED') 'Timing gaps must produce an explicit warning.'
    Assert-Condition ($gappedResult.Combined -match 'No packet or container warnings') 'The fixture must distinguish clean packet structure from bad timing.'

    $repairScript = Join-Path $repoRoot 'Video\Repair-DamagedVideo.ps1'
    $currentShell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $repairDiagnostic = & $currentShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $repairScript -Path $gapped -DetectOnly 2>&1 | Out-String
    $repairDiagnosticExitCode = $LASTEXITCODE
    Assert-Condition ($repairDiagnosticExitCode -eq 3 -and $repairDiagnostic -match 'TIMELINE REVIEW REQUIRED') 'Repair detection must not call a packet-clean but gapped file healthy.'

    $corrupt = Join-Path $tempRoot 'corrupt.mp4'
    $bytes = [IO.File]::ReadAllBytes($healthy)
    $mdatMarker = -1
    for ($index = 4; $index -lt ($bytes.Length - 8); $index++) {
        if ($bytes[$index] -eq 0x6D -and $bytes[$index + 1] -eq 0x64 -and
            $bytes[$index + 2] -eq 0x61 -and $bytes[$index + 3] -eq 0x74) {
            $mdatMarker = $index
            break
        }
    }
    Assert-Condition ($mdatMarker -gt 0) 'Fixture must contain an mdat box.'
    $payloadStart = $mdatMarker + 4
    $bytes[$payloadStart] = 0x7F
    $bytes[$payloadStart + 1] = 0xFF
    $bytes[$payloadStart + 2] = 0xFF
    $bytes[$payloadStart + 3] = 0xFF
    [IO.File]::WriteAllBytes($corrupt, $bytes)

    $corruptResult = Invoke-IntegrityCheck -InputPath $corrupt
    Assert-Condition ($corruptResult.ExitCode -ne 0) 'Corrupt NAL length must produce a nonzero result.'
    Assert-Condition ($corruptResult.Combined -match 'Invalid NAL unit size') 'Corrupt NAL length must be reported.'
    Assert-Condition ($corruptResult.Combined -notmatch 'No packet or container warnings') 'Corrupt input must not report a clean fast scan.'

    Write-Host "PASS: $assertionCount assertions validated the real fast-integrity scan."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolvedTempRoot = (Resolve-Path -LiteralPath $tempRoot).Path
        $expectedTempRoot = [IO.Path]::GetFullPath($tempRoot)
        $allowedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ($resolvedTempRoot -ne $expectedTempRoot -or -not $resolvedTempRoot.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedTempRoot) -notlike 'encode-integrity-tests-*') { throw 'Unsafe test cleanup path.' }
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
