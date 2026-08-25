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

    $existingOutputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $keepOutput).Hash
    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $keepInput -SkipInputAnalysis
    $collisionExitCode = $LASTEXITCODE
    if ($collisionExitCode -eq 0) {
        throw 'Existing default output was not rejected.'
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $keepOutput).Hash -ne $existingOutputHash) {
        throw 'Existing default output changed after collision rejection.'
    }
    if (-not (Test-Path -LiteralPath $keepInput)) {
        throw 'Collision rejection changed the source.'
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

    $invalidInput = Join-Path -Path $smokeRoot -ChildPath 'invalid.ts'
    [IO.File]::WriteAllText($invalidInput, 'not media')
    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $invalidInput -SkipInputAnalysis
    $invalidExitCode = $LASTEXITCODE
    if ($invalidExitCode -eq 0) {
        throw 'Invalid TS input returned success.'
    }
    if (-not (Test-Path -LiteralPath $invalidInput)) {
        throw 'Invalid TS input was not preserved.'
    }
    if (Test-Path -LiteralPath (Join-Path $smokeRoot '_TS_FIXED_MP4\invalid.mp4')) {
        throw 'Invalid TS input left a partial MP4.'
    }
    if (@(Get-ChildItem -LiteralPath (Join-Path $smokeRoot '_TS_FIXED_MP4') -Filter 'invalid.*.stage.mkv' -File -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Invalid TS input left a temporary MKV.'
    }

    $batchRoot = Join-Path -Path $smokeRoot -ChildPath 'batch'
    New-Item -ItemType Directory -Path $batchRoot | Out-Null
    Copy-Item -LiteralPath $keepInput -Destination (Join-Path $batchRoot 'one.ts')
    Copy-Item -LiteralPath $keepInput -Destination (Join-Path $batchRoot 'two.ts')
    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $batchRoot -AnalyzeOnly -MoveProblemFiles
    if ($LASTEXITCODE -ne 0) {
        throw 'Clean folder analyze-and-move smoke failed.'
    }
    if (Test-Path -LiteralPath (Join-Path $batchRoot '_TS_TIMESTAMP_PROBLEMS')) {
        throw 'Clean folder scan created a problem folder unexpectedly.'
    }

    $problemRoot = Join-Path -Path $smokeRoot -ChildPath 'problem-scan'
    New-Item -ItemType Directory -Path $problemRoot | Out-Null
    $problemPart = Join-Path $problemRoot 'part.ts'
    $problemInput = Join-Path $problemRoot 'bad.ts'
    & $ffmpegPath @(
        '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=25',
        '-t', '1', '-c:v', 'libx264', '-an', '-f', 'mpegts', $problemPart
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'Timestamp-problem fixture creation failed.'
    }
    $partBytes = [IO.File]::ReadAllBytes($problemPart)
    $problemBytes = New-Object byte[] ($partBytes.Length * 2)
    [Array]::Copy($partBytes, 0, $problemBytes, 0, $partBytes.Length)
    [Array]::Copy($partBytes, 0, $problemBytes, $partBytes.Length, $partBytes.Length)
    [IO.File]::WriteAllBytes($problemInput, $problemBytes)
    Remove-Item -LiteralPath $problemPart -Force
    $problemFolder = Join-Path $problemRoot '_TS_TIMESTAMP_PROBLEMS'
    New-Item -ItemType Directory -Path $problemFolder | Out-Null
    $existingProblem = Join-Path $problemFolder 'bad.ts'
    $problemSentinel = [byte[]](9, 8, 7, 6)
    [IO.File]::WriteAllBytes($existingProblem, $problemSentinel)
    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $problemRoot -AnalyzeOnly -MoveProblemFiles
    if ($LASTEXITCODE -ne 0) {
        throw 'Timestamp-problem folder scan failed.'
    }
    if (Test-Path -LiteralPath $problemInput) {
        throw 'Detected timestamp-problem file was not moved.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $problemFolder 'bad_1.ts'))) {
        throw 'Problem-file destination collision did not create a unique name.'
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($existingProblem)) -ne
        [Convert]::ToBase64String($problemSentinel)) {
        throw 'Existing problem-folder file changed during collision handling.'
    }

    & $pwshPath -NoLogo -NoProfile -File $repairScript -Path $batchRoot -SkipInputAnalysis
    if ($LASTEXITCODE -ne 0) {
        throw 'Folder repair smoke failed.'
    }
    foreach ($batchName in 'one', 'two') {
        if (-not (Test-Path -LiteralPath (Join-Path $batchRoot "$batchName.ts"))) {
            throw "Folder repair did not preserve $batchName.ts."
        }
        if (-not (Test-Path -LiteralPath (Join-Path $batchRoot "_TS_FIXED_MP4\$batchName.mp4"))) {
            throw "Folder repair did not create $batchName.mp4."
        }
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
