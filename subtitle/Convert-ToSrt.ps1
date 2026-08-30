<#
.SYNOPSIS
    Converts subtitle files (.vtt, etc.) to validated SubRip (.srt) output with SeConv.

.DESCRIPTION
    Preserves the source, refuses an existing destination, converts through a
    unique temporary directory, validates the result with SeConv, and only then
    moves it beside the source. Supports both single files and directory scans.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\SubtitleNative.ps1')

function Convert-SingleFile {
    param([string]$FilePath, [string]$SeconvPath)

    $resolvedPath = (Resolve-Path -LiteralPath $FilePath).Path
    if ([string]::Equals([IO.Path]::GetExtension($resolvedPath), '.srt', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The source is already an SRT file.'
    }

    $outputPath = [IO.Path]::ChangeExtension($resolvedPath, '.srt')
    if (Test-Path -LiteralPath $outputPath) {
        throw "Output already exists; nothing was overwritten: $outputPath"
    }

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-subtitle-{0}" -f [guid]::NewGuid())
    [void][IO.Directory]::CreateDirectory($tempRoot)
    try {
        $tempOutput = Join-Path $tempRoot ([IO.Path]::GetFileName($outputPath))

        $convertResult = Invoke-SubtitleNative -Exe $SeconvPath -Arguments @(
            $resolvedPath, 'subrip', "--output-folder:$tempRoot",
            "--output-filename:$([IO.Path]::GetFileName($tempOutput))", '--quiet'
        )
        if ($convertResult.ExitCode -ne 0) {
            throw "SeConv conversion failed for '$resolvedPath' with exit code $($convertResult.ExitCode). $(Get-SubtitleNativeFailureText $convertResult)"
        }
        if (-not (Test-Path -LiteralPath $tempOutput -PathType Leaf) -or
            (Get-Item -LiteralPath $tempOutput).Length -le 0) {
            throw "SeConv returned success without creating a non-empty SRT file for '$resolvedPath'."
        }

        $validation = Invoke-SubtitleNative -Exe $SeconvPath -Arguments @('info', $tempOutput, '--json')
        if ($validation.ExitCode -ne 0) {
            throw "SRT validation failed for '$resolvedPath'. $(Get-SubtitleNativeFailureText $validation)"
        }

        [IO.File]::Move($tempOutput, $outputPath)
        Write-Host "Converted subtitle: $outputPath" -ForegroundColor Green
    }
    finally {
        if ($tempRoot -and (Test-Path -LiteralPath $tempRoot -PathType Container)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Subtitle path not found: $Path"
    }

    $seconv = Resolve-SubtitleTool -Name 'seconv' -KnownPaths @(
        'C:\Program Files\Subtitle Edit CLI\seconv.exe',
        'C:\Program Files\Subtitle Edit\seconv.exe'
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Convert-SingleFile -FilePath $Path -SeconvPath $seconv
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $vttFiles = @(Get-ChildItem -LiteralPath $Path -Filter '*.vtt' -File)
        if ($vttFiles.Count -eq 0) {
            Write-Host "No .vtt files found in $Path" -ForegroundColor Yellow
            return
        }
        foreach ($file in $vttFiles) {
            try {
                Convert-SingleFile -FilePath $file.FullName -SeconvPath $seconv
            }
            catch {
                Write-Warning $_.Exception.Message
            }
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
