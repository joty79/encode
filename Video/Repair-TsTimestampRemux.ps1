param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$TempDirectory,

    [Parameter()]
    [switch]$AnalyzeOnly,

    [Parameter()]
    [switch]$SkipInputAnalysis,

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [switch]$MoveProblemFiles,

    [Parameter()]
    [string]$ProblemFolderName = '_TS_TIMESTAMP_PROBLEMS',

    [Parameter()]
    [string]$OutputFolderName = '_TS_FIXED_MP4',

    [Parameter()]
    [switch]$SkipSettsRepair,

    [Parameter()]
    [switch]$KeepSource,

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

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    Write-Host ''
    Write-Host ('🔧 {0}' -f $Text) -ForegroundColor Cyan
}

function Write-Ok {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    Write-Host ('✅ {0}' -f $Text) -ForegroundColor Green
}

function Write-Warn {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    Write-Host ('⚠️  {0}' -f $Text) -ForegroundColor Yellow
}

function Write-Bad {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    Write-Host ('❌ {0}' -f $Text) -ForegroundColor Red
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

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Exe,

        [Parameter(Mandatory = $true)]
        [string[]]$CommandArgs,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Write-Step $Label
    Write-Host ('  {0} {1}' -f $Exe, ($CommandArgs -join ' '))

    & $Exe @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

function Get-MediaSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ffprobe,

        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $json = & $Ffprobe -hide_banner -v error -show_format -show_streams -of json $InputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe metadata read failed for '$InputPath'."
    }

    return ($json | ConvertFrom-Json)
}

function New-StreamStat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StreamIndex,

        [Parameter(Mandatory = $true)]
        [double]$FirstPts
    )

    return [pscustomobject]@{
        StreamIndex = $StreamIndex
        Packets = 0
        Gaps = 0
        ApproxMissingSeconds = 0.0
        MaxGapSeconds = 0.0
        CadenceShort = 0
        CadenceLong = 0
        MinDeltaSeconds = [double]::PositiveInfinity
        MaxDeltaSeconds = 0.0
        TinyPts = 0
        TinyDts = 0
        PtsBackwards = 0
        DtsBackwards = 0
        FirstPts = $FirstPts
        LastPts = $FirstPts
    }
}

