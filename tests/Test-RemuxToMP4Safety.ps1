[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\RemuxToMP4.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("encode-remux-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Resolve-Tool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction Stop | Select-Object -First 1
    return $command.Source
}

function Invoke-RemuxScript {
    param([Parameter(Mandatory = $true)][string]$InputPath)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $startInfo.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -InputFile "{1}"' -f $scriptPath, $InputPath)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Combined = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    }
}

function New-MkvFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$AudioCodec
    )

    & $script:ffmpeg -hide_banner -loglevel error -y `
        -f lavfi -i 'testsrc2=size=160x90:rate=25' `
        -f lavfi -i 'sine=frequency=700:sample_rate=48000' `
        -t 0.5 -c:v mpeg4 -c:a $AudioCodec $Path
    if ($LASTEXITCODE -ne 0) { throw "Failed to create fixture: $Path" }
}

$script:ffmpeg = Resolve-Tool -Name 'ffmpeg'
$ffprobe = Resolve-Tool -Name 'ffprobe'
New-Item -ItemType Directory -Path $tempRoot -ErrorAction Stop | Out-Null

try {
    $aacInput = Join-Path $tempRoot 'aac-input.mkv'
    $aacOutput = [System.IO.Path]::ChangeExtension($aacInput, '.mp4')
    New-MkvFixture -Path $aacInput -AudioCodec 'aac'

    $aacResult = Invoke-RemuxScript -InputPath $aacInput
    Assert-Condition ($aacResult.ExitCode -eq 0) 'AAC-compatible remux must succeed.'
    Assert-Condition (Test-Path -LiteralPath $aacInput -PathType Leaf) 'Successful remux must preserve the source MKV.'
    Assert-Condition (Test-Path -LiteralPath $aacOutput -PathType Leaf) 'Successful remux must create the MP4 output.'

    $aacCodec = & $ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $aacOutput
    Assert-Condition ($LASTEXITCODE -eq 0 -and $aacCodec -eq 'aac') 'Compatible AAC audio must remain AAC in the MP4.'

    $existingHash = (Get-FileHash -LiteralPath $aacOutput -Algorithm SHA256).Hash
    $existingResult = Invoke-RemuxScript -InputPath $aacInput
    $existingHashAfter = (Get-FileHash -LiteralPath $aacOutput -Algorithm SHA256).Hash
    Assert-Condition ($existingResult.ExitCode -ne 0) 'Existing output must make the remux fail safely.'
    Assert-Condition ($existingResult.Combined -match 'Output already exists') 'Existing-output failure must be explicit.'
    Assert-Condition ($existingHashAfter -ceq $existingHash) 'Existing output must remain byte-identical.'

    $pcmInput = Join-Path $tempRoot 'pcm-input.mkv'
    $pcmOutput = [System.IO.Path]::ChangeExtension($pcmInput, '.mp4')
    New-MkvFixture -Path $pcmInput -AudioCodec 'pcm_s16le'

    $pcmResult = Invoke-RemuxScript -InputPath $pcmInput
    Assert-Condition ($pcmResult.ExitCode -eq 0) 'PCM remux path must succeed through AAC conversion.'
    $pcmOutputCodec = & $ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 $pcmOutput
    Assert-Condition ($LASTEXITCODE -eq 0 -and $pcmOutputCodec -eq 'aac') 'PCM audio must be converted to AAC.'

    $invalidInput = Join-Path $tempRoot 'invalid.mkv'
    $invalidOutput = [System.IO.Path]::ChangeExtension($invalidInput, '.mp4')
    [System.IO.File]::WriteAllText($invalidInput, 'not media')
    $invalidResult = Invoke-RemuxScript -InputPath $invalidInput
    Assert-Condition ($invalidResult.ExitCode -ne 0) 'Invalid media must return a nonzero exit code.'
    Assert-Condition (-not (Test-Path -LiteralPath $invalidOutput)) 'Invalid media must not leave a partial MP4.'

    $missingResult = Invoke-RemuxScript -InputPath (Join-Path $tempRoot 'missing.mkv')
    Assert-Condition ($missingResult.ExitCode -ne 0) 'Missing input must return a nonzero exit code.'

    Write-Host "PASS: $assertionCount assertions validated safe MKV-to-MP4 remux behavior."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
