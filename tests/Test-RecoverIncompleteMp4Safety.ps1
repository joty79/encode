[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Recover-IncompleteMp4.ps1'
$registryPath = Join-Path $repoRoot 'Video\Recover-IncompleteMp4.reg'
$ffmpegCandidates = @(
    'E:\Compilers\ffmpeg\bin\ffmpeg.exe',
    (Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
)
$ffmpeg = $ffmpegCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $ffmpeg) { throw 'ffmpeg.exe is required for the safety fixture.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('encode-truncated-mp4-safety-' + [guid]::NewGuid().ToString('N'))
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-Recovery {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [string[]]$ExtraArguments = @()
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    foreach ($argument in (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-Path', $InputPath) + $ExtraArguments)) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
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
    & $ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=160x90:rate=25' `
        -f lavfi -i 'sine=frequency=800:sample_rate=48000' -t 0.5 -c:v libx264 -pix_fmt yuv420p -c:a aac $healthy
    if ($LASTEXITCODE -ne 0) { throw 'Healthy MP4 fixture creation failed.' }

    $healthyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $healthy).Hash
    $healthyTime = (Get-Item -LiteralPath $healthy).LastWriteTimeUtc
    $healthyOutput = Join-Path $tempRoot 'healthy_recovered_av.mp4'
    $healthyResult = Invoke-Recovery -InputPath $healthy
    Assert-Condition ($healthyResult.ExitCode -ne 0) 'A healthy MP4 with moov must be rejected.'
    Assert-Condition ($healthyResult.Combined -match 'moov atom') 'Healthy rejection must explain that moov already exists.'
    Assert-Condition (-not (Test-Path -LiteralPath $healthyOutput)) 'Healthy rejection must not create output.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $healthy).Hash -eq $healthyHash) 'Healthy input must remain byte-identical.'
    Assert-Condition ((Get-Item -LiteralPath $healthy).LastWriteTimeUtc -eq $healthyTime) 'Healthy input timestamp must remain unchanged.'

    $invalid = Join-Path $tempRoot 'invalid.mp4'
    [IO.File]::WriteAllBytes($invalid, [Text.Encoding]::ASCII.GetBytes('not an MP4'))
    $invalidHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $invalid).Hash
    $invalidResult = Invoke-Recovery -InputPath $invalid
    Assert-Condition ($invalidResult.ExitCode -ne 0) 'Invalid MP4 input must return nonzero.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $invalid).Hash -eq $invalidHash) 'Invalid input must remain byte-identical.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'invalid_recovered_av.mp4'))) 'Invalid input must leave no output.'

    $collisionOutput = Join-Path $tempRoot 'collision.mp4'
    [IO.File]::WriteAllText($collisionOutput, 'preserve me')
    $collisionHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $collisionOutput).Hash
    $collisionResult = Invoke-Recovery -InputPath $healthy -ExtraArguments @('-OutputPath', $collisionOutput)
    Assert-Condition ($collisionResult.ExitCode -ne 0) 'Existing OutputPath must be rejected.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $collisionOutput).Hash -eq $collisionHash) 'Existing output must remain byte-identical.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $healthy).Hash -eq $healthyHash) 'Collision rejection must preserve source.'

    $wrongExtension = Join-Path $tempRoot 'input.bin'
    [IO.File]::Copy($healthy, $wrongExtension)
    $wrongExtensionResult = Invoke-Recovery -InputPath $wrongExtension
    Assert-Condition ($wrongExtensionResult.ExitCode -ne 0) 'Non-MP4 input extension must be rejected.'
    Assert-Condition (Test-Path -LiteralPath $wrongExtension -PathType Leaf) 'Rejected non-MP4 input must be preserved.'

    $switchResult = Invoke-Recovery -InputPath $healthy -ExtraArguments @('-VideoOnly', '-RequireCleanAudioDecode')
    Assert-Condition ($switchResult.ExitCode -ne 0) 'Contradictory audio switches must be rejected.'

    $manifestPath = Join-Path $repoRoot 'config\MediaTools-Menu.json'
    $mediaToolsRegPath = Join-Path $repoRoot 'Video\Media-Tools.reg'

    Assert-Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'The MediaTools manifest must exist.'
    Assert-Condition (Test-Path -LiteralPath $mediaToolsRegPath -PathType Leaf) 'The generated Media-Tools.reg artifact must exist.'

    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    Assert-Condition ($manifestText -match '"recover-incomplete-mp4"') 'Manifest must register recover-incomplete-mp4 action.'
    Assert-Condition ($manifestText -match '"label": "Recover Incomplete MP4"') 'Manifest must use Title Case label.'

    $mediaToolsText = Get-Content -LiteralPath $mediaToolsRegPath -Raw
    Assert-Condition ($mediaToolsText -match [regex]::Escape('Recover-IncompleteMp4.ps1\" -Path \"%1\"')) 'Context command must forward the selected file to Recover-IncompleteMp4.ps1.'

    Write-Host "PASS: $assertionCount assertions validated incomplete-MP4 recovery safety."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