function Get-TimestampStats {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ffprobe,

        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $streamInfoJson = & $Ffprobe -hide_banner -v error -show_entries 'stream=index,codec_type' -of json $InputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe stream map failed for '$InputPath'."
    }

    $streamTypeByIndex = @{}
    $streamInfo = $streamInfoJson | ConvertFrom-Json
    foreach ($stream in @($streamInfo.streams)) {
        $streamTypeByIndex[[string]$stream.index] = [string]$stream.codec_type
    }

    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $Ffprobe
    $probeArgs = @(
        '-hide_banner',
        '-v', 'error',
        '-show_packets',
        '-show_entries', 'packet=stream_index,pts_time,dts_time,duration_time,flags',
        '-of', 'csv=p=0',
        $InputPath
    )

    foreach ($probeArg in $probeArgs) {
        [void]$processInfo.ArgumentList.Add($probeArg)
    }

    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $previousByStream = @{}
    $statsByStream = @{}

    while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split ','
        if ($parts.Count -lt 5) {
            continue
        }

        $streamIndex = $parts[0]
        $pts = 0.0
        $dts = 0.0
        $duration = 0.0
        $style = [Globalization.NumberStyles]::Float
        $culture = [Globalization.CultureInfo]::InvariantCulture

        if (-not [double]::TryParse($parts[1], $style, $culture, [ref]$pts)) {
            continue
        }
        [void][double]::TryParse($parts[2], $style, $culture, [ref]$dts)
        [void][double]::TryParse($parts[3], $style, $culture, [ref]$duration)

        if (-not $statsByStream.ContainsKey($streamIndex)) {
            $statsByStream[$streamIndex] = New-StreamStat -StreamIndex $streamIndex -FirstPts $pts
        }

        $stat = $statsByStream[$streamIndex]
        $stat.Packets++

        if ($previousByStream.ContainsKey($streamIndex)) {
            $previous = $previousByStream[$streamIndex]
            $ptsDelta = $pts - $previous.Pts
            $dtsDelta = $dts - $previous.Dts
            $expectedDuration = if ($duration -gt 0) { $duration } else { 0.033367 }

            if ($ptsDelta -lt 0) {
                $stat.PtsBackwards++
            }
            if ($dtsDelta -lt 0) {
                $stat.DtsBackwards++
            }
            if ([Math]::Abs($ptsDelta) -lt 0.0005) {
                $stat.TinyPts++
            }
            if ([Math]::Abs($dtsDelta) -lt 0.0005) {
                $stat.TinyDts++
            }
            if ($ptsDelta -gt 0.0005) {
                if ($ptsDelta -lt $stat.MinDeltaSeconds) {
                    $stat.MinDeltaSeconds = $ptsDelta
                }
                if ($ptsDelta -gt $stat.MaxDeltaSeconds) {
                    $stat.MaxDeltaSeconds = $ptsDelta
                }
                if ($ptsDelta -lt ($expectedDuration - 0.0005)) {
                    $stat.CadenceShort++
                }
                elseif (($ptsDelta -gt ($expectedDuration + 0.0005)) -and ($ptsDelta -le 0.20)) {
                    $stat.CadenceLong++
                }
            }
            if ($ptsDelta -gt [Math]::Max(0.20, $expectedDuration * 4.0)) {
                $stat.Gaps++
                $stat.ApproxMissingSeconds += ($ptsDelta - $expectedDuration)
                if ($ptsDelta -gt $stat.MaxGapSeconds) {
                    $stat.MaxGapSeconds = $ptsDelta
                }
            }
        }

        $stat.LastPts = $pts
        $previousByStream[$streamIndex] = [pscustomobject]@{
            Pts = $pts
            Dts = $dts
        }
    }

    $process.WaitForExit()
    $stderr = $process.StandardError.ReadToEnd()
    if ($process.ExitCode -ne 0) {
        throw "ffprobe packet scan failed for '$InputPath'. $stderr"
    }

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($streamIndex in ($statsByStream.Keys | Sort-Object {[int]$_})) {
        $stat = $statsByStream[$streamIndex]
        $streamName = if ($streamTypeByIndex.ContainsKey($streamIndex)) {
            $streamTypeByIndex[$streamIndex]
        } else {
            "stream-$streamIndex"
        }

        $result.Add([pscustomobject]@{
            Stream = $streamName
            Packets = $stat.Packets
            Gaps = $stat.Gaps
            CadenceShort = $stat.CadenceShort
            CadenceLong = $stat.CadenceLong
            CadenceJitter = ($stat.CadenceShort + $stat.CadenceLong)
            MinDeltaSeconds = if ([double]::IsInfinity($stat.MinDeltaSeconds)) { '0.000' } else { '{0:F3}' -f $stat.MinDeltaSeconds }
            MaxDeltaSeconds = '{0:F3}' -f $stat.MaxDeltaSeconds
            ApproxMissingSeconds = '{0:F3}' -f $stat.ApproxMissingSeconds
            MaxGapSeconds = '{0:F3}' -f $stat.MaxGapSeconds
            TinyPts = $stat.TinyPts
            TinyDts = $stat.TinyDts
            PtsBackwards = $stat.PtsBackwards
            DtsBackwards = $stat.DtsBackwards
            FirstPts = '{0:F3}' -f $stat.FirstPts
            LastPts = '{0:F3}' -f $stat.LastPts
        }) | Out-Null
    }

    return $result
}

