#requires -Version 7.0
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $env:TEMP ('encode-inspector-tests-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$inspector = Join-Path $root 'Video\inspector\inspect.ps1'
. (Join-Path $root 'Video\inspector\lib\Probe.ps1')
. (Join-Path $root 'Video\inspector\lib\Metrics.ps1')
. (Join-Path $root 'Video\inspector\lib\Policy.ps1')
. (Join-Path $root 'Video\inspector\lib\render.ps1')
function Assert-That($Condition,[string]$Message) { if (-not $Condition) { throw "ASSERT: $Message" }; Write-Host "PASS: $Message" }
function Invoke-Fixture([string[]]$Arguments) {
    & ffmpeg -hide_banner -loglevel error -nostdin -n @Arguments
    $code=$LASTEXITCODE
    if ($code -ne 0) { throw "Fixture FFmpeg exit $code" }
}
function Invoke-Case([string]$Name,[string[]]$Arguments,[int]$ExpectedExit=0) {
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $inspector @Arguments 2>&1
    $code=$LASTEXITCODE
    $output | Out-String | Set-Content -LiteralPath (Join-Path $OutputDirectory "$Name.log")
    Assert-That ($code -eq $ExpectedExit) "$Name process exit $ExpectedExit (actual $code)"
}
New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop | Out-Null
Write-Host "Artifacts: $OutputDirectory"
$cfr = Join-Path $OutputDirectory 'Ελληνικά space [1] & quote''s.mp4'
$multi = Join-Path $OutputDirectory 'multiple tracks.mkv'
$irregular = Join-Path $OutputDirectory 'irregular.mkv'
$subtitle = Join-Path $OutputDirectory 'captions.srt'
"1`n00:00:00,000 --> 00:00:01,000`nFixture" | Set-Content -LiteralPath $subtitle
Invoke-Fixture @('-f','lavfi','-i','testsrc2=size=160x90:rate=25:duration=2','-c:v','libx264','-g','25','-bf','2',$cfr)
Invoke-Fixture @('-i',$cfr,'-f','lavfi','-i','sine=frequency=440:duration=2','-i',$subtitle,'-map','0:v','-map','1:a','-map','1:a','-map','2:s','-c:v','copy','-c:a','aac','-c:s','srt','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=ell',$multi)
Invoke-Fixture @('-f','lavfi','-i','testsrc2=size=160x90:rate=25:duration=2','-vf','setpts=PTS+if(gte(N\,20)\,0.2/TB\,0)','-fps_mode','vfr','-c:v','libx264','-bf','0',$irregular)
$cfrReport = Join-Path $OutputDirectory 'cfr.json'
Invoke-Case 'cfr' @($cfr,'-NonInteractive','-Deep','-MaxPackets','100','-JsonPath',$cfrReport)
$c = Get-Content -LiteralPath $cfrReport -Raw | ConvertFrom-Json
Assert-That ($c.files[0].streams.Count -eq 1) 'No-audio fixture has one video stream'
Assert-That ($c.files[0].samples[0].measured.nominalDeviations -eq 0) 'Known 25 fps packet sample has no interval deviations'
Assert-That ($c.files[0].samples[0].measured.ptsBackwardsInPacketOrder -gt 0) 'B-frame PTS reordering observed without false interval anomaly'
Assert-That ($c.files[0].path -eq $cfr) 'Unicode, spaces, brackets, ampersand and apostrophe preserved'
$multiReport = Join-Path $OutputDirectory 'multi.json'
Invoke-Case 'multitrack' @($multi,'-NonInteractive','-JsonPath',$multiReport)
$m = Get-Content -LiteralPath $multiReport -Raw | ConvertFrom-Json
Assert-That (@($m.files[0].streams | Where-Object codec_type -eq audio).Count -eq 2) 'Both audio tracks retained'
Assert-That (@($m.files[0].streams | Where-Object codec_type -eq subtitle).Count -eq 1) 'Subtitle stream retained'
Assert-That ($m.files[0].samples.Count -eq 0) 'Default metadata path performs no packet sample'
$irregularReport = Join-Path $OutputDirectory 'irregular.json'
Invoke-Case 'irregular' @($irregular,'-NonInteractive','-Deep','-MaxPackets','100','-JsonPath',$irregularReport)
$v = Get-Content -LiteralPath $irregularReport -Raw | ConvertFrom-Json
Assert-That ($v.files[0].samples[0].measured.maxIntervalSeconds -gt 0.15) 'Actual irregular timing gap detected'
$bad = Join-Path $OutputDirectory 'broken.mp4'
'not media' | Set-Content -LiteralPath $bad
Invoke-Case 'bad-file' @($bad,'-NonInteractive') 1
Invoke-Case 'missing-path' @((Join-Path $OutputDirectory 'missing.mp4'),'-NonInteractive') 1
Invoke-Case 'invalid-stream' @($cfr,'-NonInteractive','-Deep','-StreamIndex','55') 1
Invoke-Case 'folder-deep-refused' @($OutputDirectory,'-NonInteractive','-Deep') 1
$before = (Get-FileHash -LiteralPath $cfr).Hash
Invoke-Case 'export-collision' @($cfr,'-NonInteractive','-JsonPath',$cfr) 1
Assert-That ((Get-FileHash -LiteralPath $cfr).Hash -eq $before) 'Export collision preserves source bytes'
$folderReport = Join-Path $OutputDirectory 'folder.json'
Invoke-Case 'mixed-folder' @($OutputDirectory,'-NonInteractive','-JsonPath',$folderReport) 1
$f = Get-Content -LiteralPath $folderReport -Raw | ConvertFrom-Json
Assert-That ($f.files.Count -eq 3 -and $f.failures.Count -eq 1) 'Mixed folder continues after bad media and retains failure'
foreach ($raw in @($null,'0/0','25/0','N/A','-25/1')) { Assert-That ($null -eq (Get-InspectorRational $raw).decimal) "Invalid rational remains unknown: $raw" }
Assert-That ((Get-InspectorRational '2997003/125000').raw -eq '2997003/125000') 'Exact large rational preserved'
Assert-That ((Get-InspectorScan $null) -eq 'Unknown' -and (Get-InspectorScan 'unknown') -eq 'Unknown') 'Absent and unknown scan never become progressive/interlaced'
$fake = [pscustomobject]@{ streams=@([pscustomobject]@{ index=0; codec_type='video'; r_frame_rate='25/1'; avg_frame_rate='25/1'; bits_per_raw_sample='0' }); format=[pscustomobject]@{ duration='2'; bit_rate='1000000' } }
$entry = New-InspectorEntry (Get-Item -LiteralPath $cfr) $fake ([pscustomobject]@{ arguments=@(); stderr=''; exitCode=0 })
Assert-That ($null -eq $entry.streams[0].bit_rate -and $null -eq $entry.streams[0].compressionDensity) 'Container bitrate never promoted to video bitrate/density'
Assert-That ($entry.streams[0].timingMode -like 'Not analyzed*' -and $null -eq $entry.streams[0].bitDepth) 'Equal FPS and absent pixel format remain unproven'
$packets = @([pscustomobject]@{pts=0;dts=0;flags='K'},[pscustomobject]@{pts=0;dts=-1},[pscustomobject]@{pts=1;dts=-1},[pscustomobject]@{})
$stats = Measure-InspectorPackets $packets ([pscustomobject]@{time_base='1/1000000';r_frame_rate='25/1'})
Assert-That ($stats.duplicatePts -eq 1 -and $stats.tinyPositiveIntervals -eq 1 -and $stats.missingPts -eq 1 -and $stats.backwardsDts -eq 1 -and $stats.duplicateDts -eq 1) 'Duplicate/tiny/missing PTS and backwards/duplicate DTS measured independently'
$clock = [Diagnostics.Stopwatch]::StartNew()
$timedOut=$false
try { Invoke-InspectorProbe (Get-Command pwsh).Source @('-NoProfile','-Command','Start-Sleep -Seconds 20') 1 | Out-Null } catch { $timedOut=$_.Exception.Message -like '*timed out*' }
Assert-That ($timedOut -and $clock.Elapsed.TotalSeconds -lt 5) 'Wall-time bound kills slow process and rejects partial output'
$fullReportBefore = Format-InspectorReport $c
foreach ($width in @(108,100,99,80,50,40,108)) {
    $view = @(Get-InspectorView $c -Width $width)
    foreach ($row in $view) {
        $rowText = ($row.Spans | ForEach-Object Text) -join ''
        if ($rowText.Length -gt $width) { throw "Presentation overflow at $width columns: $rowText" }
    }
    Write-Host "PASS: Overview fits $width columns."
}
$view = @(Get-InspectorView $c -Width 108)
$visible = ($view | ForEach-Object { ($_.Spans | ForEach-Object Text) -join '' }) -join "`n"
Assert-That ($visible -match 'H264' -and $visible -match 'VIDEO' -and $visible -match 'SUBTITLES' -and $visible -match 'MiB') 'Overview shows media identity, size and track sections'
Assert-That ($visible -match '25 fps' -and $visible -match 'kb/s' -and $visible -notmatch '\[25/1\]|Nominal FPS') 'Overview shows readable FPS and video bitrate; exact rates stay in details'
Assert-That ($visible -notmatch 'SMART CUT|NEXT STEP|Not checked|closer look|custom-2026|diagnosis|Not measured') 'Casual overview contains no Smart Cut verdict or diagnostic checklist'
Assert-That ($visible -match 'No audio track' -and $visible -match 'None embedded') 'Missing audio and subtitles are explicit'
$multiView=(Get-InspectorSummaryLines $m.files[0] 108 | ForEach-Object { $_.Spans.Text -join '' }) -join "`n"
Assert-That ($multiView -match '2 tracks' -and $multiView -match 'eng' -and $multiView -match 'ell' -and $multiView -match 'subrip') 'Overview retains both audio languages and embedded subtitle codec'
Assert-That ($visible -notmatch 'ffprobe version|schema 1|bits_per_raw_sample') 'Overview keeps report internals out of the reading flow'
$detailView = @(Get-InspectorView $c -Width 80 -Details)
$detailText = ($detailView | ForEach-Object { ($_.Spans | ForEach-Object Text) -join '' }) -join "`n"
Assert-That ($detailText -match 'Time base' -and $fullReportBefore -match 'ffprobe version') 'Technical details retain clocks; full report retains probe provenance'
Assert-That ((Format-InspectorReport $c) -ceq $fullReportBefore) 'Overview/details do not alter full copy/export report'
Write-Host 'PASS: Inspector regression suite complete.'
