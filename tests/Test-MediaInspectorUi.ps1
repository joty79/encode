#requires -Version 7.0
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path $env:TEMP ('inspector-ui-'+[guid]::NewGuid().ToString('N'))), [string]$ReportPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($helper in @('Probe','Metrics','Policy','render','Ui')) { . (Join-Path $root "Video\inspector\lib\$helper.ps1") }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$metadata=@'
{"streams":[{"index":0,"codec_type":"video","codec_name":"h264","profile":"High","codec_tag_string":"avc1","width":1920,"height":1080,"coded_width":1920,"coded_height":1080,"pix_fmt":"yuv420p","field_order":"progressive","r_frame_rate":"2997003/125000","avg_frame_rate":"2146960935/88324601","time_base":"1/2997003","start_pts":119880,"start_time":"0.04","duration":"772.021249","bit_rate":"12772609","nb_frames":"18766","has_b_frames":4,"color_range":"tv","color_space":"bt709","sample_aspect_ratio":"1:1","display_aspect_ratio":"16:9","tags":{"language":"und"}},{"index":1,"codec_type":"audio","codec_name":"aac","profile":"LC","sample_rate":"44100","channels":2,"channel_layout":"stereo","bit_rate":"139873","start_time":"0","duration":"772.08","time_base":"1/44100"}],"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"772.08","size":"1246686990","bit_rate":"12917582","tags":{"major_brand":"isom"}}}
'@ | ConvertFrom-Json
$file=[pscustomobject]@{FullName='E:\Beautiful_Girl_on_the_Beach.mp4';Length=1246686990;LastWriteTimeUtc=[datetime]'2026-09-26T00:00:00Z'}
$entry=New-InspectorEntry $file $metadata ([pscustomobject]@{arguments=@('-show_streams','-show_format',$file.FullName);stderr='';exitCode=0})
$report=[pscustomobject]@{inspectorVersion='2.4';schemaVersion=1;generatedUtc='2026-09-26T00:00:00Z';tool=[pscustomobject]@{powershell='7';version='ffprobe version test fixture';path='ffprobe.exe'};files=@($entry);failures=@();interpretation='Import, preview, Copy and Smart Cut have different requirements.'}
if ($ReportPath) { $report=Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json }
$state=@{Tab=0;File=0;Video=0;Offset=0;Status=''}
foreach ($case in @(@('D','δ','d'),@('D','Δ','d'),@('None','δ','d'),@('D','d','d'),@('D','D','d'),@('C','ψ','c'),@('J','ξ','j'),@('T','τ','t'),@('F','φ','f'),@('V','ω','v'),@('S','σ','s'),@('Q',';','q'),@('A','α','a'),@('R','ρ','r'))) {
    $shortcut=Get-InspectorShortcut ([pscustomobject]@{Key=$case[0];KeyChar=[char]$case[1]})
    if ($shortcut -ne $case[2]) { throw "Shortcut failed for $($case[0]) / $($case[1])" }
}
$handled=Update-InspectorUiNavigation $state ([pscustomobject]@{Key='V';KeyChar=[char]'ω'})
if (-not $handled -or $state.Tab -ne 1) { throw 'Greek-layout Video shortcut failed' }
$handled=Update-InspectorUiNavigation $state ([pscustomobject]@{Key='A';KeyChar=[char]'α'})
if (-not $handled -or $state.Tab -ne 5) { throw 'Optional Smart Cut shortcut failed' }
if (Update-InspectorUiNavigation $state ([pscustomobject]@{Key='D';KeyChar=[char]'δ'})) { throw 'Navigation consumed the timing action' }
Write-Host 'PASS: English/Greek shortcuts resolve; timing action reaches dispatch.'
foreach ($digit in 1..6) {
    $handled=Update-InspectorUiNavigation $state ([pscustomobject]@{Key="D$digit";KeyChar=[char][string]$digit})
    if (-not $handled -or $state.Tab -ne $digit-1) { throw "Single-key page $digit failed" }
}
$state.Offset=5
Update-InspectorUiNavigation $state ([pscustomobject]@{Key='LeftArrow';KeyChar=[char]0}) | Out-Null
if ($state.Tab -ne 4 -or $state.Offset -ne 0) { throw 'Page switch did not reset scroll' }
$manifest=[Collections.Generic.List[object]]::new()
$sequence=@(@(120,38),@(101,30),@(100,30),@(99,30),@(98,30),@(80,24),@(60,24),@(42,16),@(120,38),@(192,44),@(148,28),@(192,44))
$counter=0
foreach ($viewport in $sequence) {
    foreach ($tab in 0..7) {
        $counter++
        $state.Tab=$tab%6; $state.Offset=0; $state.Status="STATE-$counter"
        if ($tab -lt 6) { $frame=New-InspectorUiFrame $report $state $viewport[0] $viewport[1] }
        else {
            $state.Offset=4
            $modal=[Collections.Generic.List[object]]::new()
            $w=[math]::Min(112,$viewport[0]-2)
            Add-InspectorViewSection $modal $(if ($tab -eq 6) { 'EXPORT JSON' } else { 'CHOOSE FILE' }) $w
            Add-InspectorViewText $modal 'Enter confirms. Esc returns to your previous page position.' Gray $w
            $frame=New-InspectorUiFrame $report $state $viewport[0] $viewport[1] -ModalLines $modal.ToArray() -ModalKind $(if ($tab -eq 6) { 'Text' } else { 'List' })
            if ($state.Offset -ne 4) { throw 'Modal destroyed the underlying scroll position' }
        }
        $plain=$frame.ToString() -replace '\x1b\[[0-?]*[ -/]*[@-~]',''
        $rows=$plain -split '\r?\n'
        if ($rows.Count -gt $viewport[1]) { throw "Frame $counter exceeds viewport height" }
        foreach ($line in $rows) {
            if ($Host.UI.RawUI.LengthInBufferCells($line) -ge $viewport[0]) { throw "Frame $counter overflows width $($viewport[0]): $line" }
        }
        $writer=[IO.StringWriter]::new()
        $original=[Console]::Out
        try { [Console]::SetOut($writer); Write-UiFrame $frame -ForceClear:($tab -eq 0) } finally { [Console]::SetOut($original) }
        $path=Join-Path $OutputDirectory "$counter.ansi"
        [IO.File]::WriteAllText($path,$writer.ToString(),[Text.UTF8Encoding]::new($false))
        $manifest.Add([ordered]@{width=$viewport[0];height=$viewport[1];path=$path;state=$counter;tab=$tab})
    }
}
$manifestPath=Join-Path $OutputDirectory 'manifest.json'
$manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "PASS: single-key navigation; $counter frames fit width/height. Replay manifest: $manifestPath"
