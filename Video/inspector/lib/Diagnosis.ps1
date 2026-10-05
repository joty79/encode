# Read-only explanations against a dated custom-build contract, not an eligibility oracle.
# Owners: Avidemux docs/smart-cut-reordered.md, docs/smart-cut-hevc.md and
# Q_smartCutReordered.h / Q_smartCutHevc.h, inspected 2026-09-26.
function Get-InspectorDiagnosis {
    param($Entry)
    $findings=[Collections.Generic.List[object]]::new()
    function Add-Finding($Id,$Severity,$Title,$Why,$Next,$Evidence) {
        $findings.Add([pscustomobject]@{id=$Id;severity=$Severity;title=$Title;why=$Why;nextStep=$Next;evidence=$Evidence})
    }
    $videos=@($Entry.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
    $allVideos=@($Entry.streams | Where-Object codec_type -eq video)
    $video=$videos | Select-Object -First 1
    $covered=$video.codec_name -in 'h264','hevc'
    if (-not $video) {
        Add-Finding 'video.absent' 'Restriction' 'No video track was found' 'There is no moving-picture track to cut.' 'Check that this is the intended video file.' @{videoTracks=$videos.Count}
    } elseif (-not $covered) {
        Add-Finding 'codec.unassessed' 'Unknown' 'This codec needs an Avidemux check' "The inspector currently explains H.264 and HEVC repair limits; this file uses $($video.codec_name)." 'Open the file in your custom Avidemux build; other repair paths may support it.' @{codec=$video.codec_name}
    } else {
        if ($allVideos.Count -ne 1) {
            Add-Finding 'video.multiple' 'Restriction' 'More than one video track' 'This repair path expects exactly one video track, including any cover-art track.' 'Use a separate copy containing only the intended video track.' @{videoTracks=$allVideos.Count}
        }
        $extension=[IO.Path]::GetExtension($Entry.path).ToLowerInvariant()
        if ($extension -notin '.mp4','.mkv') {
            Add-Finding 'container.extension' 'Restriction' 'This repair path expects MP4 or MKV' 'The custom repair path checks the source filename extension.' 'Remux to a new MP4/MKV if suitable; renaming the extension does not convert the file.' @{extension=$extension;format=$Entry.format.format_name}
        }
        $missing=[Collections.Generic.List[string]]::new()
        $profiles=if ($video.codec_name -eq 'h264') { @('Main','High') } else { @('Main','Main 10') }
        $pixels=if ($video.codec_name -eq 'h264') { @('yuv420p') } else { @('yuv420p','yuv420p10le') }
        if (-not $video.profile -or $video.profile -eq 'unknown') { $missing.Add('codec profile') }
        elseif ($video.profile -notin $profiles) {
            Add-Finding 'video.profile' 'Restriction' 'The codec profile is outside this repair path' "This file uses $($video.profile); the checked path accepts $($profiles -join ' or ')." 'Use Avidemux to check alternatives; full re-encoding may be needed.' @{codec=$video.codec_name;profile=$video.profile;accepted=$profiles}
        }
        if (-not $video.pix_fmt -or $video.pix_fmt -eq 'unknown') { $missing.Add('pixel format') }
        elseif ($video.pix_fmt -notin $pixels) {
            $allowed=if ($video.codec_name -eq 'h264') { '8-bit 4:2:0' } else { '8-bit or 10-bit 4:2:0' }
            Add-Finding 'video.pixels' 'Restriction' 'The picture format is outside this repair path' "This file reports $($video.bitDepth)-bit / $($video.chroma); this path accepts $allowed video." 'Remuxing will not change this; a compatible full encode may be needed.' @{pix_fmt=$video.pix_fmt;bitDepth=$video.bitDepth;chroma=$video.chroma;accepted=$pixels}
        }
        if ($video.field_order -in 'tt','bb','tb','bt') {
            Add-Finding 'video.interlaced' 'Restriction' 'The video is interlaced' 'This Smart Cut repair path requires progressive video (whole pictures, rather than alternating fields).' 'Use a suitable full-encoding workflow if this path is required.' @{field_order=$video.field_order}
        } elseif ($video.field_order -ne 'progressive') { $missing.Add('progressive/interlaced signalling') }
        if (-not $video.sample_aspect_ratio -or $video.sample_aspect_ratio -in 'N/A','0:1','unknown') { $missing.Add('pixel shape') }
        elseif ($video.sample_aspect_ratio -ne '1:1') {
            Add-Finding 'video.aspect' 'Restriction' 'The video uses non-square pixels' 'This repair path cannot preserve this picture-shape setting.' 'Do not force a new aspect flag; use an encode that preserves the intended display shape.' @{sample_aspect_ratio=$video.sample_aspect_ratio}
        }
        $side=@($video.side_data_list | Where-Object { $null -ne $_ })
        if ($video.color_transfer -in 'smpte2084','arib-std-b67' -or @($side | Where-Object side_data_type -Match 'mastering|content light|dovi|HDR').Count) {
            Add-Finding 'video.hdr' 'Restriction' 'HDR metadata is outside this repair path' 'This repair path does not support HDR or Dolby Vision metadata.' 'Use an HDR-aware workflow; simply removing the metadata can give incorrect colours.' @{color_transfer=$video.color_transfer;side_data_list=$side}
        } elseif ($side.Count) {
            Add-Finding 'video.side-data' 'Restriction' 'Extra picture metadata needs another workflow' 'This repair path rejects stream side data, including rotation or display transforms.' 'Check the metadata in Video details before choosing another export workflow.' @{side_data_list=$side}
        }
        if ($video.codec_name -eq 'h264') {
            if (-not $video.nominalFps.decimal) { $missing.Add('frame rate') }
            elseif ($video.nominalFps.decimal -lt 10 -or $video.nominalFps.decimal -gt 120 -or $video.nominalFps.numerator -gt 2147483647 -or $video.nominalFps.denominator -gt 2147483647) {
                Add-Finding 'video.rate' 'Restriction' 'The reported frame rate is outside this repair path' 'The H.264 path accepts 10 to 120 fps with supported exact rate numbers.' 'Keep the original timing; check the Avidemux rejection before considering conversion.' @{r_frame_rate=$video.r_frame_rate;maximumComponent=2147483647}
            }
            if ($video.nal_length_size -and [string]$video.nal_length_size -ne '4') {
                Add-Finding 'video.nal' 'Restriction' 'The video packet layout is unsupported here' 'This H.264 repair path expects four-byte AVC packet lengths.' 'A separate remux may help; check the resulting file again.' @{nal_length_size=$video.nal_length_size}
            }
        }
        if ($missing.Count) {
            Add-Finding 'metadata.incomplete' 'Unknown' 'Some format information is missing' "Not reported clearly: $($missing -join ', ')." 'Avidemux must inspect the stream; missing information is not proof of compatibility or damage.' @{missing=$missing.ToArray()}
        }
    }
    foreach ($sample in $Entry.samples) {
        $m=$sample.measured
        $coverage='stream {0}, {1:0.000}-{2:0.000} s' -f $sample.streamIndex,$m.firstPtsSeconds,$m.lastPtsSeconds
        if ($m.tinyPositiveIntervals -gt 0 -or $m.duplicatePts -gt 0 -or $m.missingPts -gt 0 -or $m.backwardsDts -gt 0) {
            $reasons=[Collections.Generic.List[string]]::new()
            if ($m.tinyPositiveIntervals -gt 0) {
                $extent=if ($null -ne $m.firstTinySeconds) { ' ({0:0.000}-{1:0.000} s, first to last)' -f $m.firstTinySeconds,$m.lastTinySeconds } else { '' }
                $reasons.Add("$($m.tinyPositiveIntervals) picture-time gaps are almost zero$extent.")
            }
            if ($m.duplicatePts -gt 0) { $reasons.Add("$($m.duplicatePts) picture timestamps repeat.") }
            if ($m.missingPts -gt 0) { $reasons.Add("$($m.missingPts) picture timestamps are missing.") }
            if ($m.backwardsDts -gt 0) { $reasons.Add("Decoding time goes backwards $($m.backwardsDts) time(s).") }
            Add-Finding 'timing.anomaly' 'Review' 'Timing problems were found in the sample' ($reasons -join ' ') 'Let Avidemux check whether your cuts depend on this area. A problem elsewhere may not block the selection.' @{streamIndex=$sample.streamIndex;coverage=@($m.firstPtsSeconds,$m.lastPtsSeconds);tiny=$m.tinyPositiveIntervals;duplicatePts=$m.duplicatePts;missingPts=$m.missingPts;backwardsDts=$m.backwardsDts;tinyExtent=@($m.firstTinySeconds,$m.lastTinySeconds)}
        } elseif ($m.nominalDeviations -gt 0 -or $m.missingDts -gt 0 -or $m.duplicateDts -gt 0) {
            Add-Finding 'timing.review' 'Review' 'The sampled timing needs a closer look' "Picture spacing or decoding timestamps need review ($coverage). Sample edges can also cause apparent gaps." 'Use Avidemux to check the selected cuts; this sample does not prove variable frame rate.' @{streamIndex=$sample.streamIndex;coverage=@($m.firstPtsSeconds,$m.lastPtsSeconds);nominalDeviations=$m.nominalDeviations;missingDts=$m.missingDts;duplicateDts=$m.duplicateDts}
        } elseif ($m.intervals -lt 1 -or -not $m.nominalIntervalSeconds) {
            Add-Finding 'timing.insufficient' 'Unknown' 'The timing sample is inconclusive' 'There are too few timestamps or no usable reference frame rate.' 'Try another sample position or use the Avidemux analysis.' @{streamIndex=$sample.streamIndex;intervals=$m.intervals}
        }
    }
    if (-not $Entry.samples.Count -and $video.nominalFps.decimal -and $video.averageFps.decimal -and [math]::Abs($video.nominalFps.decimal-$video.averageFps.decimal) -gt 0.001) {
        Add-Finding 'timing.rate-difference' 'Review' 'The reported frame rates disagree' 'The file reports different nominal and average speeds. Actual timestamps need checking.' 'Press D to check a timing sample; this difference alone does not mean VFR.' @{r_frame_rate=$video.r_frame_rate;avg_frame_rate=$video.avg_frame_rate}
    }
    if ($Entry.provenance.stderr) {
        Add-Finding 'probe.diagnostics' 'Review' 'The file reader reported a problem' 'Metadata was returned, but ffprobe also reported diagnostics.' 'Copy the full report for diagnosis; do not assume the file is healthy.' @{stderr=$Entry.provenance.stderr}
    }
    $ordered=@($findings | Sort-Object @{Expression={switch ($_.severity) {'Restriction' {0} 'Review' {1} default {2}}}} -Stable)
    $restriction=@($ordered | Where-Object severity -eq Restriction).Count -gt 0
    $status=if ($restriction) { 'Restriction' } elseif ($ordered.Count) { 'Review' } else { 'Unchecked' }
    $headline=if ($restriction) { 'A repair limitation was found' } elseif ($ordered.Count) { 'Needs a closer look' } else { 'No common format restriction found' }
    $next=if ($ordered.Count) { $ordered[0].nextStep } else { 'Check your selected cuts in Avidemux. Their surrounding frames still need analysis.' }
    [pscustomobject]@{
        rulesVersion='avidemux-custom-2026-09-26.1';scope='H.264 Main/High reordered repair and HEVC Main/Main 10 repair; not general Avidemux support.'
        status=$status;headline=$headline;nextStep=$next;findings=$ordered
        limitation='No project or cut dependencies analyzed. Import, playback, ordinary Copy and other repair paths can differ. The installed Avidemux build was not detected.'
        unchecked=@('Selected ranges and whole dependency windows','True IDR/access points and reference structure','In-stream parameter changes and hidden HDR/SEI','Full-file timing and decoding','Audio/muxer compatibility and final A/V sync')
    }
}

function Update-InspectorDiagnoses {
    param($Report)
    foreach ($file in $Report.files) {
        $diagnosis=Get-InspectorDiagnosis $file
        if ($file -is [Collections.IDictionary]) { $file['diagnosis']=$diagnosis }
        else { $file | Add-Member -NotePropertyName diagnosis -NotePropertyValue $diagnosis -Force }
    }
}
