#requires -Version 7.0
# Explorer uses pwsh -NoExit -NoProfile -File. Read-only media inspection.
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0, ValueFromRemainingArguments)][string[]]$Paths,
    [switch]$NonInteractive, [switch]$Deep,
    [ValidateRange(0,2147483647)][double]$StartSeconds = 0,
    [ValidateRange(10,20000)][int]$MaxPackets = 5000,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 30,
    [ValidateRange(0,65535)][int]$StreamIndex,
    [string]$JsonPath, [string]$TextPath
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Probe.ps1"
. "$PSScriptRoot\lib\Metrics.ps1"
. "$PSScriptRoot\lib\Policy.ps1"
. "$PSScriptRoot\lib\render.ps1"
$ffprobe = (Get-Command ffprobe -CommandType Application | Select-Object -First 1).Source
$interactive = -not $NonInteractive -and -not [Console]::IsInputRedirected
$version = Invoke-InspectorProbe $ffprobe @('-version') 10
$report = [ordered]@{
    schemaVersion = 1; inspectorVersion = '2.4'; generatedUtc = [DateTime]::UtcNow.ToString('o')
    tool = [ordered]@{ path=$ffprobe; version=($version.stdout -split '\r?\n')[0]; powershell="$($PSVersionTable.PSVersion)" }
    scope = 'Stream/container metadata by default; packet samples only on explicit request.'
    interpretation = 'No Avidemux eligibility verdict. Import, preview, Copy and Smart Cut depend on build, selected cuts and dependencies.'
    files = [Collections.Generic.List[object]]::new(); failures = [Collections.Generic.List[object]]::new()
}
$targets = [Collections.Generic.List[object]]::new()
$extensions = '.mp4','.mkv','.avi','.mov','.wmv','.mpg','.mpeg','.vob','.ts','.m2ts','.mts','.webm','.m4v'
if ($Deep -and ($Paths.Count -ne 1 -or -not [IO.File]::Exists($Paths[0]))) {
    throw '-Deep requires one explicit file. For folders, select a file using the interactive D action.'
}
foreach ($requestedPath in $Paths) {
    try {
        $item = Get-Item -LiteralPath $requestedPath
        if ($item.PSIsContainer) {
            $found = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File | Where-Object Extension -in $extensions | Sort-Object FullName)
            if (-not $found.Count) { throw "No video files found: $requestedPath" }
            foreach ($file in $found) { $targets.Add($file) }
        } else { $targets.Add($item) }
    } catch {
        $report.failures.Add([ordered]@{ path=$requestedPath; stage='Resolve'; error=$_.Exception.Message })
        Write-Warning $_.Exception.Message
    }
}
foreach ($file in $targets) {
    try {
        $result = Invoke-InspectorProbe $ffprobe @('-v','error','-show_streams','-show_format','-of','json',$file.FullName) $TimeoutSeconds -CanCancel:$interactive
        $metadata = $result.stdout | ConvertFrom-Json
        if (-not $metadata.streams -or -not $metadata.format) { throw 'Invalid metadata: streams/format missing.' }
        $entry = New-InspectorEntry $file $metadata $result
        $report.files.Add($entry)
        if ($Deep) {
            $chosen = if ($PSBoundParameters.ContainsKey('StreamIndex')) { $StreamIndex } else { $null }
            $entry.samples.Add((Get-InspectorPacketSample $ffprobe $entry $StartSeconds $MaxPackets $TimeoutSeconds $chosen -CanCancel:$interactive))
        }
        if (-not $interactive) { Write-InspectorReport $report $entry }
    } catch {
        $report.failures.Add([ordered]@{ path=$file.FullName; stage='Inspect'; error=$_.Exception.Message })
        Write-Warning "$($file.FullName): $($_.Exception.Message)"
    }
}
if ($interactive -and $report.files.Count) {
    . "$PSScriptRoot\lib\Ui.ps1"
    Show-InspectorUi $report $ffprobe $MaxPackets $TimeoutSeconds
}
if ($JsonPath) { Export-InspectorReport $report $JsonPath Json }
if ($TextPath) { Export-InspectorReport $report $TextPath Text }
if ($report.failures.Count) { throw 'Media inspection completed with one or more failures (see report).' }
