<#
.SYNOPSIS
    Converts one subtitle file to a validated SubRip (.srt) output with SeConv.

.DESCRIPTION
    Preserves the source, refuses an existing destination, converts through a
    unique temporary directory, validates the result with SeConv, and only then
    moves it beside the source.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\SubtitleNative.ps1')

$tempRoot = $null
try {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Subtitle file not found: $Path"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    if ([string]::Equals([IO.Path]::GetExtension($resolvedPath), '.srt', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The source is already an SRT file.'
    }

    $outputPath = [IO.Path]::ChangeExtension($resolvedPath, '.srt')
    if (Test-Path -LiteralPath $outputPath) {
        throw "Output already exists; nothing was overwritten: $outputPath"
    }

    $seconv = Resolve-SubtitleTool -Name 'seconv' -KnownPaths @(
        'C:\Program Files\Subtitle Edit CLI\seconv.exe',
        'C:\Program Files\Subtitle Edit\seconv.exe'
    )
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-subtitle-{0}" -f [guid]::NewGuid())
    [void][IO.Directory]::CreateDirectory($tempRoot)
    $tempOutput = Join-Path $tempRoot ([IO.Path]::GetFileName($outputPath))

    $convertResult = Invoke-SubtitleNative -Exe $seconv -Arguments @(
        $resolvedPath, 'subrip', "--output-folder:$tempRoot",
        "--output-filename:$([IO.Path]::GetFileName($tempOutput))", '--quiet'
    )
    if ($convertResult.ExitCode -ne 0) {
        throw "SeConv conversion failed with exit code $($convertResult.ExitCode). $(Get-SubtitleNativeFailureText $convertResult)"
    }
    if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf) -or
        (Get-Item -LiteralPath $tempOutput).Length -le 0) {
        throw 'SeConv returned success without creating a non-empty SRT file.'
    }

    $validation = Invoke-SubtitleNative -Exe $seconv -Arguments @('info', $tempOutput, '--json')
    if ($validation.ExitCode -ne 0) {
        throw "SRT validation failed. $(Get-SubtitleNativeFailureText $validation)"
    }

    [IO.File]::Move($tempOutput, $outputPath)
    Write-Host "Converted subtitle: $outputPath" -ForegroundColor Green
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
