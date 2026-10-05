#requires -Version 7.0
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($helper in @('Probe','Metrics','Policy','render')) { . (Join-Path $root "Video/inspector/lib/$helper.ps1") }
function Assert-Diagnosis($Condition,$Message) {
    if (-not $Condition) { throw $Message }; Write-Host "PASS: $Message"
}
function New-Case {
    $metadata='{"streams":[{"index":0,"codec_type":"video","codec_name":"h264","profile":"High","pix_fmt":"yuv420p","width":1920,"height":1080,"field_order":"progressive","sample_aspect_ratio":"1:1","r_frame_rate":"2997003/125000","avg_frame_rate":"2997003/125000","nal_length_size":"4"}],"format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"30"}}' | ConvertFrom-Json
    New-InspectorEntry ([pscustomobject]@{FullName='E:\fixture.mp4';Length=1000000;LastWriteTimeUtc=[datetime]::UtcNow}) $metadata ([pscustomobject]@{arguments=@();exitCode=0;stderr=''})
}
$entry=New-Case
$d=Get-InspectorDiagnosis $entry
Assert-Diagnosis ($d.status -eq 'Unchecked' -and $d.findings.Count -eq 0) 'Exact large H264 rational is accepted without inventing eligibility'
Assert-Diagnosis ($d.limitation -match 'No project' -and $d.rulesVersion -eq 'avidemux-custom-2026-09-26.1') 'Rule version and untested selection/build boundaries are explicit'
$entry.streams[0].pix_fmt='yuv420p10le';$entry.streams[0].bitDepth=10
$d=Get-InspectorDiagnosis $entry
Assert-Diagnosis ($d.status -eq 'Restriction' -and $d.findings.id -contains 'video.pixels') 'H264 10-bit explains the repair restriction'
$entry.streams[0].codec_name='hevc';$entry.streams[0].profile='Main 10'
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).status -eq 'Unchecked') 'HEVC Main 10 does not inherit the H264 8-bit restriction'
$entry.streams[0].color_transfer='smpte2084'
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings.id -contains 'video.hdr') 'PQ is detected without requiring side data'
$entry=New-Case;$entry.streams[0].side_data_list=@([pscustomobject]@{side_data_type='Display Matrix';rotation=90})
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings.id -contains 'video.side-data') 'Rotation metadata is explained'
$entry=New-Case;$entry.streams[0].field_order='tt';$entry.streams[0].sample_aspect_ratio='4:3'
$d=Get-InspectorDiagnosis $entry
Assert-Diagnosis ($d.findings.id -contains 'video.interlaced' -and $d.findings.id -contains 'video.aspect') 'Interlace and non-square pixels remain separate reasons'
$entry=New-Case;$entry.streams[0].field_order=$null;$entry.streams[0].pix_fmt=$null;$entry.streams[0].profile=$null
$d=Get-InspectorDiagnosis $entry
Assert-Diagnosis ($d.status -eq 'Review' -and $d.findings.id -contains 'metadata.incomplete') 'Missing metadata is unknown, not a claimed format rejection'
$entry=New-Case;$entry.streams[0].codec_name='vp9'
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings[0].severity -eq 'Unknown') 'Other custom repair codecs are unassessed, not unsupported'
$entry=New-Case;$entry.streams=@()
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings.id -contains 'video.absent') 'Audio-only input has a clear explanation'
$entry=New-Case;$entry.streams+=($entry.streams[0] | Select-Object *)
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings.id -contains 'video.multiple') 'Multiple video tracks are detected'
$entry=New-Case;$entry.path='E:\fixture.ts'
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings.id -contains 'container.extension') 'Container gate matches the custom filename-extension check'
$entry=New-Case;$entry.streams[0].averageFps=Get-InspectorRational '25/1'
$d=Get-InspectorDiagnosis $entry
Assert-Diagnosis ($d.status -eq 'Review' -and $d.findings.id -contains 'timing.rate-difference') 'Different rates request measurement without a VFR verdict'
$packets=@([pscustomobject]@{pts=0;dts=0},[pscustomobject]@{pts=1;dts=1},[pscustomobject]@{pts=40000;dts=40000})
$entry.samples.Add([pscustomobject]@{streamIndex=0;measured=(Measure-InspectorPackets $packets ([pscustomobject]@{time_base='1/1000000';r_frame_rate='25/1'}))})
$d=Get-InspectorDiagnosis $entry
Assert-Diagnosis ($d.status -eq 'Review' -and $d.findings.id -contains 'timing.anomaly' -and $d.findings.id -notcontains 'timing.rate-difference') 'Measured anomaly supersedes metadata suspicion without rejecting the whole file'
$entry=New-Case
$packets=@(0..9 | ForEach-Object { [pscustomobject]@{pts=($_*40000);dts=($_*40000)} })
$entry.samples.Add([pscustomobject]@{streamIndex=0;measured=(Measure-InspectorPackets $packets ([pscustomobject]@{time_base='1/1000000';r_frame_rate='25/1'}))})
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).status -eq 'Unchecked') 'Clean bounded sample never grants whole-file approval'
$entry.provenance.stderr='decoder diagnostic'
Assert-Diagnosis ((Get-InspectorDiagnosis $entry).findings.id -contains 'probe.diagnostics') 'Reader diagnostics are not hidden behind a clean summary'
$report=[pscustomobject]@{files=@($entry)}
Update-InspectorDiagnoses $report
Assert-Diagnosis ($entry.diagnosis.rulesVersion -eq 'avidemux-custom-2026-09-26.1') 'Structured diagnosis is attached for JSON export'
Write-Host 'PASS: Diagnosis regression suite complete.'
