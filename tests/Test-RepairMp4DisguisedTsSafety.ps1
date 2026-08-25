[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Repair-Mp4DisguisedTs.ps1'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-disguised-ts-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-RepairHelper {
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

function New-VideoFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('mp4', 'mpegts')][string]$Container
    )

    $args = @(
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=25',
        '-f', 'lavfi', '-i', 'sine=frequency=900:sample_rate=48000',
        '-t', '1', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac'
    )
    if ($Container -eq 'mpegts') { $args += @('-f', 'mpegts') }
    $args += $Path
    & $script:ffmpeg @args
    if ($LASTEXITCODE -ne 0) { throw "Fixture creation failed: $Path" }
}

[void][IO.Directory]::CreateDirectory($tempRoot)
try {
    $normal = Join-Path $tempRoot 'normal.mp4'
    New-VideoFixture -Path $normal -Container mp4
    $normalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $normal).Hash
    $normalResult = Invoke-RepairHelper -InputPath $normal
    Assert-Condition ($normalResult.ExitCode -eq 0) 'Normal MP4 detection must return success.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $normal).Hash -eq $normalHash) 'Normal MP4 must remain byte-identical.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot '_TS_FIXED_MP4\normal.mp4'))) 'Normal MP4 must not create repair output.'

    $disguised = Join-Path $tempRoot 'disguised.mp4'
    New-VideoFixture -Path $disguised -Container mpegts
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $disguised).Hash
    $disguisedResult = Invoke-RepairHelper -InputPath $disguised
    $disguisedOutput = Join-Path $tempRoot '_TS_FIXED_MP4\disguised.mp4'
    Assert-Condition ($disguisedResult.ExitCode -eq 0) 'Disguised TS repair must succeed.'
    Assert-Condition (Test-Path -LiteralPath $disguisedOutput -PathType Leaf) 'Disguised TS repair must create output.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $disguised).Hash -eq $sourceHash) 'Disguised TS source must remain byte-identical.'
    $outputProbe = (& $ffprobe -v error -show_format -show_streams -of json $disguisedOutput | Out-String) | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -eq 0) 'Disguised TS output probe must succeed.'
    Assert-Condition ((@([string]$outputProbe.format.format_name -split ',') -contains 'mov') -or ([string]$outputProbe.format.format_name -match 'mp4')) 'Disguised TS output must be an MP4/MOV-style container.'
    Assert-Condition (@($outputProbe.streams | Where-Object codec_type -eq 'video').Count -eq 1) 'Disguised TS output must contain video.'
    Assert-Condition (@($outputProbe.streams | Where-Object codec_type -eq 'audio').Count -eq 1) 'Disguised TS output must contain audio.'

    $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $disguisedOutput).Hash
    $collisionResult = Invoke-RepairHelper -InputPath $disguised
    Assert-Condition ($collisionResult.ExitCode -ne 0) 'Existing repair output must return nonzero.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $disguisedOutput).Hash -eq $outputHash) 'Existing repair output must remain byte-identical.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $disguised).Hash -eq $sourceHash) 'Collision rejection must preserve the source.'

    $customInput = Join-Path $tempRoot 'custom.mp4'
    New-VideoFixture -Path $customInput -Container mpegts
    $customDir = Join-Path $tempRoot 'custom-output'
    $customOutput = Join-Path $customDir 'fixed.mp4'
    $customResult = Invoke-RepairHelper -InputPath $customInput -ExtraArguments @('-OutputPath', $customOutput)
    Assert-Condition ($customResult.ExitCode -eq 0) 'Custom output repair must succeed.'
    Assert-Condition (Test-Path -LiteralPath $customOutput -PathType Leaf) 'Custom output directory/file must be created.'
    Assert-Condition (Test-Path -LiteralPath $customInput -PathType Leaf) 'Custom output repair must preserve source.'

    $wrongOutputInput = Join-Path $tempRoot 'wrong-output.mp4'
    New-VideoFixture -Path $wrongOutputInput -Container mpegts
    $wrongOutput = Join-Path $tempRoot 'wrong-output\fixed.mkv'
    $wrongOutputResult = Invoke-RepairHelper -InputPath $wrongOutputInput -ExtraArguments @('-OutputPath', $wrongOutput)
    Assert-Condition ($wrongOutputResult.ExitCode -ne 0) 'Non-MP4 OutputPath must return nonzero.'
    Assert-Condition (-not (Test-Path -LiteralPath $wrongOutput)) 'Rejected non-MP4 OutputPath must not be created.'
    Assert-Condition (Test-Path -LiteralPath $wrongOutputInput -PathType Leaf) 'Rejected OutputPath must preserve source.'

    $invalid = Join-Path $tempRoot 'invalid.mp4'
    [IO.File]::WriteAllText($invalid, 'not media')
    $invalidResult = Invoke-RepairHelper -InputPath $invalid
    Assert-Condition ($invalidResult.ExitCode -ne 0) 'Invalid MP4 input must return nonzero.'
    Assert-Condition (Test-Path -LiteralPath $invalid -PathType Leaf) 'Invalid MP4 input must be preserved.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot '_TS_FIXED_MP4\invalid.mp4'))) 'Invalid MP4 input must leave no output.'

    $wrongExtension = Join-Path $tempRoot 'wrong.ts'
    New-VideoFixture -Path $wrongExtension -Container mpegts
    $wrongExtensionResult = Invoke-RepairHelper -InputPath $wrongExtension
    Assert-Condition ($wrongExtensionResult.ExitCode -ne 0) 'Non-MP4 input extension must return nonzero.'
    Assert-Condition (Test-Path -LiteralPath $wrongExtension -PathType Leaf) 'Non-MP4 input must be preserved.'

    $missingResult = Invoke-RepairHelper -InputPath (Join-Path $tempRoot 'missing.mp4')
    Assert-Condition ($missingResult.ExitCode -ne 0) 'Missing input must return nonzero.'

    Write-Host "PASS: $assertionCount assertions validated MP4-disguised-TS repair safety."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
