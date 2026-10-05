# Interactive screen state/layout. Input, viewport and redraw mechanics stay in the shared owner.
Import-Module $inspectorUiOwner -DisableNameChecking
$script:InspectorTabs = @('Overview','Video','Timing','Tracks','File','Smart Cut')

function Add-InspectorFrameLine {
    param($Frame, [string]$Text='')
    Add-UiFrameLine $Frame "$Text`e[K"
}

function Get-InspectorDetailLines {
    param($Report, $File, [int]$Tab, [int]$Width, [int]$VideoSelection=0)
    $lines=[Collections.Generic.List[object]]::new()
    $videos=@($File.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
    $video=if ($videos.Count) { $videos[[math]::Min($VideoSelection,$videos.Count-1)] } else { $null }
    switch ($Tab) {
        0 {
            foreach ($row in (Get-InspectorSummaryLines $File $Width)) { $lines.Add($row) }
        }
        1 {
            if (-not $video) { Add-InspectorViewText $lines 'No video stream reported.' Yellow $Width; break }
            Add-InspectorViewSection $lines "VIDEO $($video.index)   $(([string]$video.codec_name).ToUpperInvariant()) / $($video.profile)" $Width
            Add-InspectorViewPair $lines $Width 'Codec / tag' "$($video.codec_name) / $($video.codec_tag_string)" 'Level (raw)' $video.level
            Add-InspectorViewPair $lines $Width 'Dimensions' "$($video.width) × $($video.height)" 'Coded size' "$($video.coded_width) × $($video.coded_height)" -Color Cyan
            Add-InspectorViewPair $lines $Width 'Scan' $video.scan 'Field order' $video.field_order
            Add-InspectorViewPair $lines $Width 'Pixel format' $video.pix_fmt 'Chroma' $video.chroma
            Add-InspectorViewPair $lines $Width 'Bit depth' $video.bitDepth 'Depth source' $video.bitDepthSource
            Add-InspectorViewPair $lines $Width 'Aspect SAR' $video.sample_aspect_ratio 'Aspect DAR' $video.display_aspect_ratio
            Add-InspectorViewSection $lines 'COLOR & HDR' $Width
            Add-InspectorViewPair $lines $Width 'Range' $video.color_range 'Matrix' $video.color_space
            Add-InspectorViewPair $lines $Width 'Primaries' $video.color_primaries 'Transfer' $video.color_transfer
            Add-InspectorViewPair $lines $Width 'Chroma loc.' $video.chroma_location 'Rotation tag' $video.tags.rotate
            $side=@($video.side_data_list | Where-Object { $null -ne $_ })
            if (-not $side.Count) { Add-InspectorViewText $lines 'No stream-level HDR/side data reported. Frame-level HDR was not analyzed.' DarkGray $Width }
            foreach ($item in $side) {
                Add-InspectorViewSection $lines $item.side_data_type $Width
                foreach ($property in $item.PSObject.Properties) {
                    if ($property.Name -eq 'side_data_type') { continue }
                    Add-InspectorViewText $lines ($property.Name -replace '_',' ') DarkGray $Width
                    Add-InspectorViewText $lines ([string]$property.Value) White $Width
                }
            }
            Add-InspectorViewSection $lines 'COMPRESSION & STRUCTURE' $Width
            Add-InspectorViewPair $lines $Width 'Video bitrate' (Format-InspectorBitrate $video.bit_rate) 'B-frame hint' $video.has_b_frames
            Add-InspectorViewPair $lines $Width 'Density' $video.compressionDensity 'Personal tier' $video.bitratePolicy
            Add-InspectorViewPair $lines $Width 'NAL bytes' $video.nal_length_size 'Extradata' $video.extradata_size
            Add-InspectorViewText $lines 'Bitrate is stream-reported. Density/tier are subjective. B-frame metadata does not establish GOP, IDR or safe cuts.' DarkGray $Width
        }
        2 {
            if ($video) {
                Add-InspectorViewSection $lines "STREAM $($video.index) CLOCK" $Width
                Add-InspectorViewRate $lines $Width 'Nominal FPS' $video.nominalFps Cyan
                Add-InspectorViewRate $lines $Width 'Average FPS' $video.averageFps
                Add-InspectorViewPair $lines $Width 'Time base' $video.time_base 'Start PTS' $video.start_pts -Color Cyan
                Add-InspectorViewPair $lines $Width 'Start (s)' $video.start_time 'Duration (s)' $video.duration
                Add-InspectorViewPair $lines $Width 'Duration ticks' $video.duration_ts 'Frames (meta)' $video.nb_frames
            }
            Add-InspectorViewSection $lines 'MEASURED PACKET TIMING' $Width
            $samples=@($File.samples | Where-Object { -not $video -or $_.streamIndex -eq $video.index })
            if (-not $samples.Count) {
                Add-InspectorViewText $lines 'Not measured' Yellow $Width
                Add-InspectorViewText $lines 'Press D to sample this video stream. Equal or different reported FPS values do not prove CFR/VFR.' Gray $Width
            }
            foreach ($sample in $samples) {
                $m=$sample.measured
                Add-InspectorViewSection $lines "SAMPLE  $($sample.readInterval)" $Width
                if ($m.tinyPositiveIntervals -gt 0 -or $m.duplicatePts -gt 0) {
                    Add-InspectorViewText $lines "$($m.tinyPositiveIntervals) tiny intervals / $($m.duplicatePts) duplicate PTS in this sample" Red $Width
                }
                Add-InspectorViewPair $lines $Width 'PTS from (s)' $m.firstPtsSeconds 'PTS to (s)' $m.lastPtsSeconds
                Add-InspectorViewPair $lines $Width 'Packets' $m.packetCount 'Intervals' $m.intervals
                $tone=if ($m.tinyPositiveIntervals -gt 0 -or $m.duplicatePts -gt 0) { 'Red' } else { 'White' }
                Add-InspectorViewPair $lines $Width 'Tiny intervals' $m.tinyPositiveIntervals 'Duplicate PTS' $m.duplicatePts -Color $tone -Color2 $tone
                Add-InspectorViewPair $lines $Width 'Missing PTS' $m.missingPts 'Missing DTS' $m.missingDts
                Add-InspectorViewPair $lines $Width 'Min delta (s)' $m.minIntervalSeconds 'Max delta (s)' $m.maxIntervalSeconds
                Add-InspectorViewPair $lines $Width 'Mean delta (s)' $m.meanIntervalSeconds 'Nominal flags' $m.nominalDeviations
                Add-InspectorViewPair $lines $Width 'Backwards DTS' $m.backwardsDts 'Duplicate DTS' $m.duplicateDts
                Add-InspectorViewPair $lines $Width 'Key flags' $m.keyFlagCount 'PTS reorder' $m.ptsBackwardsInPacketOrder
                if ($null -ne $m.firstTinySeconds) {
                    Add-InspectorViewPair $lines $Width 'Tiny from (s)' $m.firstTinySeconds 'Tiny to (s)' $m.lastTinySeconds -Color Yellow -Color2 Yellow
                }
                Add-InspectorViewText $lines 'K flags are not IDR/recovery proof. Packet PTS are sorted before interval comparison; reordered groups at sample edges can create gaps.' DarkGray $Width
                if ($m.anomalyExamples.Count) {
                    Add-InspectorViewSection $lines 'INTERVAL EXAMPLES' $Width
                    foreach ($example in ($m.anomalyExamples | Select-Object -First 8)) {
                        Add-InspectorViewPair $lines $Width 'From → to (s)' ('{0:0.000000} → {1:0.000000}' -f $example.fromSeconds,$example.toSeconds) 'Delta (ms)' ([double]$example.deltaSeconds*1000) -Color Yellow
                    }
                }
            }
            Add-InspectorViewText $lines 'Sample evidence only. No full-file CFR/integrity verdict or dependency-window analysis.' DarkGray $Width
        }
        3 {
            foreach ($stream in $File.streams) {
                Add-InspectorViewSection $lines "$(([string]$stream.codec_type).ToUpperInvariant()) $($stream.index)   $($stream.codec_name)" $Width
                Add-InspectorViewPair $lines $Width 'Profile / tag' "$($stream.profile) / $($stream.codec_tag_string)" 'Language' $stream.tags.language
                if ($stream.codec_type -eq 'audio') {
                    Add-InspectorViewPair $lines $Width 'Sample rate' "$($stream.sample_rate) Hz" 'Sample format' $stream.sample_fmt
                    Add-InspectorViewPair $lines $Width 'Channels' $stream.channels 'Layout' $stream.channel_layout
                }
                Add-InspectorViewPair $lines $Width 'Start (s)' $stream.start_time 'Duration (s)' $stream.duration
                Add-InspectorViewPair $lines $Width 'Time base' $stream.time_base 'Start PTS' $stream.start_pts
                Add-InspectorViewPair $lines $Width 'Bitrate' (Format-InspectorBitrate $stream.bit_rate) 'Frames (meta)' $stream.nb_frames
                Add-InspectorViewPair $lines $Width 'Title' $stream.tags.title
                $flags=@($stream.disposition.PSObject.Properties | Where-Object Value -eq 1 | ForEach-Object Name)
                Add-InspectorViewPair $lines $Width 'Disposition' ($flags -join ', ')
            }
        }
        4 {
            Add-InspectorViewSection $lines 'FILE IDENTITY' $Width
            Add-InspectorViewText $lines $File.path White $Width
            Add-InspectorViewPair $lines $Width 'Size' (Format-InspectorSize $File.sizeBytes) 'Exact bytes' $File.sizeBytes
            Add-InspectorViewPair $lines $Width 'Modified UTC' $File.lastWriteUtc
            Add-InspectorViewSection $lines 'CONTAINER' $Width
            Add-InspectorViewPair $lines $Width 'Format' $File.format.format_name
            Add-InspectorViewPair $lines $Width 'Name' $File.format.format_long_name
            Add-InspectorViewPair $lines $Width 'Major brand' $File.format.brands.major 'Other brands' $File.format.brands.compatible
            Add-InspectorViewPair $lines $Width 'Start (s)' $File.format.start_time 'Duration (s)' $File.format.duration
            Add-InspectorViewPair $lines $Width 'Format bitrate' (Format-InspectorBitrate $File.format.bit_rate) 'File average' (Format-InspectorBitrate $File.format.fileAverageBitrate)
            Add-InspectorViewText $lines 'Both rates cover all streams + overhead. File average is size × 8 / duration; neither replaces video bitrate.' DarkGray $Width
        }
        5 {
            $diagnosis=Get-InspectorDiagnosis $File
            Add-InspectorViewSection $lines 'SMART CUT · OPTIONAL FORMAT HINTS' $Width
            Add-InspectorViewText $lines $diagnosis.headline White $Width
            foreach ($finding in $diagnosis.findings) {
                Add-InspectorViewSection $lines $finding.title $Width
                Add-InspectorViewText $lines $finding.why White $Width
                Add-InspectorViewText $lines ("Next: $($finding.nextStep)") Cyan $Width
                Add-InspectorViewText $lines ("$($finding.severity) / $($finding.id)") DarkGray $Width
            }
            Add-InspectorViewSection $lines 'OPTIONAL DEVELOPMENT CHECKS' $Width
            Add-InspectorViewText $lines 'D samples timing; 3 shows measurements. R copies all technical evidence.' Cyan $Width
            Add-InspectorViewText $lines 'Format hints and timing samples only; selected cuts have not been assessed.' DarkGray $Width
            Add-InspectorViewText $lines ("Rule reference: $($diagnosis.rulesVersion). Full scope is in the report.") DarkGray $Width
        }
    }
    return $lines.ToArray()
}

function ConvertTo-InspectorAnsiRow {
    param($Row)
    $colors=@{Black=30;DarkBlue=34;DarkGray=90;Gray=37;White=97;Cyan=96;Yellow=93;Red=91;Green=92;Magenta=95}
    $text=[Text.StringBuilder]::new()
    foreach ($span in $Row.Spans) {
        $null=$text.Append("`e[$($colors[$span.Color])m")
        if ($span.Background) { $null=$text.Append("`e[$($colors[$span.Background]+10)m") }
        $null=$text.Append($span.Text).Append("`e[0m")
    }
    return $text.ToString()
}
function New-InspectorUiFrame {
    param($Report, $State, [int]$Width, [int]$Height, [object[]]$ModalLines=$null, [string]$ModalKind='Text')
    $frame=New-UiFrame
    if ($Width -lt 42 -or $Height -lt 12) {
        Add-InspectorFrameLine $frame ('Resize window; Q exits.'.Substring(0,[math]::Min(22,[math]::Max(1,$Width-2))))
        return $frame
    }
    $w=[math]::Min(112,$Width-2)
    $file=$Report.files[$State.File]
    $title=if (Test-UiAsciiGlyphMode) { 'MEDIA INFO' } else { '🎬 MEDIA INFO' }
    Add-InspectorFrameLine $frame "  `e[97;44m $title `e[0m  `e[96m$($script:InspectorTabs[$State.Tab])`e[0m"
    $name=ConvertTo-UiSafeSingleLineText ([IO.Path]::GetFileName($file.path))
    if ($name.Length -gt $w-4) { $name=$name.Substring(0,$w-7)+'...' }
    Add-InspectorFrameLine $frame "  `e[97m$name`e[0m"
    $tabs=[Collections.Generic.List[object]]::new()
    $tabNames=if ($w -ge 86) { $script:InspectorTabs } else { @('Info','Video','Time','Tracks','File','Cuts') }
    $spans=@((New-InspectorSpan '  '))
    for ($i=0;$i -lt 6;$i++) {
        if ($i -eq $State.Tab) { $spans+=New-InspectorSpan " $($i+1) $($tabNames[$i]) " Black Cyan }
        else { $spans+=New-InspectorSpan " $($i+1) $($tabNames[$i]) " DarkGray }
    }
    if ($w -lt 70) {
        $spans=@((New-InspectorSpan '  '),(New-InspectorSpan "$($State.Tab+1)/6  $($script:InspectorTabs[$State.Tab])   ← → Pages" Cyan))
    }
    Add-InspectorViewLine $tabs $spans
    Add-InspectorFrameLine $frame (ConvertTo-InspectorAnsiRow $tabs[0])
    Add-InspectorFrameLine $frame ("  `e[90m"+('─'*($w-3))+"`e[0m")
    $body=if ($null -ne $ModalLines) { @($ModalLines) } else { @(Get-InspectorDetailLines $Report $file $State.Tab $w $State.Video) }
    $bodyHeight=[math]::Max(1,$Height-10)
    $offset=if ($null -ne $ModalLines) { 0 } else { [math]::Clamp([int]$State.Offset,0,[math]::Max(0,$body.Count-$bodyHeight)) }
    if ($null -eq $ModalLines) { $State.Offset=$offset }
    for ($i=0;$i -lt $bodyHeight;$i++) {
        $row=if ($offset+$i -lt $body.Count) { ConvertTo-InspectorAnsiRow $body[$offset+$i] } else { '' }
        Add-InspectorFrameLine $frame "$row`e[K"
    }
    Add-InspectorFrameLine $frame ("  `e[90m"+('─'*($w-3))+"`e[0m")
    $footer=if ($null -ne $ModalLines) { 'Enter Confirm   Esc Cancel' }
        elseif ($State.Tab -eq 0 -and $w -ge 90) { 'C Copy overview   V Video details   A Smart Cut   J/T Export   F Files   Q Exit' }
        elseif ($State.Tab -eq 0) { 'C Copy  V Details  A Smart Cut  Q Exit' }
        elseif ($w -ge 90) { 'C Copy page   R Full report   D Timing sample   J/T Export   F Files   Q Exit' }
        else { 'C Copy  R Report  D Sample  J/T Export' }
    Add-InspectorFrameLine $frame "  `e[96m$footer`e[0m`e[K"
    $navigation=if ($null -ne $ModalLines) { if ($ModalKind -eq 'List') { '↑ ↓ Choose file' } else { 'Type a value; Backspace edits.' } } elseif ($w -ge 90) { '1–6 / ← → Pages   ↑ ↓ / PgUp PgDn Scroll   Esc Back   (no Enter needed)' } else { '←→ Pages  ↑↓ Scroll  [ ] Video  Esc/Q' }
    Add-InspectorFrameLine $frame "  `e[90m$navigation`e[0m`e[K"
    $status=if ($State.Status) { ConvertTo-UiSafeSingleLineText $State.Status } else { "File $($State.File+1)/$($Report.files.Count)  •  Rows $($offset+1)–$([math]::Min($offset+$bodyHeight,$body.Count))/$($body.Count)" }
    if ($status.Length -gt $w-4) { $status=$status.Substring(0,$w-7)+'...' }
    Add-InspectorFrameLine $frame "  `e[93m$status`e[0m`e[K"
    return $frame
}

function Read-InspectorUiText {
    param($Report,$State,[string]$Title,[string]$Hint,[string]$Default='')
    $value=$Default
    while ($true) {
        Lock-ViewportToWindow
        $size=$Host.UI.RawUI.WindowSize
        $lines=[Collections.Generic.List[object]]::new()
        $w=[math]::Max(40,[math]::Min(112,$size.Width-2))
        Add-InspectorViewSection $lines $Title $w
        Add-InspectorViewText $lines $Hint Gray $w
        Add-InspectorViewLine $lines @()
        # Show the editable tail; preserve the complete input for submission.
        $tail=if ($value.Length -gt $w-8) { '...'+$value.Substring($value.Length-($w-11)) } else { $value }
        Add-InspectorViewText $lines "> $tail▏" White $w
        Add-InspectorViewText $lines 'Enter: confirm   Esc: cancel   Backspace: edit' Cyan $w
        Write-UiFrame (New-InspectorUiFrame $Report $State $size.Width $size.Height -ModalLines $lines.ToArray())
        $key=Read-ConsoleKey
        switch ($key.Key) {
            'Escape' { return $null }
            'Enter' { return $value }
            'Backspace' { if ($value.Length) { $value=$value.Substring(0,$value.Length-1) } }
            default { if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) { $value += $key.KeyChar } }
        }
    }
}
function Select-InspectorUiFile {
    param($Report,$State)
    $selected=$State.File
    while ($true) {
        Lock-ViewportToWindow
        $size=$Host.UI.RawUI.WindowSize
        $w=[math]::Max(40,[math]::Min(112,$size.Width-2))
        $lines=[Collections.Generic.List[object]]::new()
        Add-InspectorViewText $lines 'FILES   ↑ ↓ choose / Enter open / Esc cancel' Cyan $w
        $count=[math]::Max(1,$size.Height-13)
        $first=[math]::Max(0,$selected-$count+1)
        for ($i=$first;$i -lt [math]::Min($Report.files.Count,$first+$count);$i++) {
            $name=ConvertTo-UiSafeSingleLineText ([IO.Path]::GetFileName($Report.files[$i].path))
            if ($name.Length -gt $w-9) { $name=$name.Substring(0,$w-12)+'...' }
            $prefix=if ($i -eq $selected) { '>' } else { ' ' }
            Add-InspectorViewText $lines "$prefix $($i+1)  $name" $(if ($i -eq $selected) { 'Cyan' } else { 'Gray' }) $w
        }
        Write-UiFrame (New-InspectorUiFrame $Report $State $size.Width $size.Height -ModalLines $lines.ToArray() -ModalKind List)
        $key=Read-ConsoleKey
        switch ($key.Key) {
            'Escape' { return }
            'Enter' { $State.File=$selected; $State.Offset=0; $State.Video=0; return }
            'UpArrow' { $selected=[math]::Max(0,$selected-1) }
            'DownArrow' { $selected=[math]::Min($Report.files.Count-1,$selected+1) }
        }
    }
}
function Get-InspectorShortcut {
    param($Key)
    # Shortcut identity is separate from text entry: Greek layout yields δ for D.
    # Prefer the console's key identity; character aliases also cover VT-only input.
    $name=([string]$Key.Key).ToLowerInvariant()
    if ($name -match '^[a-z]$') { return $name }
    if ($name -match '^(?:d|numpad)([1-6])$') { return $Matches[1] }
    $letter=([string]$Key.KeyChar).ToLowerInvariant()
    $greek=@{ 'α'='a'; 'ρ'='r'; 'δ'='d'; 'ψ'='c'; 'ξ'='j'; 'τ'='t'; 'φ'='f'; 'ω'='v'; 'σ'='s'; ';'='q' }
    if ($greek.ContainsKey($letter)) { return $greek[$letter] }
    return $letter
}
function Update-InspectorUiNavigation {
    param($State,$Key,[int]$PageSize=10)
    switch ($Key.Key) {
        'ResizeEvent' { return $true }
        'UpArrow' { $State.Offset=[math]::Max(0,$State.Offset-1); return $true }
        'DownArrow' { $State.Offset++; return $true }
        'PageUp' { $State.Offset=[math]::Max(0,$State.Offset-$PageSize); return $true }
        'PageDown' { $State.Offset+=$PageSize; return $true }
        'Home' { $State.Offset=0; return $true }
        'End' { $State.Offset=[int]::MaxValue; return $true }
        'LeftArrow' { $State.Tab=($State.Tab+5)%6; $State.Offset=0; return $true }
        { $_ -in 'RightArrow','Tab' } { $State.Tab=($State.Tab+1)%6; $State.Offset=0; return $true }
    }
    $letter=Get-InspectorShortcut $Key
    if ($letter -match '^[1-6]$') { $State.Tab=[int]$letter-1; $State.Offset=0; return $true }
    if ($letter -in 'v','s','a') { $State.Tab=switch ($letter) { 'v' {1} 'a' {5} default {0} }; $State.Offset=0; return $true }
    return $false
}
function Show-InspectorUi {
    param($Report,[string]$Executable,[int]$MaxPackets,[int]$TimeoutSeconds)
    $state=@{File=0;Tab=0;Video=0;Offset=0;Status=''}
    Initialize-TuiHost
    try {
        while ($true) {
            Lock-ViewportToWindow
            $size=$Host.UI.RawUI.WindowSize
            Write-UiFrame (New-InspectorUiFrame $Report $state $size.Width $size.Height)
            $key=Read-ConsoleKey
            if (Update-InspectorUiNavigation $state $key ([math]::Max(1,$size.Height-10))) {
                if ($key.Key -ne 'ResizeEvent') { $state.Status='' }
                continue
            }
            $letter=Get-InspectorShortcut $key
            if ($letter -eq 'q') { break }
            if ($key.Key -eq 'Escape') {
                if ($state.Tab -eq 0) { break }
                $state.Tab=0; $state.Offset=0; continue
            }
            $state.Status=''
            try {
                $entry=$Report.files[$state.File]
                $videos=@($entry.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
                switch ($letter) {
                    'f' { Select-InspectorUiFile $Report $state }
                    '[' { $state.Video=[math]::Max(0,$state.Video-1); $state.Offset=0 }
                    ']' { $state.Video=[math]::Max(0,[math]::Min($videos.Count-1,$state.Video+1)); $state.Offset=0 }
                    'c' {
                        $rows=Get-InspectorDetailLines $Report $entry $state.Tab 108 $state.Video
                        $text=@($entry.path; $rows | ForEach-Object { $_.Spans.Text -join '' }) -join [Environment]::NewLine
                        Set-Clipboard -Value $text; $state.Status='Current page copied.'
                    }
                    'r' { Set-Clipboard -Value (Format-InspectorReport $Report); $state.Status='Full technical report copied.' }
                    { $_ -in 'j','t' } {
                        $format=if ($letter -eq 'j') { 'Json' } else { 'Text' }
                        $path=Read-InspectorUiText $Report $state "EXPORT $($format.ToUpperInvariant())" 'New full path. Existing files are never overwritten.'
                        if ($path) { Export-InspectorReport $Report $path $format 6>$null; $state.Status="Saved: $path" }
                    }
                    'd' {
                        if (-not $videos.Count) { throw 'No video stream available.' }
                        $chosen=$videos[$state.Video].index
                        $answer=Read-InspectorUiText $Report $state "PACKET SAMPLE • STREAM $chosen" "Start timestamp in seconds. Up to $MaxPackets packets / $TimeoutSeconds seconds wall time. Esc cancels." '0'
                        if ($null -eq $answer) { continue }
                        $start=ConvertTo-InspectorNumber $answer
                        if ($null -eq $start -or $start -lt 0 -or $start -gt 2147483647) { throw 'Invalid start timestamp.' }
                        $entry.samples.Add((Get-InspectorPacketSample $Executable $entry $start $MaxPackets $TimeoutSeconds $chosen -CanCancel 6>$null))
                        $state.Tab=2; $state.Offset=0; $state.Status='Timing sample complete. 1 returns to the media overview.'
                        $resultRows=@(Get-InspectorDetailLines $Report $entry 2 ([math]::Max(40,[math]::Min(112,$size.Width-2))) $state.Video)
                        for ($rowIndex=0;$rowIndex -lt $resultRows.Count;$rowIndex++) {
                            if (($resultRows[$rowIndex].Spans.Text -join '') -match '^  MEASURED PACKET TIMING') { $state.Offset=$rowIndex; break }
                        }
                    }
                }
            } catch {
                $state.Status=$_.Exception.Message
                $Report.failures.Add([ordered]@{path=$entry.path;stage="UI $letter";error=$_.Exception.Message})
            }
        }
    } finally { Restore-TuiHost }
}
