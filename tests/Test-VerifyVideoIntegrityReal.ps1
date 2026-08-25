[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Verify-VideoIntegrity.ps1'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
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
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
