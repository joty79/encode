[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Repair-DamagedVideo.ps1'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-damaged-prototype-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-Prototype {
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

function New-H264Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [switch]$NoAudio
    )
    $args = @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=160x90:rate=25')
    if (-not $NoAudio) { $args += @('-f', 'lavfi', '-i', 'sine=frequency=700:sample_rate=48000') }
    $args += @('-t', '3.1', '-c:v', 'libx264', '-g', '25', '-keyint_min', '25', '-sc_threshold', '0', '-pix_fmt', 'yuv420p')
    if (-not $NoAudio) { $args += @('-c:a', 'aac') }
    $args += $OutputPath
    & $script:ffmpeg @args
    if ($LASTEXITCODE -ne 0) { throw "Fixture creation failed: $OutputPath" }
}

function Damage-H264Packet {
    param([Parameter(Mandatory = $true)][string]$InputPath)
    $packetJson = & $script:ffprobe -v error -select_streams v:0 -show_packets `
        -show_entries 'packet=pts_time,pos,size' -of json $InputPath | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Fixture packet probe failed.' }
    $packets = @((($packetJson | ConvertFrom-Json).packets))
    $packet = $packets | Where-Object {
        [double]::Parse([string]$_.pts_time, [Globalization.CultureInfo]::InvariantCulture) -ge 0.4
    } | Select-Object -First 1
    if (-not $packet) { throw 'No fixture packet found for corruption.' }
    $bytes = [IO.File]::ReadAllBytes($InputPath)
    $position = [int64]$packet.pos
    $bytes[$position] = 0x7F
    $bytes[$position + 1] = 0xFF
    $bytes[$position + 2] = 0xFF
    $bytes[$position + 3] = 0xFF
    [IO.File]::WriteAllBytes($InputPath, $bytes)
}

[void][IO.Directory]::CreateDirectory($tempRoot)
try {
    $healthy = Join-Path $tempRoot 'healthy.mp4'
    New-H264Fixture -OutputPath $healthy
    $healthyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $healthy).Hash
    $healthyDetect = Invoke-Prototype -InputPath $healthy -ExtraArguments @('-DetectOnly')
    Assert-Condition ($healthyDetect.ExitCode -eq 0) 'Healthy H.264 MP4 detection must succeed.'
    Assert-Condition ($healthyDetect.Combined -match 'No damaged H.264 packet ranges detected') 'Healthy H.264 MP4 must report no structural ranges.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $healthy).Hash -eq $healthyHash) 'Healthy detection must preserve source bytes.'

    $damaged = Join-Path $tempRoot 'damaged.mp4'
    Copy-Item -LiteralPath $healthy -Destination $damaged
    Damage-H264Packet -InputPath $damaged
    $damagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $damaged).Hash
    $damagedDetect = Invoke-Prototype -InputPath $damaged -ExtraArguments @('-DetectOnly', '-StartPadding', '0.05', '-MergeGap', '0.1')
    Assert-Condition ($damagedDetect.ExitCode -ne 0) 'Detected structural damage must return nonzero in DetectOnly mode.'
    Assert-Condition ($damagedDetect.Combined -match 'Bad packets: [1-9]\d*') 'DetectOnly must report at least one damaged packet.'
    Assert-Condition ($damagedDetect.Combined -match 'Bad packet PTS span: 00:00:00\.440') 'Detector must preserve the corrupt packet PTS.'
    Assert-Condition ($damagedDetect.Combined -match '00:00:00\.390 - 00:00:01\.000') 'StartPadding must produce the expected conservative range without resetting to zero.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'damaged_smart_repaired.mp4'))) 'DetectOnly must not create output.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $damaged).Hash -eq $damagedHash) 'DetectOnly must preserve damaged source bytes.'

    $dryRun = Invoke-Prototype -InputPath $damaged -ExtraArguments @('-DryRun', '-StartPadding', '0.05', '-MergeGap', '0.1')
    Assert-Condition ($dryRun.ExitCode -ne 0) 'DryRun with detected damage must return nonzero.'
    Assert-Condition ($dryRun.Combined -match 'Dry run complete. No files were written') 'DryRun must explicitly report no writes.'

    $output = Join-Path $tempRoot 'fixed.mp4'
    $repair = Invoke-Prototype -InputPath $damaged -ExtraArguments @(
        '-OutputPath', $output, '-StartPadding', '0.05', '-MergeGap', '0.1',
        '-Encoder', 'libx264', '-Preset', 'ultrafast', '-Cq', '23'
    )
    Assert-Condition ($repair.ExitCode -eq 0) 'Prototype repair must succeed for the characterized corrupt fixture.'
    Assert-Condition (Test-Path -LiteralPath $output -PathType Leaf) 'Prototype repair must create output.'
    Assert-Condition ($repair.Combined -match 'full-decode verification passed') 'Prototype repair must report automated verification.'
    Assert-Condition ($repair.Combined -match 'patch\s+0') 'Characterized repair must exercise a re-encoded patch segment.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $damaged).Hash -eq $damagedHash) 'Prototype repair must preserve source bytes.'
    $probe = (& $ffprobe -v error -show_format -show_streams -of json $output | Out-String) | ConvertFrom-Json
    Assert-Condition ($LASTEXITCODE -eq 0) 'Repaired output probe must succeed.'
    Assert-Condition (@($probe.streams | Where-Object codec_type -eq 'video').Count -eq 1) 'Repaired output must contain video.'
    Assert-Condition (@($probe.streams | Where-Object codec_type -eq 'audio').Count -eq 1) 'Repaired output must contain audio.'

    $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash
    $collision = Invoke-Prototype -InputPath $damaged -ExtraArguments @('-OutputPath', $output)
    Assert-Condition ($collision.ExitCode -ne 0) 'Existing prototype output must return nonzero.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash -eq $outputHash) 'Existing prototype output must remain byte-identical.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $damaged).Hash -eq $damagedHash) 'Collision rejection must preserve source.'

    $failedOutput = Join-Path $tempRoot 'failed-repair.mp4'
    $failedRepair = Invoke-Prototype -InputPath $damaged -ExtraArguments @(
        '-OutputPath', $failedOutput, '-StartPadding', '0.05', '-MergeGap', '0.1',
        '-Encoder', 'libx264', '-Preset', 'definitely-invalid', '-Cq', '23'
    )
    Assert-Condition ($failedRepair.ExitCode -ne 0) 'A failed re-encode step must return nonzero.'
    Assert-Condition (-not (Test-Path -LiteralPath $failedOutput)) 'A failed repair must remove any partial final output.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $damaged).Hash -eq $damagedHash) 'A failed repair must preserve source bytes.'

    $videoOnly = Join-Path $tempRoot 'video-only.mp4'
    New-H264Fixture -OutputPath $videoOnly -NoAudio
    $videoOnlyDetect = Invoke-Prototype -InputPath $videoOnly -ExtraArguments @('-DetectOnly')
    Assert-Condition ($videoOnlyDetect.ExitCode -eq 0) 'Healthy video-only H.264 input must be supported.'

    $mpeg2 = Join-Path $tempRoot 'mpeg2.mp4'
    & $ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=160x90:rate=25' `
        -t 1 -c:v mpeg2video $mpeg2
    if ($LASTEXITCODE -ne 0) { throw 'MPEG-2 fixture creation failed.' }
    $mpeg2Result = Invoke-Prototype -InputPath $mpeg2 -ExtraArguments @('-DetectOnly')
    Assert-Condition ($mpeg2Result.ExitCode -ne 0) 'Non-H.264/AVCC input must be rejected.'
    Assert-Condition ($mpeg2Result.Combined -match 'only supports MP4/MOV H.264 AVCC') 'Unsupported codec rejection must explain the strict scope.'

    $invalid = Join-Path $tempRoot 'invalid.mp4'
    [IO.File]::WriteAllText($invalid, 'not media')
    $invalidResult = Invoke-Prototype -InputPath $invalid -ExtraArguments @('-DetectOnly')
    Assert-Condition ($invalidResult.ExitCode -ne 0) 'Invalid media must return nonzero.'
    Assert-Condition (Test-Path -LiteralPath $invalid -PathType Leaf) 'Invalid media must be preserved.'

    Write-Host "PASS: $assertionCount assertions characterized damaged-video prototype safety."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
