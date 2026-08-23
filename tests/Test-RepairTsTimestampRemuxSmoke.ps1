[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ffmpegPath = (Get-Command -Name 'ffmpeg' -ErrorAction Stop).Source
$pwshPath = (Get-Command -Name 'pwsh' -ErrorAction Stop).Source
$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$repairScript = Join-Path -Path $repoRoot -ChildPath 'Video\Repair-TsTimestampRemux.ps1'

$systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$smokeRoot = Join-Path -Path $systemTempRoot -ChildPath ('encode-ts-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $smokeRoot | Out-Null

try {
    $keepInput = Join-Path -Path $smokeRoot -ChildPath 'keep.ts'
    $deleteInput = Join-Path -Path $smokeRoot -ChildPath 'delete.ts'

    & $ffmpegPath @(
        '-hide_banner',
        '-loglevel', 'error',
        '-y',
        '-f', 'lavfi',
        '-i', 'testsrc2=size=160x90:rate=25',
        '-f', 'lavfi',
        '-i', 'sine=frequency=1000:sample_rate=48000',
        '-t', '1',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-f', 'mpegts',
        $keepInput
    )
    $fixtureExitCode = $LASTEXITCODE
    if ($fixtureExitCode -ne 0) {
        throw "Fixture creation failed with exit code $fixtureExitCode."
    }
    Copy-Item -LiteralPath $keepInput -Destination $deleteInput

    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $keepInput -SkipInputAnalysis
    $keepExitCode = $LASTEXITCODE
    $keepOutput = Join-Path -Path $smokeRoot -ChildPath '_TS_FIXED_MP4\keep.mp4'
    if ($keepExitCode -ne 0) {
        throw "Default keep smoke failed with exit code $keepExitCode."
    }
    if (-not (Test-Path -LiteralPath $keepInput)) {
        throw 'Default keep smoke deleted the source.'
    }
    if (-not (Test-Path -LiteralPath $keepOutput)) {
        throw 'Default keep smoke did not create output.'
    }

    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $deleteInput -SkipInputAnalysis -DeleteSource
    $deleteExitCode = $LASTEXITCODE
    $deleteOutput = Join-Path -Path $smokeRoot -ChildPath '_TS_FIXED_MP4\delete.mp4'
    if ($deleteExitCode -ne 0) {
        throw "Explicit delete smoke failed with exit code $deleteExitCode."
    }
    if (Test-Path -LiteralPath $deleteInput) {
        throw 'Explicit clean delete smoke preserved the source unexpectedly.'
    }
    if (-not (Test-Path -LiteralPath $deleteOutput)) {
        throw 'Explicit delete smoke did not create output.'
    }

    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $keepInput -DeleteSource -NoVerify
    $blockedExitCode = $LASTEXITCODE
    if ($blockedExitCode -eq 0) {
        throw 'DeleteSource plus NoVerify was not rejected.'
    }
    if (-not (Test-Path -LiteralPath $keepInput)) {
        throw 'Rejected unsafe invocation changed the source.'
    }

    Write-Host 'PASS: TS remux source-preservation smoke test.' -ForegroundColor Green
}
finally {
    $resolvedSmokeRoot = [IO.Path]::GetFullPath($smokeRoot)
    $expectedPrefix = Join-Path -Path $systemTempRoot -ChildPath 'encode-ts-smoke-'
    if ((Test-Path -LiteralPath $resolvedSmokeRoot) -and $resolvedSmokeRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedSmokeRoot -Recurse -Force
    }
}
