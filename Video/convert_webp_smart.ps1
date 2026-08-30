[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$PauseAtEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$supportedExtensions = @('.webp', '.avif', '.heic', '.heif')
$script:ffmpegPath = $null
$script:ffprobePath = $null

function Wait-ForUserIfRequested {
    if ($PauseAtEnd) {
        Write-Host ''
        Write-Host 'Press any key to close...' -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
    }
}

function Resolve-Application {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$KnownPatterns = @()
    )

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    foreach ($pattern in $KnownPatterns) {
        $candidate = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw "$Name was not found on PATH or at a known installation path."
}

function Remove-FailedOutput {
    param([Parameter(Mandatory = $true)][string]$OutputPath)

    if (Test-Path -LiteralPath $OutputPath -PathType Leaf) {
        Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-ImageFrameCount {
    param(
        [Parameter(Mandatory = $true)][string]$MagickPath,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    if (-not $script:ffprobePath) {
        try {
            $script:ffprobePath = Resolve-Application -Name 'ffprobe'
        } catch {}
    }

    # 1. Fast probe via ffprobe to detect animated containers without loading all frames into RAM
    if ($script:ffprobePath) {
        $probeOut = @(& $script:ffprobePath -v error -show_entries format=format_name -show_entries stream=codec_name -of json $InputPath 2>&1)
        if ($LASTEXITCODE -eq 0 -and $probeOut.Count -gt 0) {
            try {
                $json = ($probeOut -join "`n") | ConvertFrom-Json
                if ($json.format.format_name -match 'webp_anim|gif|apng') {
                    return 2
                }
                foreach ($s in $json.streams) {
                    if ($s.codec_name -match 'webp_anim|gif|apng') {
                        return 2
                    }
                }
            } catch {}
        }
    }

    # 2. ImageMagick identify with fallback
    $identifyOutput = @(& $MagickPath identify `
        -limit thread 4 `
        -limit memory 768MiB `
        -limit map 2GiB `
        -limit disk 2GiB `
        -limit time 240 `
        -format '%n\n' $InputPath 2>&1)
    $identifyExitCode = $LASTEXITCODE

    if ($identifyExitCode -eq 0 -and $identifyOutput.Count -gt 0) {
        $frameCountText = $identifyOutput[0].ToString().Trim()
        $frameCount = 0
        if ([int]::TryParse($frameCountText, [ref]$frameCount) -and $frameCount -ge 1) {
            return $frameCount
        }
    }

    # 3. If ImageMagick failed due to huge frame list on an animated file, check if ffprobe can decode frames
    if ($identifyOutput -join ' ' -match 'list length exceeds limit') {
        return 2
    }

    throw "Image identification failed with exit code $identifyExitCode. $($identifyOutput -join [Environment]::NewLine)"
}

function Test-HasTransparency {
    param(
        [Parameter(Mandatory = $true)][string]$MagickPath,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    $opaqueCheck = @(& $MagickPath identify -format '%[opaque]' $InputPath 2>&1)
    if ($LASTEXITCODE -eq 0 -and $opaqueCheck.Count -gt 0) {
        $val = ($opaqueCheck -join '').Trim()
        if ($val -eq 'False') {
            return $true
        }
    }
    return $false
}

function Convert-StaticImage {
    param(
        [Parameter(Mandatory = $true)][string]$MagickPath,
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$TargetFormat
    )

    $quality = if ($TargetFormat -eq 'PNG') { 95 } else { 90 }
    $convertOutput = @(& $MagickPath `
        -limit thread 4 `
        -limit memory 768MiB `
        -limit map 2GiB `
        -limit disk 2GiB `
        -limit time 240 `
        $InputPath -quality $quality $OutputPath 2>&1)
    $convertExitCode = $LASTEXITCODE

    if ($convertExitCode -ne 0) {
        Remove-FailedOutput -OutputPath $OutputPath
        throw "ImageMagick conversion failed with exit code $convertExitCode. $($convertOutput -join [Environment]::NewLine)"
    }

    $validationOutput = @(& $MagickPath identify -format '%m %w %h' $OutputPath 2>&1)
    $validationExitCode = $LASTEXITCODE
    $validationText = ($validationOutput -join ' ').Trim()
    $pattern = if ($TargetFormat -eq 'PNG') { '^PNG\s+\d+\s+\d+$' } else { '^JPEG\s+\d+\s+\d+$' }
    if ($validationExitCode -ne 0 -or $validationText -notmatch $pattern) {
        Remove-FailedOutput -OutputPath $OutputPath
        throw "Static output validation failed. $validationText"
    }
}

function Convert-AnimatedImage {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )

    if (-not $script:ffmpegPath) {
        $script:ffmpegPath = Resolve-Application -Name 'ffmpeg'
        $script:ffprobePath = Resolve-Application -Name 'ffprobe'
    }

    $convertOutput = @(& $script:ffmpegPath -hide_banner -loglevel error -n `
        -i $InputPath -map '0:v:0' -an -c:v libx264 -pix_fmt yuv420p `
        -fps_mode vfr -movflags +faststart $OutputPath 2>&1)
    $convertExitCode = $LASTEXITCODE

    if ($convertExitCode -ne 0) {
        Remove-FailedOutput -OutputPath $OutputPath
        throw "FFmpeg animation conversion failed with exit code $convertExitCode. $($convertOutput -join [Environment]::NewLine)"
    }

    $probeOutput = @(& $script:ffprobePath -v error `
        -show_entries 'stream=codec_type' -show_entries 'format=duration' `
        -of json $OutputPath 2>&1)
    $probeExitCode = $LASTEXITCODE
    if ($probeExitCode -ne 0) {
        Remove-FailedOutput -OutputPath $OutputPath
        throw "Animated output probe failed with exit code $probeExitCode."
    }

    try {
        $probe = ($probeOutput -join [Environment]::NewLine) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Remove-FailedOutput -OutputPath $OutputPath
        throw 'Animated output probe returned invalid JSON.'
    }

    $hasVideo = @($probe.streams | Where-Object { $_.codec_type -eq 'video' }).Count -gt 0
    $duration = 0.0
    $durationIsValid = [double]::TryParse(
        [string]$probe.format.duration,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$duration
    )
    if (-not $hasVideo -or -not $durationIsValid -or $duration -le 0) {
        Remove-FailedOutput -OutputPath $OutputPath
        throw 'Animated output validation did not find a positive-duration video stream.'
    }

    $decodeOutput = @(& $script:ffmpegPath -hide_banner -v error -i $OutputPath -f null - 2>&1)
    $decodeExitCode = $LASTEXITCODE
    if ($decodeExitCode -ne 0) {
        Remove-FailedOutput -OutputPath $OutputPath
        throw "Animated output full-decode validation failed with exit code $decodeExitCode. $($decodeOutput -join [Environment]::NewLine)"
    }
}

trap {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Wait-ForUserIfRequested
    exit 1
}

$Path = $Path -replace '"', ''
$magickPath = Resolve-Application -Name 'magick' `
    -KnownPatterns 'C:\Program Files\ImageMagick-*\magick.exe'

if ([System.IO.Directory]::Exists($Path)) {
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $files = @(Get-ChildItem -LiteralPath $resolvedPath -File | Where-Object {
        $supportedExtensions -contains $_.Extension.ToLowerInvariant()
    } | Sort-Object Name | ForEach-Object { $_.FullName })
}
elseif ([System.IO.File]::Exists($Path)) {
    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
    if ($supportedExtensions -notcontains $extension) {
        throw "Unsupported file type: $extension"
    }
    $files = @($resolvedPath)
}
else {
    throw "Path not found: $Path"
}

if ($files.Count -eq 0) {
    throw 'No compatible WebP, AVIF, HEIC, or HEIF files were found.'
}

$successCount = 0
$failureCount = 0

foreach ($filePath in $files) {
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $baseDir = [System.IO.Path]::GetDirectoryName($filePath)
    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $outputPath = $null
    $outputCanBeRemoved = $false

    Write-Host ''
    Write-Host "Processing: $fileName" -ForegroundColor Cyan

    try {
        $frameCount = Get-ImageFrameCount -MagickPath $magickPath -InputPath $filePath
        if ($frameCount -gt 1) {
            $outputDir = [System.IO.Path]::Combine($baseDir, 'animation')
            $outputPath = [System.IO.Path]::Combine($outputDir, "$fileBaseName.mp4")
            if ([System.IO.File]::Exists($outputPath)) {
                throw "Output already exists; nothing was overwritten: $outputPath"
            }
            $outputCanBeRemoved = $true
            [void][System.IO.Directory]::CreateDirectory($outputDir)
            Convert-AnimatedImage -InputPath $filePath -OutputPath $outputPath
            Write-Host "MP4 created: $outputPath" -ForegroundColor Green
        }
        else {
            $hasTrans = Test-HasTransparency -MagickPath $magickPath -InputPath $filePath
            $targetFormat = if ($hasTrans) { 'PNG' } else { 'JPEG' }
            $targetExt = if ($hasTrans) { 'png' } else { 'jpg' }

            $outputDir = [System.IO.Path]::Combine($baseDir, 'converted')
            $outputPath = [System.IO.Path]::Combine($outputDir, "$fileBaseName.$targetExt")
            if ([System.IO.File]::Exists($outputPath)) {
                throw "Output already exists; nothing was overwritten: $outputPath"
            }
            $outputCanBeRemoved = $true
            [void][System.IO.Directory]::CreateDirectory($outputDir)
            Convert-StaticImage -MagickPath $magickPath -InputPath $filePath -OutputPath $outputPath -TargetFormat $targetFormat
            Write-Host "$targetFormat created: $outputPath" -ForegroundColor Green
        }

        $successCount++
    }
    catch {
        if ($outputCanBeRemoved -and $outputPath) {
            Remove-FailedOutput -OutputPath $outputPath
        }
        $failureCount++
        Write-Host "FAILED: $fileName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Completed: $successCount succeeded, $failureCount failed." `
    -ForegroundColor $(if ($failureCount -eq 0) { 'Green' } else { 'Yellow' })
Wait-ForUserIfRequested

if ($failureCount -gt 0) {
    exit 1
}

exit 0
