param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$UseSettsRepair,

    [Parameter()]
    [switch]$KeepTemp,

    [Parameter()]
    [switch]$NoVerify,

    [Parameter()]
    [switch]$PauseAtEnd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Wait-ForUserIfRequested {
    if ($PauseAtEnd) {
        Write-Host ''
        Write-Host 'Press any key to close...' -ForegroundColor Gray
        [void][System.Console]::ReadKey($true)
    }
}

trap {
    Write-Host ''
    Write-Host ('ERROR: {0}' -f $_.Exception.Message) -ForegroundColor Red
    Wait-ForUserIfRequested
    exit 1
}

function Resolve-RequiredCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Required command '$Name' was not found in PATH."
    }

    return $command.Source
}

function Write-ToolHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ''
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host ('🎞️  {0}' -f $Title) -ForegroundColor Cyan
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
}

function Format-Seconds {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Seconds
    )

    $span = [TimeSpan]::FromSeconds([Math]::Max(0.0, $Seconds))
    if ($span.TotalHours -ge 1) {
        return '{0:00}:{1:00}:{2:00}.{3:000}' -f [Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds, $span.Milliseconds
    }

    return '{0:00}:{1:00}.{2:000}' -f $span.Minutes, $span.Seconds, $span.Milliseconds
}

function Test-MpegTsFormatName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FormatName
    )

    return (($FormatName -split ',') -contains 'mpegts')
}

$resolvedInputPath = (Resolve-Path -LiteralPath $Path).Path
$extension = [IO.Path]::GetExtension($resolvedInputPath)
if (-not [string]::Equals($extension, '.mp4', [StringComparison]::OrdinalIgnoreCase)) {
    throw "This helper is only for .mp4 files that are actually MPEG-TS containers. Input was: $resolvedInputPath"
}

$ffprobe = Resolve-RequiredCommand -Name 'ffprobe'
$pwsh = Resolve-RequiredCommand -Name 'pwsh'
$metadataJson = & $ffprobe -hide_banner -v error -show_format -show_streams -of json $resolvedInputPath
if ($LASTEXITCODE -ne 0) {
    throw "ffprobe metadata read failed for '$resolvedInputPath'."
}

$metadata = $metadataJson | ConvertFrom-Json
$formatName = [string]$metadata.format.format_name
$duration = 0.0
[void][double]::TryParse([string]$metadata.format.duration, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration)

Write-ToolHeader -Title 'MP4 Disguised TS Repair'
Write-Host ('📄 Input:     {0}' -f $resolvedInputPath)
Write-Host ('📦 Container: {0}' -f $formatName)
Write-Host ('⏱️  Duration:  {0}' -f (Format-Seconds -Seconds $duration))

if (-not (Test-MpegTsFormatName -FormatName $formatName)) {
    Write-Host ''
    Write-Host '✅ This is a real MP4/MOV-style container. TS remux repair is not applicable.' -ForegroundColor Green
    Write-Host '   Use the damaged-video workflow only if there are visual/corrupt-frame problems.' -ForegroundColor Gray
    Wait-ForUserIfRequested
    exit 0
}

Write-Host ''
Write-Host '⚠️  Extension is .mp4, but the real container is MPEG-TS.' -ForegroundColor Yellow
Write-Host '🔧 Running no-reencode TS -> MKV -> MP4 repair. Source file will be kept.' -ForegroundColor Cyan
if (-not $UseSettsRepair) {
    Write-Host '🧭 MP4-disguised-TS mode keeps original packet cadence; setts repair is skipped.' -ForegroundColor Cyan
}

$scriptDirectory = Split-Path -Parent $PSCommandPath
$tsRepairScript = Join-Path -Path $scriptDirectory -ChildPath 'Repair-TsTimestampRemux.ps1'
if (-not (Test-Path -LiteralPath $tsRepairScript)) {
    throw "Required helper not found: $tsRepairScript"
}

$repairArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $tsRepairScript,
    '-Path', $resolvedInputPath,
    '-SkipInputAnalysis',
    '-KeepSource'
)

if (-not $UseSettsRepair) {
    $repairArgs += '-SkipSettsRepair'
}

if ($OutputPath) {
    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if (-not [string]::Equals([IO.Path]::GetExtension($resolvedOutputPath), '.mp4', [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputPath must use the .mp4 extension: $resolvedOutputPath"
    }
    $outputDirectory = [IO.Path]::GetDirectoryName($resolvedOutputPath)
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }

    $repairArgs += @('-OutputPath', $resolvedOutputPath)
}

if ($KeepTemp) {
    $repairArgs += '-KeepTemp'
}

if ($NoVerify) {
    $repairArgs += '-NoVerify'
}

& $pwsh @repairArgs
if ($LASTEXITCODE -ne 0) {
    throw "MP4 disguised TS repair failed with exit code $LASTEXITCODE."
}

Wait-ForUserIfRequested
