<#
.SYNOPSIS
    Extracts the only text subtitle track in an MKV and converts it to SRT.

.DESCRIPTION
    Uses MKVToolNix to inspect the container and official Subtitle Edit SeConv
    to perform a real text-subtitle conversion. It refuses multiple tracks,
    image-based tracks, and existing outputs. The source is never modified.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$MkvFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\SubtitleNative.ps1')

$tempRoot = $null
try {
    if (-not (Test-Path -LiteralPath $MkvFile -PathType Leaf)) {
        throw "MKV file not found: $MkvFile"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $MkvFile).Path
    if (-not [string]::Equals([IO.Path]::GetExtension($resolvedPath), '.mkv', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Input must use the .mkv extension.'
    }

    $outputPath = [IO.Path]::ChangeExtension($resolvedPath, '.srt')
    if (Test-Path -LiteralPath $outputPath) {
        throw "Output already exists; nothing was overwritten: $outputPath"
    }

    $mkvmerge = Resolve-SubtitleTool -Name 'mkvmerge' -KnownPaths @(
        'C:\Program Files\MKVToolNix\mkvmerge.exe'
    )
    $seconv = Resolve-SubtitleTool -Name 'seconv' -KnownPaths @(
        'C:\Program Files\Subtitle Edit CLI\seconv.exe',
        'C:\Program Files\Subtitle Edit\seconv.exe'
    )

    $probeResult = Invoke-SubtitleNative -Exe $mkvmerge -Arguments @('-J', $resolvedPath)
    if ($probeResult.ExitCode -ne 0) {
        throw "MKV inspection failed with exit code $($probeResult.ExitCode). $(Get-SubtitleNativeFailureText $probeResult)"
    }
    try {
        $container = $probeResult.Stdout | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'MKV inspection returned invalid JSON.'
    }

    $subtitleTracks = @($container.tracks | Where-Object { $_.type -eq 'subtitles' })
    if ($subtitleTracks.Count -eq 0) {
        throw 'No subtitle tracks found.'
    }
    if ($subtitleTracks.Count -gt 1) {
        throw "Multiple subtitle tracks found ($($subtitleTracks.Count)); choose the intended track in Subtitle Edit or MKVToolNix GUI."
    }

    $track = $subtitleTracks[0]
    $codecId = if ($track.properties.PSObject.Properties['codec_id']) {
        [string]$track.properties.codec_id
    }
    else { '' }
    if ($codecId -notmatch '^S_TEXT/') {
        throw "Subtitle track is '$codecId', not a text track. OCR/image-subtitle conversion requires an explicit Subtitle Edit GUI workflow."
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-mkv-subtitle-{0}" -f [guid]::NewGuid())
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $tempOutput = Join-Path $tempRoot ([IO.Path]::GetFileName($outputPath))

    $convertResult = Invoke-SubtitleNative -Exe $seconv -Arguments @(
        $resolvedPath, 'subrip', "--output-folder:$tempRoot",
        "--output-filename:$([IO.Path]::GetFileName($tempOutput))", '--quiet'
    )
    if ($convertResult.ExitCode -ne 0) {
        throw "SeConv MKV extraction failed with exit code $($convertResult.ExitCode). $(Get-SubtitleNativeFailureText $convertResult)"
    }
    if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf) -or
        (Get-Item -LiteralPath $tempOutput).Length -le 0) {
        throw 'SeConv returned success without creating a non-empty SRT file.'
    }

    $validation = Invoke-SubtitleNative -Exe $seconv -Arguments @('info', $tempOutput, '--json')
    if ($validation.ExitCode -ne 0) {
        throw "Extracted SRT validation failed. $(Get-SubtitleNativeFailureText $validation)"
    }

    [IO.File]::Move($tempOutput, $outputPath)
    Write-Host "Subtitle extracted: $outputPath" -ForegroundColor Green
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
