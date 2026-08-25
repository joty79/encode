[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Detect-BadCuts.ps1'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-cut-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-CutTool {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [string[]]$ExtraArguments = @()
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-Path', $InputPath) + $ExtraArguments
    $startInfo.Arguments = (($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
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
    $healthy = Join-Path $tempRoot 'gop.mp4'
    & $ffmpeg -hide_banner -loglevel error -y -f lavfi `
        -i 'testsrc2=size=160x90:rate=25' -t 2.1 -c:v libx264 `
        -g 25 -keyint_min 25 -sc_threshold 0 -pix_fmt yuv420p $healthy
    if ($LASTEXITCODE -ne 0) { throw 'GOP fixture creation failed.' }

    $aligned = Invoke-CutTool -InputPath $healthy -ExtraArguments @('-Cuts', '00:01')
    Assert-Condition ($aligned.ExitCode -eq 0) 'Known keyframe cut must succeed.'
    Assert-Condition ($aligned.Combined -match 'properly aligned') 'Known keyframe cut must report alignment.'

    $misaligned = Invoke-CutTool -InputPath $healthy -ExtraArguments @('-Cuts', '00:00.50')
    Assert-Condition ($misaligned.ExitCode -ne 0) 'Known non-keyframe cut must return nonzero.'
    Assert-Condition ($misaligned.Combined -match 'BAD CUT') 'Known non-keyframe cut must be reported.'
    Assert-Condition ($misaligned.Combined -match '00:00:00.000|00:00:01.000') 'Misaligned cut must suggest a nearby keyframe.'

    $invalid = Invoke-CutTool -InputPath $healthy -ExtraArguments @('-Cuts', 'not-a-time')
    Assert-Condition ($invalid.ExitCode -ne 0) 'Invalid cut timestamp must return nonzero.'
    Assert-Condition ($invalid.Combined -match 'Invalid cut timestamps') 'Invalid cut timestamp must be reported.'

    $fullDecode = Invoke-CutTool -InputPath $healthy
    Assert-Condition ($fullDecode.ExitCode -eq 0) 'Healthy full decode must succeed.'
    Assert-Condition ($fullDecode.Combined -match 'Full decode completed without detected decoding errors') 'Healthy full decode must report clean decoding.'

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

    $corruptDecode = Invoke-CutTool -InputPath $corrupt
    Assert-Condition ($corruptDecode.ExitCode -ne 0) 'Corrupt full decode must return nonzero.'
    Assert-Condition ($corruptDecode.Combined -match 'Invalid NAL unit size|Error splitting') 'Corrupt full decode must preserve decoding diagnostics.'
    Assert-Condition ($corruptDecode.Combined -notmatch 'Full decode completed without detected decoding errors') 'Corrupt full decode must not report clean decoding.'

    Write-Host "PASS: $assertionCount assertions characterized cut alignment and full-decode modes."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
