. "$PSScriptRoot\Diagnosis.ps1"
# Text is shared by terminal, clipboard and text export. Narrow terminals wrap naturally.
function Show-InspectorValue {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'Unknown / missing' }
    if ($Value -is [double] -or $Value -is [decimal]) { return $Value.ToString('0.#########', [Globalization.CultureInfo]::InvariantCulture) }
    return [string]$Value
}
function Format-InspectorRate {
    param($Rate)
    if ($null -eq $Rate.decimal) { return "$(Show-InspectorValue $Rate.raw) (Unknown)" }
    return ('{0} (~{1} fps)' -f $Rate.raw,$Rate.decimal.ToString('0.#########',[Globalization.CultureInfo]::InvariantCulture))
}
function Format-InspectorReport {
    param($Report, $Entry)
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("Media Info $($Report.inspectorVersion) | schema $($Report.schemaVersion) | $($Report.generatedUtc)")
    $lines.Add("$($Report.tool.version) | PowerShell $($Report.tool.powershell)")
    $entries = if ($null -ne $Entry) { @($Entry) } else { @($Report.files) }
    foreach ($file in $entries) {
        $lines.Add('')
        $lines.Add("FILE: $($file.path)")
        $diagnosis=Get-InspectorDiagnosis $file
        $lines.Add("SMART CUT CHECK: $($diagnosis.headline)")
        $lines.Add("Rules: $($diagnosis.rulesVersion) | $($diagnosis.scope)")
        foreach ($finding in $diagnosis.findings) {
            $lines.Add("  [$($finding.severity) / $($finding.id)] $($finding.title)")
            $lines.Add("  Why: $($finding.why)")
            $lines.Add("  Next: $($finding.nextStep)")
            $lines.Add("  Evidence: $($finding.evidence | ConvertTo-Json -Depth 12 -Compress)")
        }
        $lines.Add("Next: $($diagnosis.nextStep)")
        $lines.Add($diagnosis.limitation)
        $lines.Add("Not checked: $($diagnosis.unchecked -join '; ')")
        $lines.Add("Size: $($file.sizeBytes) bytes | Modified UTC: $($file.lastWriteUtc)")
        $f=$file.format
        $lines.Add("Container: $(Show-InspectorValue $f.format_name) | brand: $(Show-InspectorValue $f.brands.major)")
        $lines.Add("Container start: $(Show-InspectorValue $f.start_time) s | duration: $(Show-InspectorValue $f.duration) s")
        $lines.Add("Container bitrate: $(Show-InspectorValue $f.bit_rate) bit/s (reported, all streams + overhead)")
        if ($null -ne $f.fileAverageBitrate) { $lines.Add(('File average: {0:F0} bit/s (size * 8 / container duration, all streams + overhead)' -f $f.fileAverageBitrate)) }
        $lines.Add("Evidence: $($file.provenance.source)")
        if ($file.provenance.stderr) { $lines.Add("ffprobe diagnostics: $($file.provenance.stderr)") }
        foreach ($s in $file.streams) {
            $lines.Add('')
            $lines.Add("[$($s.index)] $(Show-InspectorValue $s.codec_type): $(Show-InspectorValue $s.codec_name) / tag $(Show-InspectorValue $s.codec_tag_string) | profile $(Show-InspectorValue $s.profile)")
            $lines.Add("  Time base: $(Show-InspectorValue $s.time_base) | start: $(Show-InspectorValue $s.start_time) s / PTS $(Show-InspectorValue $s.start_pts)")
            $lines.Add("  Duration: $(Show-InspectorValue $s.duration) s / ticks $(Show-InspectorValue $s.duration_ts) | frames: $(Show-InspectorValue $s.nb_frames) (reported, not counted)")
            $lines.Add("  Stream bitrate: $(Show-InspectorValue $s.bit_rate) bit/s (reported stream value only)")
            if ($s.codec_type -eq 'video') {
                $lines.Add("  Image: $(Show-InspectorValue $s.width)x$(Show-InspectorValue $s.height) | level $(Show-InspectorValue $s.level) (raw codec-specific) | $($s.scan)")
                $lines.Add("  Pixel format: $(Show-InspectorValue $s.pix_fmt) | chroma $($s.chroma) (pix_fmt name) | depth $(Show-InspectorValue $s.bitDepth) ($($s.bitDepthSource))")
                $lines.Add("  SAR: $(Show-InspectorValue $s.sample_aspect_ratio) | DAR: $(Show-InspectorValue $s.display_aspect_ratio) | field_order: $(Show-InspectorValue $s.field_order)")
                $lines.Add("  Nominal FPS: $(Format-InspectorRate $s.nominalFps)")
                $lines.Add("  Average FPS: $(Format-InspectorRate $s.averageFps)")
                $lines.Add("  CFR/VFR: $($s.timingMode)")
                $lines.Add("  Color: range $(Show-InspectorValue $s.color_range), primaries $(Show-InspectorValue $s.color_primaries), transfer $(Show-InspectorValue $s.color_transfer), matrix $(Show-InspectorValue $s.color_space)")
                $lines.Add("  has_b_frames: $(Show-InspectorValue $s.has_b_frames) (reported hint, not GOP proof)")
                $lines.Add('  GOP / IDR / recovery / dependency windows: Not analyzed')
                $lines.Add("  Density: $(Show-InspectorValue $s.compressionDensity) bits/pixel/frame | personal bitrate policy: $($s.bitratePolicy) (subjective, not quality/compatibility proof)")
                $side = @($s.side_data_list | Where-Object { $null -ne $_ })
                $lines.Add("  HDR / side data: $(if ($side.Count) { ($side | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress }) -join '; ' } else { 'Not reported at stream level; frame-level HDR not analyzed' })")
            } elseif ($s.codec_type -eq 'audio') {
                $lines.Add("  Audio: $(Show-InspectorValue $s.sample_rate) Hz | $(Show-InspectorValue $s.channels) channels / $(Show-InspectorValue $s.channel_layout) | $(Show-InspectorValue $s.sample_fmt)")
            }
            $lines.Add("  Language: $(Show-InspectorValue $s.tags.language) | title: $(Show-InspectorValue $s.tags.title)")
        }
        if (-not @($file.streams | Where-Object codec_type -eq 'audio').Count) { $lines.Add('Audio: none reported') }
        if (-not $file.samples.Count) { $lines.Add('Packet timing: Not analyzed. Use D for a bounded sample.') }
        foreach ($sample in $file.samples) {
            $m=$sample.measured
            $lines.Add('')
            $lines.Add("PACKET SAMPLE: stream $($sample.streamIndex) | requested $($sample.readInterval) | limit $($sample.timeoutSeconds) s wall time")
            $lines.Add("  $($sample.scope)")
            $lines.Add("  Packets: $($m.packetCount) | actual PTS coverage: $(Show-InspectorValue $m.firstPtsSeconds) .. $(Show-InspectorValue $m.lastPtsSeconds) s")
            $lines.Add("  Sorted PTS intervals: $($m.intervals) | min/mean/max: $(Show-InspectorValue $m.minIntervalSeconds) / $(Show-InspectorValue $m.meanIntervalSeconds) / $(Show-InspectorValue $m.maxIntervalSeconds) s")
            $lines.Add("  Missing PTS/DTS: $($m.missingPts)/$($m.missingDts) | duplicate PTS: $($m.duplicatePts) | tiny positive: $(Show-InspectorValue $m.tinyPositiveIntervals)")
            if ($null -ne $m.firstTinySeconds) { $lines.Add("  Tiny interval extent: $(Show-InspectorValue $m.firstTinySeconds) .. $(Show-InspectorValue $m.lastTinySeconds) s (first to last; may contain gaps)") }
            $lines.Add("  Nominal deviations: $(Show-InspectorValue $m.nominalDeviations) (tolerance max(1.01 ticks, 1% nominal); tiny <1% nominal)")
            $lines.Add("  Backwards/duplicate DTS: $($m.backwardsDts)/$($m.duplicateDts) | reordered packet PTS: $($m.ptsBackwardsInPacketOrder)")
            $lines.Add("  Key flags: $($m.keyFlagCount) | min/max gap: $(Show-InspectorValue $m.minKeyFlagGapSeconds) / $(Show-InspectorValue $m.maxKeyFlagGapSeconds) s")
            $lines.Add("  $($m.keyEvidence)")
            foreach ($example in ($m.anomalyExamples | Select-Object -First 5)) { $lines.Add("  Example: $(Show-InspectorValue $example.fromSeconds)..$(Show-InspectorValue $example.toSeconds) s | delta $(Show-InspectorValue $example.deltaSeconds) s | $($example.kind)") }
            if ($m.anomalyExamples.Count -gt 5) { $lines.Add('  More examples (up to 20) and exact PTS ticks are available in JSON.') }
            if ($sample.stderr) { $lines.Add("  ffprobe diagnostics: $($sample.stderr)") }
            $lines.Add("  $($m.verdict)")
        }
    }
    foreach ($failure in $Report.failures) { $lines.Add("FAILURE: $($failure | ConvertTo-Json -Compress)") }
    $lines.Add(''); $lines.Add($Report.interpretation)
    return $lines -join [Environment]::NewLine
}

