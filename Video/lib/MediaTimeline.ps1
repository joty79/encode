# Shared read-only timing diagnostics for packet integrity and damaged-MP4 repair.
# Large presentation gaps can be intentional VFR: report review, not corruption.
function Get-MediaTimelineReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Ffprobe,
        [Parameter(Mandatory = $true)][string]$InputPath
    )

    $metadataJson = & $Ffprobe -v error -show_entries stream=index,codec_type -of json $InputPath
    if ($LASTEXITCODE -ne 0) { throw "Timeline stream probe failed: $InputPath" }
    $metadata = ($metadataJson | Out-String) | ConvertFrom-Json
    $byIndex = @{}
    foreach ($stream in $metadata.streams) {
        if ($stream.codec_type -notin @('video', 'audio')) { continue }
        $byIndex[[int]$stream.index] = [pscustomobject]@{
            Index = [int]$stream.index
            Type = [string]$stream.codec_type
            Pts = [System.Collections.Generic.List[double]]::new()
            PacketCount = 0
            MissingPts = 0
            MissingDts = 0
            PreviousDts = $null
            NonIncreasingDts = 0
        }
    }
    if ($byIndex.Count -eq 0) { throw 'Timeline probe found no video or audio streams.' }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Ffprobe
    # A resolved Windows filename cannot contain a double quote and is a file,
    # so it cannot end in the backslash which escapes a closing native quote.
    $startInfo.Arguments = '-v error -show_entries packet=stream_index,pts_time,dts_time -of csv=p=0 "{0}"' -f $InputPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $numberStyle = [Globalization.NumberStyles]::Float
    try {
        while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
            $parts = $line.Split(',')
            $streamIndex = 0
            if ($parts.Count -lt 3 -or -not [int]::TryParse($parts[0], [ref]$streamIndex)) { continue }
            if (-not $byIndex.ContainsKey($streamIndex)) { continue }
            $stat = $byIndex[$streamIndex]
            $stat.PacketCount++
            $pts = 0.0
            if ([double]::TryParse($parts[1], $numberStyle, $culture, [ref]$pts)) {
                $stat.Pts.Add($pts)
            } else { $stat.MissingPts++ }
            $dts = 0.0
            if ([double]::TryParse($parts[2], $numberStyle, $culture, [ref]$dts)) {
                if ($null -ne $stat.PreviousDts -and $dts -le $stat.PreviousDts) { $stat.NonIncreasingDts++ }
                $stat.PreviousDts = $dts
            } else { $stat.MissingDts++ }
        }
        $process.WaitForExit()
        $probeExitCode = $process.ExitCode
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($probeExitCode -ne 0) { throw "Timeline packet probe failed ($probeExitCode): $stderr" }
    } finally { $process.Dispose() }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($streamIndex in ($byIndex.Keys | Sort-Object)) {
        $stat = $byIndex[$streamIndex]
        [double[]]$times = $stat.Pts.ToArray()
        # Packets arrive in decode order. Sorting PTS avoids treating healthy
        # B-frame reordering as broken presentation timing; DTS remains ordered.
        [Array]::Sort($times)
        $positiveDeltas = [System.Collections.Generic.List[double]]::new()
        $duplicatePts = 0
        for ($i = 1; $i -lt $times.Length; $i++) {
            $delta = $times[$i] - $times[$i - 1]
            if ($delta -gt 0) { $positiveDeltas.Add($delta) } else { $duplicatePts++ }
        }
        [double[]]$cadences = $positiveDeltas.ToArray()
        [Array]::Sort($cadences)
        $cadence = 0.0
        if ($cadences.Length -gt 0) {
            $middle = [int][Math]::Floor($cadences.Length / 2.0)
            $cadence = $cadences[$middle]
            if ($cadences.Length % 2 -eq 0) { $cadence = ($cadence + $cadences[$middle - 1]) / 2.0 }
        }
        # Do not trust packet duration here: muxers may stretch it across the
        # entire gap. Median PTS cadence also avoids using the depressed avg FPS.
        $threshold = [Math]::Max(0.20, 4.0 * $cadence)
        $gaps = [System.Collections.Generic.List[object]]::new()
        $totalExcess = 0.0
        $maxHold = 0.0
        for ($i = 1; $i -lt $times.Length; $i++) {
            $delta = $times[$i] - $times[$i - 1]
            if ($delta -gt $threshold) {
                $gaps.Add([pscustomobject]@{ Before = $times[$i - 1]; After = $times[$i]; Seconds = $delta })
                $totalExcess += $delta - $cadence
                $maxHold = [Math]::Max($maxHold, $delta)
            }
        }
        $needsReview = $gaps.Count -gt 0 -or $stat.NonIncreasingDts -gt 0 -or $duplicatePts -gt 0 -or
            $stat.MissingPts -gt 0 -or $stat.MissingDts -gt 0 -or $cadences.Length -lt 2
        $rows.Add([pscustomobject]@{
            Index = $streamIndex; Type = $stat.Type; PacketCount = $stat.PacketCount
            CadenceSeconds = $cadence; GapCount = $gaps.Count; MaxHoldSeconds = $maxHold
            GapExcessSeconds = $totalExcess; Gaps = $gaps.ToArray()
            NonIncreasingDts = $stat.NonIncreasingDts; DuplicatePts = $duplicatePts
            MissingPts = $stat.MissingPts; MissingDts = $stat.MissingDts
            InsufficientTiming = $cadences.Length -lt 2; NeedsReview = $needsReview
        })
    }
    return [pscustomobject]@{
        Streams = $rows.ToArray()
        NeedsReview = @($rows | Where-Object { $_.NeedsReview }).Count -gt 0
    }
}

function Write-MediaTimelineReport {
    param([Parameter(Mandatory = $true)][object]$Report)
    foreach ($row in $Report.Streams) {
        Write-Host ('Timeline {0}:{1}: {2} large PTS gaps; longest {3:F3}s; total excess over usual cadence {4:F3}s.' -f
            $row.Type, $row.Index, $row.GapCount, $row.MaxHoldSeconds, $row.GapExcessSeconds)
        foreach ($gap in ($row.Gaps | Select-Object -First 3)) {
            Write-Host ('  {0:F3}s -> {1:F3}s ({2:F3}s between packets)' -f $gap.Before, $gap.After, $gap.Seconds)
        }
        if ($row.NonIncreasingDts -gt 0 -or $row.DuplicatePts -gt 0 -or $row.MissingPts -gt 0 -or $row.MissingDts -gt 0 -or $row.InsufficientTiming) {
            Write-Host ('  Non-increasing DTS: {0}; duplicate PTS: {1}; missing PTS/DTS: {2}/{3}; insufficient timing: {4}.' -f
                $row.NonIncreasingDts, $row.DuplicatePts, $row.MissingPts, $row.MissingDts, $row.InsufficientTiming) -ForegroundColor Yellow
        }
    }
    if ($Report.NeedsReview) {
        Write-Warning 'TIMELINE REVIEW REQUIRED: gaps or timestamp anomalies can cause freezes or difficult seeking even when packets decode cleanly. Intentional VFR can also contain gaps. This is not a lip-sync measurement.'
    } else {
        Write-Host 'No suspicious timeline gaps or timestamp ordering issues found. Image content and lip-sync were not assessed.' -ForegroundColor Gray
    }
}