function Write-TimestampStats {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [object[]]$Stats
    )

    Write-Host ''
    Write-Host $Title
    $Stats |
        Select-Object `
            Stream,
            Packets,
            Gaps,
            @{Label = 'MaxGap'; Expression = { $_.MaxGapSeconds } },
            @{Label = 'Jitter'; Expression = { $_.CadenceJitter } },
            TinyPts,
            TinyDts,
            @{Label = 'BackPts'; Expression = { $_.PtsBackwards } },
            @{Label = 'BackDts'; Expression = { $_.DtsBackwards } },
            FirstPts |
        Format-Table -AutoSize |
        Out-String |
        Write-Host
}

function Test-StatsCleanForMuxing {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Stats
    )

    foreach ($stat in $Stats) {
        if (($stat.TinyPts -gt 0) -or ($stat.TinyDts -gt 0) -or ($stat.PtsBackwards -gt 0) -or ($stat.DtsBackwards -gt 0)) {
            return $false
        }
    }

    return $true
}

function Get-TimestampIssueInfo {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Stats
    )

    $tinyPts = 0
    $tinyDts = 0
    $ptsBackwards = 0
    $dtsBackwards = 0
    $gaps = 0
    $videoCadenceJitter = 0
    $videoPackets = 0
    $maxGapSeconds = 0.0

    foreach ($stat in $Stats) {
        $tinyPts += [int]$stat.TinyPts
        $tinyDts += [int]$stat.TinyDts
        $ptsBackwards += [int]$stat.PtsBackwards
        $dtsBackwards += [int]$stat.DtsBackwards
        $gaps += [int]$stat.Gaps
        if ($stat.Stream -eq 'video') {
            $videoCadenceJitter += [int]$stat.CadenceJitter
            $videoPackets += [int]$stat.Packets
        }
        $gapValue = 0.0
        [void][double]::TryParse([string]$stat.MaxGapSeconds, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$gapValue)
        if ($gapValue -gt $maxGapSeconds) {
            $maxGapSeconds = $gapValue
        }
    }

    $hardProblems = $tinyPts + $tinyDts + $ptsBackwards + $dtsBackwards
    $videoCadenceRatio = if ($videoPackets -gt 1) { $videoCadenceJitter / [double]($videoPackets - 1) } else { 0.0 }
    $videoCadenceRisk = (($videoCadenceJitter -ge 1000) -or (($videoCadenceJitter -ge 20) -and ($videoCadenceRatio -ge 0.05)))
    $status = if (($hardProblems -gt 0) -or $videoCadenceRisk) {
        'PROBLEM'
    } elseif ($gaps -gt 0) {
        'WARN'
    } else {
        'OK'
    }

    $summaryParts = New-Object System.Collections.Generic.List[string]
    if ($tinyPts -gt 0) { $summaryParts.Add("TinyPts=$tinyPts") | Out-Null }
    if ($tinyDts -gt 0) { $summaryParts.Add("TinyDts=$tinyDts") | Out-Null }
    if ($ptsBackwards -gt 0) { $summaryParts.Add("PtsBackwards=$ptsBackwards") | Out-Null }
    if ($dtsBackwards -gt 0) { $summaryParts.Add("DtsBackwards=$dtsBackwards") | Out-Null }
    if ($gaps -gt 0) { $summaryParts.Add(("Gaps={0}, MaxGap={1:F3}s" -f $gaps, $maxGapSeconds)) | Out-Null }
    if ($videoCadenceRisk) { $summaryParts.Add(("VideoCadenceJitter={0} ({1:P1})" -f $videoCadenceJitter, $videoCadenceRatio)) | Out-Null }
    if ($summaryParts.Count -eq 0) { $summaryParts.Add('No timestamp issues') | Out-Null }

    return [pscustomobject]@{
        Status = $status
        IsProblem = (($hardProblems -gt 0) -or $videoCadenceRisk)
        Summary = ($summaryParts -join ' | ')
        HardProblems = $hardProblems
        Gaps = $gaps
        VideoCadenceRisk = $videoCadenceRisk
        VideoCadenceJitter = $videoCadenceJitter
        VideoCadenceRatio = $videoCadenceRatio
        MaxGapSeconds = $maxGapSeconds
    }
}

function Write-StatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [int]$Total,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [object]$IssueInfo
    )

    $prefix = '[{0}/{1}] {2}' -f $Index, $Total, $FileName
    switch ($IssueInfo.Status) {
        'OK' { Write-Host ('✅ {0} — OK — {1}' -f $prefix, $IssueInfo.Summary) -ForegroundColor Green }
        'WARN' { Write-Host ('⚠️  {0} — WARN — {1}' -f $prefix, $IssueInfo.Summary) -ForegroundColor Yellow }
        'PROBLEM' { Write-Host ('❌ {0} — PROBLEM — {1}' -f $prefix, $IssueInfo.Summary) -ForegroundColor Red }
        default { Write-Host ('• {0} — {1} — {2}' -f $prefix, $IssueInfo.Status, $IssueInfo.Summary) }
    }
}

function Get-UniqueDestinationPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    $candidate = Join-Path -Path $Directory -ChildPath $FileName
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $baseName = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    $index = 1
    do {
        $candidateName = '{0}_{1}{2}' -f $baseName, $index, $extension
        $candidate = Join-Path -Path $Directory -ChildPath $candidateName
        $index++
    } while (Test-Path -LiteralPath $candidate)

    return $candidate
}

function Move-ProblemTsFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory = $true)]
        [string]$FolderRoot
    )

    $problemDirectory = Join-Path -Path $FolderRoot -ChildPath $ProblemFolderName
    if (-not (Test-Path -LiteralPath $problemDirectory)) {
        New-Item -ItemType Directory -Path $problemDirectory | Out-Null
    }

    $destinationPath = Get-UniqueDestinationPath -Directory $problemDirectory -FileName $File.Name
    Move-Item -LiteralPath $File.FullName -Destination $destinationPath
    Write-Host ('📦 Moved problem file -> {0}' -f $destinationPath) -ForegroundColor Magenta
    return $destinationPath
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [object]$Default = ''
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $Default
}

function Get-DefaultOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $directory = [IO.Path]::GetDirectoryName($InputPath)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $outputDirectory = Join-Path -Path $directory -ChildPath $OutputFolderName
    return (Join-Path -Path $outputDirectory -ChildPath ($baseName + '.mp4'))
}

function Remove-SourceTsAfterSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    if ($KeepSource) {
        Write-Warn 'Source file kept because -KeepSource was used.'
        return
    }

    if ([IO.Path]::GetExtension($InputPath) -ne '.ts') {
        Write-Warn ('Source was not deleted because it is not a .ts file: {0}' -f $InputPath)
        return
    }

    $resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
    $resolvedOutput = (Resolve-Path -LiteralPath $OutputPath).Path
    if ([string]::Equals($resolvedInput, $resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to delete source because input and output resolved to the same path.'
    }

    $outputItem = Get-Item -LiteralPath $resolvedOutput
    if ($outputItem.Length -le 0) {
        throw "Refusing to delete source because output is empty: $resolvedOutput"
    }

    Remove-Item -LiteralPath $resolvedInput -Force
    Write-Host ('🗑️  Deleted source TS after successful fix: {0}' -f $resolvedInput) -ForegroundColor DarkGray
}

function Invoke-TsTimestampRemux {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ffmpeg,

        [Parameter(Mandatory = $true)]
        [string]$Ffprobe,

        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter()]
        [string]$RequestedOutputPath
    )

    $resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
    $usingDefaultOutputPath = (-not $RequestedOutputPath)
    $effectiveOutputPath = if ($usingDefaultOutputPath) { Get-DefaultOutputPath -InputPath $resolvedInputPath } else { $RequestedOutputPath }
    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($effectiveOutputPath)
    if ([string]::Equals($resolvedInputPath, $resolvedOutputPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Input and output paths cannot be the same.'
    }

    $outputDirectory = [IO.Path]::GetDirectoryName($resolvedOutputPath)
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        if ($usingDefaultOutputPath) {
            New-Item -ItemType Directory -Path $outputDirectory | Out-Null
        } else {
            throw "Output directory does not exist: $outputDirectory"
        }
    }

    $effectiveTempDirectory = if ($TempDirectory) { $TempDirectory } else { $outputDirectory }
    $resolvedTempDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($effectiveTempDirectory)
    if (-not (Test-Path -LiteralPath $resolvedTempDirectory)) {
        throw "Temp directory does not exist: $resolvedTempDirectory"
    }

    $media = Get-MediaSummary -Ffprobe $Ffprobe -InputPath $resolvedInputPath
    $videoStream = $media.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
    $audioStream = $media.streams | Where-Object { $_.codec_type -eq 'audio' } | Select-Object -First 1

    Write-ToolHeader -Title 'TS Timestamp Remux'
    Write-Host ('📄 Input:    {0}' -f $resolvedInputPath)
    Write-Host ('📦 Format:   {0}' -f $media.format.format_name)
    Write-Host ('⏱️  Duration: {0}' -f (Format-Seconds -Seconds ([double]$media.format.duration)))
    if ($videoStream) {
        $videoFrames = Get-ObjectPropertyValue -Object $videoStream -Name 'nb_frames' -Default 'unknown'
        Write-Host ('🎬 Video:    {0} | {1}x{2} | frames: {3}' -f $videoStream.codec_name, $videoStream.width, $videoStream.height, $videoFrames)
    }
    if ($audioStream) {
        $audioFrames = Get-ObjectPropertyValue -Object $audioStream -Name 'nb_frames' -Default 'unknown'
        Write-Host ('🔊 Audio:    {0} | {1} Hz | packets/frames: {2}' -f $audioStream.codec_name, $audioStream.sample_rate, $audioFrames)
    }

    if ((-not $SkipInputAnalysis) -or $AnalyzeOnly) {
        $inputStats = @(Get-TimestampStats -Ffprobe $Ffprobe -InputPath $resolvedInputPath)
        Write-TimestampStats -Title 'Input timestamp diagnosis:' -Stats $inputStats

        if ($AnalyzeOnly) {
            $issueInfo = Get-TimestampIssueInfo -Stats $inputStats
            switch ($issueInfo.Status) {
                'OK' { Write-Ok 'Diagnosis: no timestamp issues found by this analyzer.' }
                'WARN' { Write-Warn ('Diagnosis: timestamp warnings found. {0}' -f $issueInfo.Summary) }
                'PROBLEM' { Write-Bad ('Diagnosis: found timestamp/Avidemux-risk issues. {0}' -f $issueInfo.Summary) }
            }
            return
        }
    } else {
        Write-Warn 'Input timestamp diagnosis skipped for faster remux.'
    }

    $tempName = ([IO.Path]::GetFileNameWithoutExtension($resolvedOutputPath) + '.stage.mkv')
    $tempPath = Join-Path -Path $resolvedTempDirectory -ChildPath $tempName

    try {
        Invoke-NativeChecked -Exe $Ffmpeg -Label 'Stage 1/2: TS/container to MKV copy remux' -CommandArgs @(
            '-hide_banner',
            '-loglevel', 'error',
            '-stats',
            '-y',
            '-i', $resolvedInputPath,
            '-map', '0',
            '-c', 'copy',
            $tempPath
        )

        $finalArgs = @(
            '-hide_banner',
            '-loglevel', 'error',
            '-stats',
            '-y',
            '-i', $tempPath,
            '-map', '0',
            '-c', 'copy'
        )

        if (-not $SkipSettsRepair) {
            $settsExpression = "setts=ts='if(eq(N,0),TS,if(lt(TS,PREV_OUTDTS+DURATION),PREV_OUTDTS+DURATION,TS))'"
            $finalArgs += @('-bsf:v', $settsExpression)
        }

        $finalArgs += @(
            '-movflags', '+faststart',
            $resolvedOutputPath
        )

        Invoke-NativeChecked -Exe $Ffmpeg -Label 'Stage 2/2: MKV to MP4 copy remux with timestamp repair' -CommandArgs $finalArgs
    }
    finally {
        if ((-not $KeepTemp) -and (Test-Path -LiteralPath $tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }

    Write-Host ''
    Write-Host ('✅ Output: {0}' -f $resolvedOutputPath) -ForegroundColor Green

    $outputStats = @(Get-TimestampStats -Ffprobe $Ffprobe -InputPath $resolvedOutputPath)
    Write-TimestampStats -Title 'Output timestamp diagnosis:' -Stats $outputStats

    if (-not $NoVerify) {
        Invoke-NativeChecked -Exe $Ffmpeg -Label 'Verification: copy-mode remux read' -CommandArgs @(
            '-hide_banner',
            '-v', 'warning',
            '-i', $resolvedOutputPath,
            '-map', '0',
            '-c', 'copy',
            '-f', 'null',
            '-'
        )
    }

    if (Test-StatsCleanForMuxing -Stats $outputStats) {
        Write-Ok 'Result: output has no backwards or tiny duplicate PTS/DTS packets.'
    } else {
        Write-Warn 'Result: output was created, but timestamp warnings remain. Try without -SkipSettsRepair, or re-encode as a last resort.'
    }

    Remove-SourceTsAfterSuccess -InputPath $resolvedInputPath -OutputPath $resolvedOutputPath
}

function Invoke-FolderTimestampScan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ffprobe,

        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Folder,

        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$Files
    )

    Write-ToolHeader -Title 'TS Folder Timestamp Scan'
    Write-Host ('📁 Folder: {0}' -f $Folder.FullName)
    Write-Host ('🔎 Files:  {0}' -f $Files.Count)
    if ($MoveProblemFiles) {
        Write-Host ('📦 Problem files will move to: {0}' -f (Join-Path -Path $Folder.FullName -ChildPath $ProblemFolderName)) -ForegroundColor Magenta
    }

    $results = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($file in $Files) {
        $index++
        try {
            $stats = @(Get-TimestampStats -Ffprobe $Ffprobe -InputPath $file.FullName)
            $issueInfo = Get-TimestampIssueInfo -Stats $stats
            Write-StatusLine -Index $index -Total $Files.Count -FileName $file.Name -IssueInfo $issueInfo

            $movedTo = ''
            if ($MoveProblemFiles -and $issueInfo.IsProblem) {
                $movedTo = Move-ProblemTsFile -File $file -FolderRoot $Folder.FullName
            }

            $results.Add([pscustomobject]@{
                File = $file.Name
                Status = $issueInfo.Status
                Summary = $issueInfo.Summary
                MovedTo = $movedTo
            }) | Out-Null
        }
        catch {
            Write-Bad ('[{0}/{1}] {2} — SCAN FAILED — {3}' -f $index, $Files.Count, $file.Name, $_.Exception.Message)
            $results.Add([pscustomobject]@{
                File = $file.Name
                Status = 'ERROR'
                Summary = $_.Exception.Message
                MovedTo = ''
            }) | Out-Null
        }
    }

    $problemCount = @($results | Where-Object { $_.Status -eq 'PROBLEM' }).Count
    $warningCount = @($results | Where-Object { $_.Status -eq 'WARN' }).Count
    $okCount = @($results | Where-Object { $_.Status -eq 'OK' }).Count
    $errorCount = @($results | Where-Object { $_.Status -eq 'ERROR' }).Count

    Write-Host ''
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray
    Write-Host ('📊 Summary: ✅ OK {0} | ⚠️ WARN {1} | ❌ PROBLEM {2} | 🚫 ERROR {3}' -f $okCount, $warningCount, $problemCount, $errorCount)
    if ($MoveProblemFiles -and ($problemCount -gt 0)) {
        Write-Host ('📦 Moved {0} problem file(s) to {1}' -f $problemCount, (Join-Path -Path $Folder.FullName -ChildPath $ProblemFolderName)) -ForegroundColor Magenta
    }
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor DarkGray

    if ($errorCount -gt 0) {
        exit 1
    }
}

$ffmpeg = Resolve-RequiredCommand -Name 'ffmpeg'
$ffprobe = Resolve-RequiredCommand -Name 'ffprobe'
$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$targetItem = Get-Item -LiteralPath $resolvedPath

if ($targetItem.PSIsContainer) {
    if ($OutputPath) {
        throw '-OutputPath is only supported for single-file mode.'
    }

    $searchMode = if ($Recurse) { 'recursive' } else { 'top-level' }
    $tsFiles = @(Get-ChildItem -LiteralPath $resolvedPath -Filter '*.ts' -File -Recurse:$Recurse | Sort-Object FullName)
    Write-ToolHeader -Title 'TS Folder Batch'
    Write-Host ('📁 Folder: {0}' -f $resolvedPath)
    Write-Host ('🔎 Mode:   {0} .ts scan' -f $searchMode)
    Write-Host ('🎞️  Files:  {0}' -f $tsFiles.Count)

    if ($tsFiles.Count -eq 0) {
        Write-Warn 'No .ts files found.'
        Wait-ForUserIfRequested
        return
    }

    if ($AnalyzeOnly) {
        Invoke-FolderTimestampScan -Ffprobe $ffprobe -Folder $targetItem -Files $tsFiles
        Wait-ForUserIfRequested
        return
    }

    $failures = New-Object System.Collections.Generic.List[object]
    foreach ($file in $tsFiles) {
        try {
            Invoke-TsTimestampRemux -Ffmpeg $ffmpeg -Ffprobe $ffprobe -InputPath $file.FullName
        }
        catch {
            $failures.Add([pscustomobject]@{
                File = $file.FullName
                Error = $_.Exception.Message
            }) | Out-Null
            Write-Bad ('FAILED: {0}' -f $file.FullName)
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    Write-Host ''
    Write-Host ('📊 Batch complete. Files: {0} | Failures: {1}' -f $tsFiles.Count, $failures.Count)
    if ($failures.Count -gt 0) {
        $failures | Format-Table -AutoSize | Out-String | Write-Host
        Wait-ForUserIfRequested
        exit 1
    }

    Wait-ForUserIfRequested
    return
}

Invoke-TsTimestampRemux -Ffmpeg $ffmpeg -Ffprobe $ffprobe -InputPath $resolvedPath -RequestedOutputPath $OutputPath
Wait-ForUserIfRequested
