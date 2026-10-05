function Invoke-InspectorProbe {
    param([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds=30, [switch]$CanCancel)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $started = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(100)) {
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "ffprobe timed out after $TimeoutSeconds seconds; partial output discarded." }
            if ($CanCancel -and -not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
                if ([Console]::ReadKey($true).Key -eq 'Escape') { throw 'ffprobe cancelled; partial output discarded.' }
            }
            Write-Progress -Activity 'Media inspection (Esc cancels in interactive mode)' -Status ('ffprobe: {0:N1}s / {1}s limit' -f $timer.Elapsed.TotalSeconds,$TimeoutSeconds)
        }
        $exitCode = $process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($exitCode -ne 0) { throw "ffprobe failed (exit $exitCode): $stderr" }
        return [pscustomobject]@{ stdout=$stdout; stderr=$stderr.Trim(); exitCode=$exitCode; arguments=$Arguments; elapsedSeconds=$timer.Elapsed.TotalSeconds }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
        Write-Progress -Activity 'Media inspection (Esc cancels in interactive mode)' -Completed
    }
}

function ConvertTo-InspectorNumber {
    param($Value)
    $number = 0.0
    if ([double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -and
        -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { return $number }
    return $null
}
function Get-InspectorRational {
    param($Value)
    $result = [ordered]@{ raw=$Value; numerator=$null; denominator=$null; decimal=$null; status='Unknown' }
    if ([string]$Value -match '^(-?\d+)/(\d+)$') {
        $result.numerator = ConvertTo-InspectorNumber $Matches[1]
        $result.denominator = ConvertTo-InspectorNumber $Matches[2]
        if ($result.numerator -gt 0 -and $result.denominator -gt 0) {
            $result.decimal = $result.numerator / $result.denominator
            $result.status = 'Reported rational'
        }
    }
    return [pscustomobject]$result
}
function Get-InspectorScan {
    param($FieldOrder)
    switch ($FieldOrder) {
        'progressive' { return 'Progressive (reported)' }
        { $_ -in 'tt','bb','tb','bt' } { return "Interlaced (reported: $FieldOrder)" }
        default { return 'Unknown' }
    }
}
function New-InspectorEntry {
    param($File, $Metadata, $Probe)
    $streams = foreach ($stream in $Metadata.streams) {
        $fields = [ordered]@{}
        foreach ($name in @('index','codec_type','codec_name','codec_long_name','codec_tag_string','codec_tag','profile','level',
            'width','height','coded_width','coded_height','pix_fmt','bits_per_raw_sample','bits_per_sample','chroma_location',
            'field_order','color_range','color_primaries','color_transfer','color_space','sample_aspect_ratio','display_aspect_ratio',
            'r_frame_rate','avg_frame_rate','time_base','start_time','start_pts','duration','duration_ts','nb_frames',
            'bit_rate','has_b_frames','is_avc','nal_length_size','extradata_size','sample_fmt','sample_rate','channels','channel_layout',
            'disposition','side_data_list')) { $fields[$name] = $stream.$name }
        $fields.tags = [ordered]@{ language=$stream.tags.language; title=$stream.tags.title; rotate=$stream.tags.rotate }
        $fields.nominalFps = Get-InspectorRational $stream.r_frame_rate
        $fields.averageFps = Get-InspectorRational $stream.avg_frame_rate
        $fields.scan = Get-InspectorScan $stream.field_order
        $fields.timingMode = 'Not analyzed (metadata FPS equality/inequality does not establish CFR/VFR)'
        $fields.bitDepth = $null; $fields.bitDepthSource = 'Unknown'; $fields.chroma = 'Unknown'
        $bits = ConvertTo-InspectorNumber $stream.bits_per_raw_sample
        if ($bits -gt 0) { $fields.bitDepth=$bits; $fields.bitDepthSource='stream.bits_per_raw_sample' }
        # Deliberately narrow derivation; unknown format names remain unknown.
        if ([string]$stream.pix_fmt -match '^yuva?j?(420|422|444)p(?:(9|10|12|14|16)(?:le|be))?$') {
            $chromaDigits = $Matches[1]; $depthDigits = $Matches[2]
            $fields.chroma = $chromaDigits -replace '(\d)(\d)(\d)', '$1:$2:$3'
            if ($null -eq $fields.bitDepth) {
                $fields.bitDepth = if ($depthDigits) { [int]$depthDigits } else { 8 }
                $fields.bitDepthSource = 'derived from pix_fmt name'
            }
        }
        $fields.compressionDensity=$null; $fields.bitratePolicy='Unknown'
        $rate = ConvertTo-InspectorNumber $stream.bit_rate
        if ($stream.codec_type -eq 'video' -and $rate -gt 0 -and $fields.averageFps.decimal -gt 0) {
            $fields.compressionDensity = Get-CompressionDensity $stream.width $stream.height $fields.averageFps.decimal ($rate/1e6)
            $fields.bitratePolicy = Get-BitratePolicy $stream.height $fields.averageFps.decimal ($rate/1e6)
        }
        [pscustomobject]$fields
    }
    $format = [ordered]@{}
    foreach ($name in @('format_name','format_long_name','start_time','duration','size','bit_rate','probe_score')) { $format[$name]=$Metadata.format.$name }
    $format.brands = [ordered]@{ major=$Metadata.format.tags.major_brand; compatible=$Metadata.format.tags.compatible_brands }
    $duration = ConvertTo-InspectorNumber $Metadata.format.duration
    $format.fileAverageBitrate = if ($duration -gt 0) { $File.Length*8/$duration } else { $null }
    return [ordered]@{
        path=$File.FullName; sizeBytes=$File.Length; lastWriteUtc=$File.LastWriteTimeUtc.ToString('o')
        provenance=[ordered]@{ source='ffprobe -show_streams -show_format; reported metadata, no whole-file decode/scan'; arguments=$Probe.arguments; stderr=$Probe.stderr; exitCode=$Probe.exitCode }
        format=$format; streams=@($streams); samples=[Collections.Generic.List[object]]::new()
    }
}
function Measure-InspectorPackets {
    param([object[]]$Packets, $Stream)
    $timeBase = Get-InspectorRational $Stream.time_base
    if (-not $timeBase.decimal) { throw 'Cannot measure packet timestamps: missing/invalid time_base.' }
    $tick = [decimal]$timeBase.numerator/[decimal]$timeBase.denominator
    $pts = [Collections.Generic.List[decimal]]::new()
    $keys = [Collections.Generic.List[decimal]]::new()
    $missingPts=0; $missingDts=0; $backwardsDts=0; $duplicateDts=0; $reorderedPts=0; $keyFlagCount=0
    $previousDts=$null; $previousPts=$null
    foreach ($packet in $Packets) {
        $stamp = 0L
        if ($packet.flags -like '*K*') { $keyFlagCount++ }
        if ([long]::TryParse([string]$packet.pts,[ref]$stamp)) {
            $pts.Add([decimal]$stamp)
            if ($null -ne $previousPts -and $stamp -lt $previousPts) { $reorderedPts++ }
            $previousPts=$stamp
            if ($packet.flags -like '*K*') { $keys.Add([decimal]$stamp) }
        } else { $missingPts++ }
        if ([long]::TryParse([string]$packet.dts,[ref]$stamp)) {
            if ($null -ne $previousDts) {
                if ($stamp -lt $previousDts) { $backwardsDts++ }
                if ($stamp -eq $previousDts) { $duplicateDts++ }
            }
            $previousDts=$stamp
        } else { $missingDts++ }
    }
    $sorted = @($pts | Sort-Object)
    $deltas = [Collections.Generic.List[decimal]]::new()
    $examples = [Collections.Generic.List[object]]::new()
    $nominal = Get-InspectorRational $Stream.r_frame_rate
    $expected = if ($nominal.decimal) { 1.0/$nominal.decimal } else { $null }
    $tolerance = if ($expected) { [math]::Max([double]$tick*1.01,$expected*0.01) } else { $null }
    $tiny=0; $duplicates=0; $deviations=0
    $firstTinySeconds=$null; $lastTinySeconds=$null
    for ($i=1; $i -lt $sorted.Count; $i++) {
        $delta = ($sorted[$i]-$sorted[$i-1])*$tick
        $deltas.Add($delta)
        $kind=$null
        if ($delta -eq 0) { $duplicates++; $kind='Duplicate PTS' }
        elseif ($expected -and $delta -lt $expected*0.01) {
            $tiny++; $kind='Tiny interval (<1% nominal)'
            if ($null -eq $firstTinySeconds) { $firstTinySeconds=$sorted[$i-1]*$tick }
            $lastTinySeconds=$sorted[$i]*$tick
        }
        if ($expected -and [math]::Abs([double]$delta-$expected) -gt $tolerance) {
            $deviations++
            if (-not $kind) { $kind='Nominal interval deviation' }
        }
        if ($kind -and $examples.Count -lt 20) {
            $examples.Add([ordered]@{ fromPts=[string]$sorted[$i-1]; toPts=[string]$sorted[$i]; fromSeconds=$sorted[$i-1]*$tick; toSeconds=$sorted[$i]*$tick; deltaSeconds=$delta; kind=$kind })
        }
    }
    $keyTimes = @($keys | Sort-Object)
    $keyGaps = for ($i=1; $i -lt $keyTimes.Count; $i++) { ($keyTimes[$i]-$keyTimes[$i-1])*$tick }
    $stats = $deltas | Measure-Object -Minimum -Maximum -Average
    return [ordered]@{
        method='Integer packet PTS sorted into presentation order; deltas scaled by stream time_base. Packets are not necessarily decoded frames.'
        packetCount=$Packets.Count; ptsCount=$pts.Count; missingPts=$missingPts; missingDts=$missingDts; timeBase=$Stream.time_base
        minPts=if ($sorted.Count) { [string]$sorted[0] } else { $null }
        maxPts=if ($sorted.Count) { [string]$sorted[-1] } else { $null }
        firstPtsSeconds=if ($sorted.Count) { $sorted[0]*$tick } else { $null }
        lastPtsSeconds=if ($sorted.Count) { $sorted[-1]*$tick } else { $null }
        intervals=$deltas.Count; minIntervalSeconds=$stats.Minimum; maxIntervalSeconds=$stats.Maximum; meanIntervalSeconds=$stats.Average
        nominalIntervalSeconds=$expected; deviationToleranceSeconds=$tolerance; duplicatePts=$duplicates
        tinyPositiveIntervals=if ($expected) { $tiny } else { $null }
        firstTinySeconds=$firstTinySeconds; lastTinySeconds=$lastTinySeconds
        nominalDeviations=if ($expected) { $deviations } else { $null }
        backwardsDts=$backwardsDts; duplicateDts=$duplicateDts; ptsBackwardsInPacketOrder=$reorderedPts
        commonIntervals=@($deltas | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { [ordered]@{ seconds=$_.Group[0]; count=$_.Count } })
        anomalyExamples=@($examples)
        keyFlagCount=$keyFlagCount; keyFlagsWithPts=$keys.Count
        minKeyFlagGapSeconds=($keyGaps | Measure-Object -Minimum).Minimum
        maxKeyFlagGapSeconds=($keyGaps | Measure-Object -Maximum).Maximum
        keyEvidence='ffprobe packet K flags only; not IDR, closed GOP, recovery point or safe-cut proof. PTS reordering may be normal with B-frames.'
        verdict=if ($deltas.Count -lt 1) { 'Insufficient timestamp evidence' } else { 'Sample measured; full-file CFR/VFR, decode integrity and dependency windows not established' }
    }
}
function Get-InspectorPacketSample {
    param([string]$Executable, $Entry, [double]$StartSeconds, [int]$MaxPackets, [int]$TimeoutSeconds, $StreamIndex, [switch]$CanCancel)
    $videos = @($Entry.streams | Where-Object { $_.codec_type -eq 'video' -and $_.disposition.attached_pic -ne 1 })
    $stream = if ($null -eq $StreamIndex) { $videos | Select-Object -First 1 } else { $videos | Where-Object index -eq $StreamIndex | Select-Object -First 1 }
    if (-not $stream) { throw 'Requested non-cover video stream not found.' }
    $interval = $StartSeconds.ToString('0.#########',[Globalization.CultureInfo]::InvariantCulture)+'%+#'+$MaxPackets
    $arguments = @('-v','error','-select_streams',"$($stream.index)",'-read_intervals',$interval,'-show_packets','-show_entries','packet=pts,dts,duration,flags','-of','json',$Entry.path)
    Write-Host "Packet sample: stream $($stream.index), seek $StartSeconds s, at most $MaxPackets packets / $TimeoutSeconds s."
    $probe = Invoke-InspectorProbe $Executable $arguments $TimeoutSeconds -CanCancel:$CanCancel
    $data = $probe.stdout | ConvertFrom-Json
    if ($null -eq $data.packets) { throw 'Invalid packet output: packets array missing.' }
    return [ordered]@{
        scope='Bounded packet sample, no full-file claim. Seek can land earlier; inspect actual PTS coverage. Partial reorder groups at sample edges can create gaps. No decode or dependency mapping.'
        measuredUtc=[DateTime]::UtcNow.ToString('o')
        streamIndex=$stream.index; requestedStartSeconds=$StartSeconds; packetLimit=$MaxPackets; timeoutSeconds=$TimeoutSeconds
        readInterval=$interval; arguments=$arguments; exitCode=$probe.exitCode; stderr=$probe.stderr; elapsedSeconds=$probe.elapsedSeconds
        measured=Measure-InspectorPackets @($data.packets) $stream
    }
}
function Export-InspectorReport {
    param($Report, [string]$Path, [ValidateSet('Json','Text')][string]$Format)
    Update-InspectorDiagnoses $Report
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $content = if ($Format -eq 'Json') { ConvertTo-Json -InputObject $Report -Depth 30 } else { Format-InspectorReport $Report }
    # Refuse every collision, including input media and configuration.
    $stream = [IO.File]::Open($fullPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($content+[Environment]::NewLine)
        $stream.Write($bytes,0,$bytes.Length)
    } finally { $stream.Dispose() }
    Write-Host "Saved: $fullPath"
}
