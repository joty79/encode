[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\convert_webp_smart.ps1'
$magick = Get-ChildItem -Path 'C:\Program Files\ImageMagick-*\magick.exe' -File |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
$ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("encode-image-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-ConversionScript {
    param([Parameter(Mandatory = $true)][string]$InputPath)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $startInfo.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Path "{1}"' -f $scriptPath, $InputPath)
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

function New-TestDirectory {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = Join-Path $tempRoot $Name
    [void][System.IO.Directory]::CreateDirectory($path)
    return $path
}

if (-not $magick -or -not (Test-Path -LiteralPath $magick -PathType Leaf)) {
    throw 'ImageMagick test dependency was not found.'
}

[void][System.IO.Directory]::CreateDirectory($tempRoot)

try {
    $staticDir = New-TestDirectory -Name 'static-webp'
    $staticInput = Join-Path $staticDir 'still.webp'
    & $magick -size 80x50 gradient:blue-yellow $staticInput
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create static WebP fixture.' }
    $staticResult = Invoke-ConversionScript -InputPath $staticInput
    $staticOutput = Join-Path $staticDir 'converted\still.jpg'
    Assert-Condition ($staticResult.ExitCode -eq 0) 'Static WebP conversion must succeed.'
    Assert-Condition (Test-Path -LiteralPath $staticOutput -PathType Leaf) 'Static WebP must create a JPG.'
    Assert-Condition ((Get-Item -LiteralPath $staticOutput).Length -gt 0) 'Static JPG must be non-empty.'
    Assert-Condition (Test-Path -LiteralPath $staticInput -PathType Leaf) 'Static source must be preserved.'
    $staticFormat = (& $magick identify -format '%m' $staticOutput 2>&1 | Out-String).Trim()
    Assert-Condition ($LASTEXITCODE -eq 0 -and $staticFormat -eq 'JPEG') 'Static output must validate as JPEG.'

    $animatedDir = New-TestDirectory -Name 'animated-webp'
    $animatedInput = Join-Path $animatedDir 'variable.webp'
    & $magick '(' -size 64x64 xc:red -set delay 10 ')' `
        '(' -size 64x64 xc:green -set delay 50 ')' -loop 0 $animatedInput
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create animated WebP fixture.' }
    $animatedResult = Invoke-ConversionScript -InputPath $animatedInput
    $animatedOutput = Join-Path $animatedDir 'animation\variable.mp4'
    Assert-Condition ($animatedResult.ExitCode -eq 0) 'Animated WebP conversion must succeed.'
    Assert-Condition (Test-Path -LiteralPath $animatedOutput -PathType Leaf) 'Animated WebP must create an MP4.'
    Assert-Condition (Test-Path -LiteralPath $animatedInput -PathType Leaf) 'Animated source must be preserved.'
    $animatedProbe = (& $ffprobe -v error -count_frames `
        -show_entries 'stream=codec_type,codec_name,nb_read_frames' `
        -show_entries 'format=duration' -of json $animatedOutput 2>&1 | Out-String) | ConvertFrom-Json
    $animatedVideo = @($animatedProbe.streams | Where-Object codec_type -eq 'video')[0]
    $animatedDuration = [double]::Parse(
        [string]$animatedProbe.format.duration,
        [Globalization.CultureInfo]::InvariantCulture
    )
    Assert-Condition ($animatedVideo.codec_name -eq 'h264') 'Animated output must use H.264.'
    Assert-Condition ([int]$animatedVideo.nb_read_frames -eq 2) 'Animated output must retain both frames.'
    Assert-Condition ([math]::Abs($animatedDuration - 0.6) -lt 0.08) 'Animated output must preserve variable frame timing.'

    $avifDir = New-TestDirectory -Name 'static-avif'
    $avifInput = Join-Path $avifDir 'still.avif'
    & $magick -size 80x50 gradient:red-blue $avifInput
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create AVIF fixture.' }
    $avifResult = Invoke-ConversionScript -InputPath $avifInput
    $avifOutput = Join-Path $avifDir 'converted\still.jpg'
    Assert-Condition ($avifResult.ExitCode -eq 0) 'Static AVIF conversion must succeed.'
    Assert-Condition (Test-Path -LiteralPath $avifOutput -PathType Leaf) 'Static AVIF must create a JPG.'
    Assert-Condition (Test-Path -LiteralPath $avifInput -PathType Leaf) 'AVIF source must be preserved.'

    $collisionDir = New-TestDirectory -Name 'collision'
    $collisionInput = Join-Path $collisionDir 'same.webp'
    & $magick -size 40x40 xc:purple $collisionInput
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create collision fixture.' }
    $collisionOutputDir = Join-Path $collisionDir 'converted'
    [void][System.IO.Directory]::CreateDirectory($collisionOutputDir)
    $collisionOutput = Join-Path $collisionOutputDir 'same.jpg'
    $sentinelBytes = [byte[]](11, 22, 33, 44, 55)
    [System.IO.File]::WriteAllBytes($collisionOutput, $sentinelBytes)
    $collisionResult = Invoke-ConversionScript -InputPath $collisionInput
    Assert-Condition ($collisionResult.ExitCode -ne 0) 'Existing output must produce a nonzero result.'
    $existingOutputBytes = [System.IO.File]::ReadAllBytes($collisionOutput)
    Assert-Condition (
        [Convert]::ToBase64String($existingOutputBytes) -eq [Convert]::ToBase64String($sentinelBytes)
    ) 'Existing output must remain byte-identical.'
    Assert-Condition (Test-Path -LiteralPath $collisionInput -PathType Leaf) 'Collision source must be preserved.'

    $mixedDir = New-TestDirectory -Name 'mixed-folder'
    $mixedGood = Join-Path $mixedDir 'good.webp'
    $mixedBad = Join-Path $mixedDir 'bad.webp'
    & $magick -size 48x32 xc:orange $mixedGood
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create mixed-folder fixture.' }
    [System.IO.File]::WriteAllText($mixedBad, 'not an image')
    $mixedResult = Invoke-ConversionScript -InputPath $mixedDir
    Assert-Condition ($mixedResult.ExitCode -ne 0) 'Mixed folder must report a nonzero result when any file fails.'
    Assert-Condition (Test-Path -LiteralPath (Join-Path $mixedDir 'converted\good.jpg') -PathType Leaf) 'Mixed folder must continue and convert the valid image.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $mixedDir 'converted\bad.jpg'))) 'Invalid image must leave no partial output.'
    Assert-Condition (Test-Path -LiteralPath $mixedGood -PathType Leaf) 'Mixed-folder valid source must be preserved.'
    Assert-Condition (Test-Path -LiteralPath $mixedBad -PathType Leaf) 'Mixed-folder invalid source must be preserved.'

    $unsupportedDir = New-TestDirectory -Name 'unsupported'
    $unsupportedFile = Join-Path $unsupportedDir 'note.txt'
    [System.IO.File]::WriteAllText($unsupportedFile, 'text')
    $unsupportedResult = Invoke-ConversionScript -InputPath $unsupportedFile
    Assert-Condition ($unsupportedResult.ExitCode -ne 0) 'Unsupported single-file input must return nonzero.'

    $emptyDir = New-TestDirectory -Name 'empty'
    $emptyResult = Invoke-ConversionScript -InputPath $emptyDir
    Assert-Condition ($emptyResult.ExitCode -ne 0) 'Folder without compatible images must return nonzero.'

    $missingResult = Invoke-ConversionScript -InputPath (Join-Path $tempRoot 'missing.webp')
    Assert-Condition ($missingResult.ExitCode -ne 0) 'Missing input must return nonzero.'

    Write-Host "PASS: $assertionCount assertions validated safe smart-image conversion behavior."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