# The terminal view is intentionally independent from the full copy/export report.
# Stateless rows are shared by CLI and Ui.ps1; the shared blueprint owns host lifecycle.
$inspectorUiOwner = Join-Path $env:USERPROFILE '.agent-shared\templates\PS_UI_Blueprint.psm1'
Import-Module $inspectorUiOwner -DisableNameChecking -Function Split-UiWrappedText,ConvertTo-UiSafeSingleLineText

function New-InspectorSpan {
    param([string]$Text, [string]$Color='Gray', [string]$Background='')
    [pscustomobject]@{ Text=$Text; Color=$Color; Background=$Background }
}
function Add-InspectorViewLine {
    param($Lines, [object[]]$Spans)
    $Lines.Add([pscustomobject]@{ Spans=@($Spans) })
}
function Add-InspectorViewText {
    param($Lines, [string]$Text, [string]$Color='Gray', [int]$Width=108)
    foreach ($part in (Split-UiWrappedText (ConvertTo-UiSafeSingleLineText $Text) ($Width-4))) {
        Add-InspectorViewLine $Lines @((New-InspectorSpan "  $part" $Color))
    }
}
function Add-InspectorViewSection {
    param($Lines, [string]$Title, [int]$Width)
    Add-InspectorViewLine $Lines @()
    foreach ($part in (Split-UiWrappedText (ConvertTo-UiSafeSingleLineText $Title) ($Width-4))) {
        Add-InspectorViewLine $Lines @((New-InspectorSpan "  $part " Cyan),(New-InspectorSpan ('─' * [math]::Max(0,$Width-$part.Length-4)) DarkGray))
    }
}
function Get-InspectorDisplayValue {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value) -or $Value -eq 'unknown' -or $Value -eq 'N/A') { return 'Not reported' }
    return ConvertTo-UiSafeSingleLineText (Show-InspectorValue $Value)
}
function Add-InspectorViewPair {
    param($Lines, [int]$Width, [string]$Label, $Value, [string]$Label2='', $Value2='', [string]$Color='White', [string]$Color2='White')
    $columns = if ($Width -ge 100 -and $Label2) { 2 } else { 1 }
    $cellWidth = if ($columns -eq 2) { [int][math]::Floor(($Width-4)/2) } else { $Width-4 }
    $valueWidth = $cellWidth-16
    $left = @(Split-UiWrappedText (Get-InspectorDisplayValue $Value) $valueWidth)
    $right = @(if ($columns -eq 2) { Split-UiWrappedText (Get-InspectorDisplayValue $Value2) $valueWidth })
    for ($lineIndex=0; $lineIndex -lt [math]::Max($left.Count,$right.Count); $lineIndex++) {
        $labelText = if ($lineIndex -eq 0) { $Label.PadRight(15) } else { ' '*15 }
        $valueText = if ($lineIndex -lt $left.Count) { $left[$lineIndex] } else { '' }
        $valueColor = if ($valueText -eq 'Not reported') { 'DarkGray' } else { $Color }
        $spans = @((New-InspectorSpan "  $labelText" DarkGray),(New-InspectorSpan $valueText $valueColor))
        if ($columns -eq 2) {
            $labelText2 = if ($lineIndex -eq 0) { $Label2.PadRight(15) } else { ' '*15 }
            $valueText2 = if ($lineIndex -lt $right.Count) { $right[$lineIndex] } else { '' }
            $valueColor2 = if ($valueText2 -eq 'Not reported') { 'DarkGray' } else { $Color2 }
            $spans += New-InspectorSpan (' '*[math]::Max(1,$cellWidth-15-$valueText.Length))
            $spans += New-InspectorSpan $labelText2 DarkGray
            $spans += New-InspectorSpan $valueText2 $valueColor2
        }
        Add-InspectorViewLine $Lines $spans
    }
    if ($columns -eq 1 -and $Label2) { Add-InspectorViewPair $Lines $Width $Label2 $Value2 -Color $Color2 }
}
function Format-InspectorSize {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:0.00} GiB' -f ($Bytes/1GB)) }
    return ('{0:0.1} MiB' -f ($Bytes/1MB))
}
function Format-InspectorDuration {
    param($Seconds)
    $number = ConvertTo-InspectorNumber $Seconds
    if ($null -eq $number -or $number -lt 0) { return 'Not reported' }
    $duration = [TimeSpan]::FromSeconds($number)
    return ('{0:00}:{1:00}:{2:00}' -f [int][math]::Floor($duration.TotalHours),$duration.Minutes,$duration.Seconds)
}
function Format-InspectorBitrate {
    param($Bits)
    $number = ConvertTo-InspectorNumber $Bits
    if ($null -eq $number -or $number -le 0) { return 'Not reported' }
    if ($number -ge 1e6) { return ('{0:0.00} Mb/s' -f ($number/1e6)) }
    return ('{0:0} kb/s' -f ($number/1e3))
}
function Add-InspectorViewRate {
    param($Lines, [int]$Width, [string]$Label, $Rate, [string]$Color='White')
    $decimal = if ($null -ne $Rate.decimal) { $Rate.decimal.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)+' fps' } else { 'Not reported' }
    $rational = if ($Rate.raw) { "   [$($Rate.raw)]" } else { '' }
    if (17+$decimal.Length+$rational.Length -le $Width) {
        Add-InspectorViewLine $Lines @((New-InspectorSpan ('  '+$Label.PadRight(15)) DarkGray),(New-InspectorSpan $decimal $Color),(New-InspectorSpan $rational DarkGray))
    } else {
        Add-InspectorViewPair $Lines $Width $Label $decimal -Color $Color
        Add-InspectorViewPair $Lines $Width 'Exact rational' $Rate.raw -Color DarkGray
    }
}
function Get-InspectorContainerName {
    param($File)
    $format=[string]$File.format.format_name
    switch -Regex ($format) {
        '(^|,)mov(,|$)' { if ([string]$File.format.brands.major -match '^qt') { return 'QuickTime / MOV' }; return 'MP4 / QuickTime' }
        'matroska' { return 'Matroska / WebM' }
        '^mpegts$' { return 'MPEG Transport Stream' }
        '^mpeg$' { return 'MPEG Program Stream' }
        '^asf$' { return 'ASF / Windows Media' }
        default { if ($format) { return $format.ToUpperInvariant() }; return 'Container not reported' }
    }
}
function Add-InspectorSummarySection {
    param($Lines,[string]$Title,[string]$Color,[int]$Width)
    Add-InspectorViewLine $Lines @()
    Add-InspectorViewLine $Lines @((New-InspectorSpan "  $Title" $Color))
}
function Get-InspectorSummaryLines {
    param($File, [int]$Width=108)
    $lines=[Collections.Generic.List[object]]::new()
    Add-InspectorViewText $lines ("$(Get-InspectorContainerName $File)  ·  $(Format-InspectorDuration $File.format.duration)  ·  $(Format-InspectorSize $File.sizeBytes)") Cyan $Width
    $videos=@($File.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
    $audio=@($File.streams | Where-Object codec_type -eq audio)
    $subtitles=@($File.streams | Where-Object codec_type -eq subtitle)
    foreach ($v in $videos) {
        $title=if ($videos.Count -gt 1) { "VIDEO  ·  Track $($v.index)" } else { 'VIDEO' }
        Add-InspectorSummarySection $lines $title Magenta $Width
        $codec=if ($v.codec_name) { ([string]$v.codec_name).ToUpperInvariant() } else { 'Codec unknown' }
        $profile=if ($v.profile -and $v.profile -ne 'unknown') { " $($v.profile)" } else { '' }
        $rate=if ($v.nominalFps.decimal) { '{0:0.###} fps' -f $v.nominalFps.decimal } else { 'FPS not reported' }
        $resolution=if ($v.width -and $v.height) { "$($v.width) × $($v.height)" } else { 'Resolution not reported' }
        Add-InspectorViewText $lines ("$codec$profile  ·  $resolution  ·  $rate") White $Width
        $picture=[Collections.Generic.List[string]]::new()
        if ($v.bitDepth) { $picture.Add("$($v.bitDepth)-bit") }
        if ($v.chroma -and $v.chroma -ne 'Unknown') { $picture.Add([string]$v.chroma) }
        if ($v.field_order -eq 'progressive') { $picture.Add('Progressive') }
        elseif ($v.field_order -in 'tt','bb','tb','bt') { $picture.Add('Interlaced') }
        else { $picture.Add('Scan not reported') }
        if ($v.display_aspect_ratio -and $v.display_aspect_ratio -ne '0:1') { $picture.Add([string]$v.display_aspect_ratio) }
        Add-InspectorViewText $lines ($picture -join '  ·  ') Gray $Width
        $extras=[Collections.Generic.List[string]]::new()
        if ((ConvertTo-InspectorNumber $v.bit_rate) -gt 0) { $extras.Add("$(Format-InspectorBitrate $v.bit_rate) video") }
        if ($v.color_transfer -eq 'smpte2084') { $extras.Add('HDR / PQ') }
        elseif ($v.color_transfer -eq 'arib-std-b67') { $extras.Add('HDR / HLG') }
        $side=@($v.side_data_list | Where-Object { $null -ne $_ })
        if (@($side | Where-Object side_data_type -Match 'dovi').Count) { $extras.Add('Dolby Vision metadata') }
        elseif (@($side | Where-Object side_data_type -Match 'mastering|content light|HDR').Count -and $v.color_transfer -notin 'smpte2084','arib-std-b67') { $extras.Add('HDR metadata') }
        if ($extras.Count) { Add-InspectorViewText $lines ($extras -join '  ·  ') Gray $Width }
    }
    if (-not $videos.Count) { Add-InspectorViewText $lines 'No video track' DarkGray $Width }
    Add-InspectorSummarySection $lines $(if ($audio.Count -gt 1) { "AUDIO  ·  $($audio.Count) tracks" } else { 'AUDIO' }) Green $Width
    if (-not $audio.Count) { Add-InspectorViewText $lines 'No audio track' DarkGray $Width }
    foreach ($track in $audio) {
        $parts=[Collections.Generic.List[string]]::new()
        $codec=if ($track.codec_name) { ([string]$track.codec_name).ToUpperInvariant() } else { 'Codec unknown' }
        if ($track.profile -and $track.profile -ne 'unknown') { $codec+=" $($track.profile)" }
        $parts.Add($codec)
        if ($track.channel_layout) { $parts.Add([string]$track.channel_layout) }
        elseif ($track.channels) { $parts.Add("$($track.channels) channels") }
        $sampleRate=ConvertTo-InspectorNumber $track.sample_rate
        if ($sampleRate) { $parts.Add(('{0:0.###} kHz' -f ($sampleRate/1000))) }
        if ((ConvertTo-InspectorNumber $track.bit_rate) -gt 0) { $parts.Add((Format-InspectorBitrate $track.bit_rate)) }
        if ($track.tags.language -and $track.tags.language -ne 'und') { $parts.Add([string]$track.tags.language) }
        if ($track.disposition.default -eq 1) { $parts.Add('default') }
        Add-InspectorViewText $lines ($parts -join '  ·  ') White $Width
        if ($track.tags.title) { Add-InspectorViewText $lines $track.tags.title DarkGray $Width }
    }
    Add-InspectorSummarySection $lines $(if ($subtitles.Count) { "SUBTITLES  ·  $($subtitles.Count) track(s)" } else { 'SUBTITLES' }) Cyan $Width
    if (-not $subtitles.Count) { Add-InspectorViewText $lines 'None embedded' DarkGray $Width }
    foreach ($track in $subtitles) {
        $parts=@((Get-InspectorDisplayValue $track.codec_name))
        if ($track.tags.language -and $track.tags.language -ne 'und') { $parts+=[string]$track.tags.language }
        if ($track.disposition.default -eq 1) { $parts+='default' }
        if ($track.disposition.forced -eq 1) { $parts+='forced' }
        if ($track.tags.title) { $parts+=[string]$track.tags.title }
        Add-InspectorViewText $lines ($parts -join '  ·  ') White $Width
    }
    $cover=@($File.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -eq 1 })
    if ($cover.Count) { Add-InspectorViewText $lines ("Cover art: $($cover.Count) image(s)") DarkGray $Width }
    if ($File.provenance.stderr) { Add-InspectorViewText $lines 'The file reader reported diagnostics. R copies the full report.' Yellow $Width }
    return $lines.ToArray()
}
function Get-InspectorView {
    param($Report, $Entry, [ValidateRange(40,240)][int]$Width=108, [switch]$Details)
    $lines=[Collections.Generic.List[object]]::new()
    $entries=if ($null -ne $Entry) { @($Entry) } else { @($Report.files) }
    foreach ($file in $entries) {
        Add-InspectorViewLine $lines @((New-InspectorSpan '  MEDIA INFO  ' White DarkBlue),(New-InspectorSpan '  OVERVIEW' Cyan))
        Add-InspectorViewText $lines ("File: $([IO.Path]::GetFileName($file.path))") White $Width
        foreach ($row in (Get-InspectorSummaryLines $file $Width)) { $lines.Add($row) }
        if ($Details) {
            if (-not (Get-Command Get-InspectorDetailLines -ErrorAction SilentlyContinue)) { . "$PSScriptRoot\Ui.ps1" }
            foreach ($tab in 1..5) {
                foreach ($row in (Get-InspectorDetailLines $Report $file $tab $Width)) { $lines.Add($row) }
            }
        }
    }
    if ($Report.failures.Count) { Add-InspectorViewText $lines "$($Report.failures.Count) failed operation(s) - see the full report." Red $Width }
    return $lines.ToArray()
}
function Get-InspectorViewWidth {
    $width = 108
    try { if ([Console]::WindowWidth -gt 0) { $width=[Console]::WindowWidth-1 } } catch { }
    return [math]::Clamp($width,40,108)
}
function Write-InspectorViewLines {
    param([object[]]$Lines)
    foreach ($line in $Lines) {
        foreach ($span in $line.Spans) {
            $settings = @{ Object=$span.Text; ForegroundColor=$span.Color; NoNewline=$true }
            if ($span.Background) { $settings.BackgroundColor=$span.Background }
            Write-Host @settings
        }
        Write-Host ''
    }
}
function Write-InspectorReport {
    param($Report, $Entry, [switch]$Details)
    Write-InspectorViewLines (Get-InspectorView $Report $Entry -Width (Get-InspectorViewWidth) -Details:$Details)
}
