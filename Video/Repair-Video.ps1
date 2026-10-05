<#
.SYNOPSIS
    Diagnoses supported MP4 failures and verifies a conservative, separate repair.
.DESCRIPTION
    Interactive by default: analyzes first, prints the proposed action, then offers
    repair or report only. Current repair routes are malformed AAC sample headers
    and a strictly characterized displaced-mdat/duplicate-moov H.264 layout.
    Unknown corruption and timeline gaps are reported without speculative repair.
    Sources and existing outputs are never overwritten. A JSON report and logs
    are retained in a unique directory beside the requested output.
.PARAMETER Path
    Input MP4/MOV. If omitted, the interactive program asks for it.
.PARAMETER AnalyzeOnly
    Write diagnosis and logs without rendering a repair or prompting.
.PARAMETER Repair
    Automation override: execute the recognized repair without prompting.
.PARAMETER AllowRangeRemoval
    Automation opt-in for the displaced-data route, which removes a bounded
    damaged range from both audio and video after index realignment.
.PARAMETER MaxRemovedSeconds
    Maximum permitted planned removal. Default 30 seconds; checked before repair.
.PARAMETER NoUI
    Plain output and text choices for automation or redirected terminals.
    Progress heartbeats and per-stage timings remain in the output.
.NOTES
    Exit 0: no detected problems or verified repair; 1: execution/verification
    failure; 2: recognized repair proposed but not executed; 3: manual review.
    Decode/timestamp verification does not establish perceptual lip-sync.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [string]$OutputPath,
    [switch]$AnalyzeOnly,
    [switch]$Repair,
    [switch]$AllowRangeRemoval,
    [switch]$NoUI,
    [ValidateRange(0.1, 120.0)][double]$MaxRemovedSeconds = 30.0,
    [ValidateSet('h264_nvenc', 'libx264')][string]$Encoder = 'libx264'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\MediaTimeline.ps1')
. (Join-Path $PSScriptRoot 'lib\RepairUi.ps1')
$script:RepairPlainOutput = $NoUI.IsPresent -or [Console]::IsOutputRedirected
$script:RepairActivityNumber = 0
$script:RepairDuration = 0.0
$script:RepairTotalClock = [Diagnostics.Stopwatch]::StartNew()
Write-Host ''
Write-Host '  MP4 DIAGNOSE / REPAIR' -ForegroundColor Cyan
Write-Host '  Inspect  >  Choose repair  >  Verify result' -ForegroundColor DarkGray
Write-Host '  Progress is per stage; verification also reads the entire video.' -ForegroundColor DarkGray

function ConvertTo-RepairArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (2 * $slashes + 1)))
        } elseif ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)) }
        [void]$builder.Append($character)
        $slashes = 0
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-RepairProcess {
    param([string]$Exe, [string[]]$CommandArgs, [string]$Label)
    $activity = Start-RepairActivity (Get-RepairStageName $Label)
    $isFfmpeg = [IO.Path]::GetFileNameWithoutExtension($Exe) -ieq 'ffmpeg'
    $progressPath = Join-Path $script:ReportDirectory ($Label + '.progress.log')
    if ($isFfmpeg) {
        # A separate file keeps progress out of JSON/hash stdout and diagnostics.
        $CommandArgs = @('-nostdin', '-nostats', '-stats_period', '0.5', '-progress', $progressPath) + $CommandArgs
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Exe
    $info.Arguments = (($CommandArgs | ForEach-Object { ConvertTo-RepairArgument $_ }) -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = $null
    $finished = $false
    $progressUpdates = 0
    $latestMediaSeconds = $null
    try {
        $process = [Diagnostics.Process]::Start($info)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(250)) {
            if ($isFfmpeg) {
                $snapshot = Get-RepairProgressSnapshot -ProgressPath $progressPath -DurationSeconds $script:RepairDuration -ElapsedSeconds $activity.Clock.Elapsed.TotalSeconds
                Update-RepairActivity -Activity $activity -Detail $snapshot.Detail -Percent $snapshot.Percent -Eta $snapshot.Eta
                if ($null -ne $snapshot.MediaSeconds) { $latestMediaSeconds = $snapshot.MediaSeconds; $progressUpdates++ }
            } else {
                $detail = 'Working (this stage does not report a percentage)'
                if ($Label -eq 'render-packets') {
                    $detail = 'Backend is copying/patching segments or running its full decode check'
                    if ([IO.File]::Exists($stage)) {
                        $detail = 'Joined output created; backend is verifying full video/audio decode'
                    }
                }
                Update-RepairActivity $activity $detail
            }
        }
        $result = [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdoutTask.GetAwaiter().GetResult(); Stderr = $stderrTask.GetAwaiter().GetResult() }
        $finished = $true
    } finally {
        if ($null -ne $process) {
            if (-not $finished -and -not $process.HasExited) {
                # Stop only our process tree when the caller interrupts a run.
                if ($PSVersionTable.PSVersion.Major -ge 7) { $process.Kill($true) }
                else { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null }
                $process.WaitForExit()
            }
            $process.Dispose()
        }
        Stop-RepairActivity $activity ($finished -and $result.ExitCode -eq 0)
    }
    [IO.File]::WriteAllText((Join-Path $script:ReportDirectory ($Label + '.stdout.log')), $result.Stdout)
    [IO.File]::WriteAllText((Join-Path $script:ReportDirectory ($Label + '.stderr.log')), $result.Stderr)
    $script:Report.Steps += [pscustomobject]@{ Label = $Label; ExitCode = $result.ExitCode; Executable = $Exe; Arguments = $CommandArgs; ElapsedSeconds = [Math]::Round($activity.Clock.Elapsed.TotalSeconds, 3); LiveProgressUpdates = $progressUpdates; LastMediaSeconds = $latestMediaSeconds }
    return $result
}

function Get-RepairProbe {
    param([string]$InputFile, [string]$Label)
    $probe = Invoke-RepairProcess -Exe $script:Ffprobe -CommandArgs @('-v', 'warning', '-show_streams', '-show_format', '-of', 'json', $InputFile) -Label $Label
    if ($probe.ExitCode -ne 0) {
        if ($probe.Stderr -match 'moov atom not found') {
            throw "MP4 index (moov) is missing. Recover Incomplete MP4 is a separate specialized tool for supported Microsoft recordings; it is not automatically safe for every missing-index file. See $Label.stderr.log."
        }
        throw "Metadata probe failed; see $Label.stderr.log. No supported repair can be inferred. $($probe.Stderr.Trim())"
    }
    return [pscustomobject]@{ Data = ($probe.Stdout | ConvertFrom-Json); Diagnostics = $probe.Stderr }
}

function Test-RepairDecode {
    param([string]$InputFile, [string]$Label, [switch]$AudioOnly)
    $decodeArgs = @('-v', 'error', '-i', $InputFile)
    if (-not $AudioOnly) { $decodeArgs += @('-map', '0:v:0') }
    $decodeArgs += @('-map', '0:a:0?', '-f', 'null', '-')
    $result = Invoke-RepairProcess -Exe $script:Ffmpeg -CommandArgs $decodeArgs -Label $Label
    if ($result.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($result.Stderr)) {
        throw "Full decode did not pass: $Label.stderr.log (exit $($result.ExitCode))."
    }
}

if ($AnalyzeOnly -and $Repair) { throw 'Choose AnalyzeOnly or Repair, not both.' }
if (-not $Path) {
    if ($Repair -or $AnalyzeOnly) { throw 'Path is required in automation mode.' }
    $Path = (Read-Host 'Video path').Trim().Trim('"')
}
$source = (Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Input must be a file.' }
if (-not $OutputPath) {
    $defaultBase = Join-Path ([IO.Path]::GetDirectoryName($source)) ([IO.Path]::GetFileNameWithoutExtension($source) + '_repaired')
    $OutputPath = $defaultBase + '.mp4'
    $suffix = 2
    while (Test-Path -LiteralPath $OutputPath) {
        $OutputPath = '{0}_{1}.mp4' -f $defaultBase, $suffix
        $suffix++
    }
}
$output = [IO.Path]::GetFullPath($OutputPath)
if ($output -eq $source) { throw 'Output must not overwrite the source.' }
if ([IO.Path]::GetExtension($output) -ine '.mp4') { throw 'Output must have the .mp4 extension.' }
if (Test-Path -LiteralPath $output) { throw "Output already exists; choose another path: $output" }
$outputDirectory = [IO.Path]::GetDirectoryName($output)
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { throw 'Output directory must already exist.' }
$script:Ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$script:Ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$script:ReportDirectory = Join-Path $outputDirectory ('repair-report-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:ReportDirectory)
$script:Report = [ordered]@{
    Input = $source; Output = $output; Status = 'Analyzing'; Route = 'None'; Reason = ''
    InputSha256 = (Get-RepairFileHash $source)
    SourceUnchanged = $null; OutputSha256 = $null; Alignment = $null
    PlannedRemovedSeconds = 0.0; InputTimeline = $null; OutputTimeline = $null
    Steps = @(); Limitations = 'Automated structural, decode and timestamp checks do not establish lip-sync or visual quality.'
}
$resultCode = 3
$stage = Join-Path $script:ReportDirectory 'candidate.mp4'
try {
    Write-Host "Analyzing: $source" -ForegroundColor Cyan
    $probe = Get-RepairProbe -InputFile $source -Label 'source-probe'
    $script:RepairDuration = [double]::Parse([string]$probe.Data.format.duration, [Globalization.CultureInfo]::InvariantCulture)
    Write-Host ('  File: {0}' -f [IO.Path]::GetFileName($source)) -ForegroundColor White
    Write-Host ('  Duration: {0} | Size: {1:N2} GB' -f (Format-RepairElapsed $script:RepairDuration), ((Get-Item -LiteralPath $source).Length / 1GB)) -ForegroundColor Gray
    $streams = @($probe.Data.streams)
    $videos = @($streams | Where-Object { $_.codec_type -eq 'video' })
    $audios = @($streams | Where-Object { $_.codec_type -eq 'audio' })
    if ($videos.Count -ne 1 -or $audios.Count -gt 1 -or $streams.Count -ne ($videos.Count + $audios.Count) -or
        $probe.Data.format.format_name -notmatch '(^|,)(mov|mp4)(,|$)') { throw 'Current router requires MP4/MOV with one video and at most one audio stream, without additional streams.' }
    $scan = Invoke-RepairProcess -Exe $script:Ffmpeg -CommandArgs @('-v', 'warning', '-i', $source, '-map', '0', '-c', 'copy', '-f', 'null', '-') -Label 'source-packets'
    $diagnostics = $probe.Diagnostics + $scan.Stderr
    $missingAacConfig = $audios.Count -eq 1 -and $audios[0].codec_name -eq 'aac' -and
        (-not $audios[0].PSObject.Properties['extradata_size'] -or [int]$audios[0].extradata_size -eq 0)
    $alignment = $null
    if ($scan.ExitCode -eq 0 -and $diagnostics -match "overread end of atom 'stsd'" -and $missingAacConfig -and
        $diagnostics -notmatch 'Invalid NAL|missing picture|corrupt|Error submitting|Invalid data') {
        $script:Report.Route = 'RebuildAacHeader'
        $script:Report.Reason = 'Malformed stsd and missing AAC configuration. Copy video; decode and re-encode AAC to rebuild its configuration.'
    } elseif ($videos[0].codec_name -eq 'h264' -and $videos[0].is_avc -eq 'true' -and
        $videos[0].nal_length_size -eq '4' -and [int]$videos[0].has_b_frames -eq 0 -and $diagnostics -match 'Invalid NAL|missing picture') {
        if (-not ('EncodeRepair.Mp4Alignment' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'lib\Mp4Alignment.cs') }
        $packets = Invoke-RepairProcess -Exe $script:Ffprobe -CommandArgs @('-v', 'error', '-select_streams', 'v:0', '-show_entries', 'packet=pts_time,pos,size', '-of', 'compact=p=0:nk=0', $source) -Label 'source-video-index'
        if ($packets.ExitCode -ne 0) { throw 'Cannot read complete video packet index.' }
        $alignment = Invoke-RepairBackground -Title 'Checking data alignment across the file' -Code 'param($p,$index) [EncodeRepair.Mp4Alignment]::Analyze($p,$index)' -Arguments @($source, $packets.Stdout)
        $script:Report.Alignment = $alignment
        if ($alignment.Status -eq 'RecoverableShift') {
            $script:Report.Route = 'RealignAndRemoveDamage'
            $script:Report.Reason = $alignment.Reason
        } else { $script:Report.Reason = $alignment.Reason }
    } elseif ($scan.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($diagnostics)) {
        $script:Report.InputTimeline = Get-RepairTimeline $source
        Write-MediaTimelineReport $script:Report.InputTimeline
        if ($script:Report.InputTimeline.NeedsReview) {
            $script:Report.Reason = 'Timeline anomalies require review; automatic retiming could alter synchronization.'
        } else {
            Test-RepairDecode -InputFile $source -Label 'source-decode'
            $script:Report.Status = 'NoDetectedProblem'
            $script:Report.Reason = 'Packet, full decode and timing checks passed; no automatic repair proposed.'
            $resultCode = 0
        }
    } else { $script:Report.Reason = 'Unrecognized diagnostics. No speculative repair or automatic broad range removal.' }

    Write-Host ("Route: {0}`n{1}" -f $script:Report.Route, $script:Report.Reason) -ForegroundColor Yellow
    if ($script:Report.Route -eq 'RealignAndRemoveDamage') {
        Write-Host ("Proven byte displacement: {0}; bad video packets {1} -> {2}; affected PTS {3:F3}s to {4:F3}s." -f
            $alignment.Shift, $alignment.OriginalBadPackets, $alignment.RemainingBadPackets, $alignment.FirstBadPts, $alignment.LastBadPts)
        Write-Host ("Repair removes a bounded interval from BOTH streams; planned removal must be <= {0}s." -f $MaxRemovedSeconds)
    }
    if ($script:Report.Route -eq 'None') {
        if ($resultCode -ne 0) { $script:Report.Status = 'ManualReview' }
    } else {
        $script:Report.Status = 'RepairProposed'; $resultCode = 2
        $execute = $Repair.IsPresent
        $permitRemoval = $AllowRangeRemoval.IsPresent
        if (-not $AnalyzeOnly -and -not $Repair) {
            $choiceDetail = if ($script:Report.Route -eq 'RebuildAacHeader') { 'Rebuild AAC audio; copy video unchanged.' } else { "Remove damaged A/V ranges (maximum $MaxRemovedSeconds s)." }
            $execute = Show-RepairChoice -Route $choiceDetail -FileName ([IO.Path]::GetFileName($source))
            $permitRemoval = $execute
        }
        if ($execute) {
            if ($script:Report.Route -eq 'RealignAndRemoveDamage' -and -not $permitRemoval) {
                throw 'Automation requires -AllowRangeRemoval for this route. No video was written.'
            }
            if ((Get-RepairFileHash $source) -ne $script:Report.InputSha256) { throw 'Source changed during diagnosis.' }
            if ($script:Report.Route -eq 'RebuildAacHeader') {
                Test-RepairDecode -InputFile $source -Label 'source-audio-decode' -AudioOnly
                $render = Invoke-RepairProcess -Exe $script:Ffmpeg -CommandArgs @('-v', 'warning', '-n', '-i', $source,
                    '-map', '0:v:0', '-map', '0:a:0', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '320k', '-movflags', '+faststart', $stage) -Label 'render-aac'
                if ($render.ExitCode -ne 0) { throw 'AAC header rebuild failed.' }
            } else {
                $realigned = Join-Path $script:ReportDirectory 'realigned-intermediate.mp4'
                Invoke-RepairBackground -Title 'Writing realigned intermediate (copying disk data)' -Code 'param($src,$dst,$plan) [EncodeRepair.Mp4Alignment]::Restore($src,$dst,$plan)' -Arguments @($source, $realigned, $alignment)
                $shellExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                $baseArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
                    (Join-Path $PSScriptRoot 'Repair-DamagedVideo.ps1'), '-Path', $realigned)
                $detection = Invoke-RepairProcess -Exe $shellExe -CommandArgs ($baseArgs + @('-DetectOnly')) -Label 'realigned-detection'
                if ($detection.ExitCode -ne 2 -or $detection.Stdout -notmatch 'Planned removal: (\d{2}:\d{2}:\d{2}\.\d+)') { throw 'Realigned repair plan was not recognized.' }
                $removed = [TimeSpan]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture).TotalSeconds
                $script:Report.PlannedRemovedSeconds = $removed
                if ($removed -le 0 -or $removed -gt $MaxRemovedSeconds) { throw "Planned removal $removed exceeds the permitted bound. No final repair rendered." }
                $render = Invoke-RepairProcess -Exe $shellExe -CommandArgs ($baseArgs + @('-OutputPath', $stage, '-Encoder', $Encoder, '-KeepTemp')) -Label 'render-packets'
                if ($render.ExitCode -notin @(0,3)) { throw 'Packet repair failed validation; see render-packets logs.' }
            }
            $outputProbe = Get-RepairProbe -InputFile $stage -Label 'output-probe'
            if (-not [string]::IsNullOrWhiteSpace($outputProbe.Diagnostics)) { throw 'Output container still produces probe warnings.' }
            $outputStreams = @($outputProbe.Data.streams)
            if ($outputStreams.Count -ne $streams.Count) { throw 'Output stream count changed unexpectedly.' }
            $outVideo = @($outputStreams | Where-Object { $_.codec_type -eq 'video' })[0]
            if ($outVideo.codec_name -ne $videos[0].codec_name -or $outVideo.width -ne $videos[0].width -or $outVideo.height -ne $videos[0].height) { throw 'Output video characteristics changed unexpectedly.' }
            $inputDuration = [double]::Parse([string]$probe.Data.format.duration, [Globalization.CultureInfo]::InvariantCulture)
            $outputDuration = [double]::Parse([string]$outputProbe.Data.format.duration, [Globalization.CultureInfo]::InvariantCulture)
            $script:RepairDuration = $outputDuration
            if ([Math]::Abs($inputDuration - $script:Report.PlannedRemovedSeconds - $outputDuration) -gt 0.25) { throw 'Output duration is inconsistent with the approved repair plan.' }
            if ($script:Report.Route -eq 'RebuildAacHeader') {
                $outAudio = @($outputStreams | Where-Object { $_.codec_type -eq 'audio' })[0]
                if (-not $outAudio.PSObject.Properties['extradata_size'] -or [int]$outAudio.extradata_size -le 0 -or $outAudio.profile -eq '-1') { throw 'Output AAC configuration is still incomplete.' }
                $inputHash = Invoke-RepairProcess -Exe $script:Ffmpeg -CommandArgs @('-v','error','-i',$source,'-map','0:v:0','-c','copy','-f','streamhash','-hash','sha256','-') -Label 'source-video-hash'
                $outputHash = Invoke-RepairProcess -Exe $script:Ffmpeg -CommandArgs @('-v','error','-i',$stage,'-map','0:v:0','-c','copy','-f','streamhash','-hash','sha256','-') -Label 'output-video-hash'
                if ($inputHash.ExitCode -ne 0 -or $outputHash.ExitCode -ne 0 -or $inputHash.Stdout.Trim() -ne $outputHash.Stdout.Trim()) { throw 'Copied video payload hash verification failed.' }
            }
            Test-RepairDecode -InputFile $stage -Label 'output-decode'
            $script:Report.OutputTimeline = Get-RepairTimeline $stage
            Write-MediaTimelineReport $script:Report.OutputTimeline
            if ($script:Report.OutputTimeline.NeedsReview) { throw 'Candidate retained for diagnosis: timeline verification did not pass.' }
            if ((Get-RepairFileHash $source) -ne $script:Report.InputSha256) { throw 'Source changed; output will not be published.' }
            # File.Move without overwrite is the final publication gate.
            [IO.File]::Move($stage, $output)
            $script:Report.OutputSha256 = Get-RepairFileHash $output
            $script:Report.Status = 'VerifiedRepair'; $resultCode = 0
            Write-Host "Verified repair: $output" -ForegroundColor Green
        }
    }
} catch {
    $script:Report.Status = 'Failed'; $script:Report.Reason = $_.Exception.Message; $resultCode = 1
    Write-Warning $_.Exception.Message
} finally {
    $script:Report.SourceUnchanged = (Get-RepairFileHash $source) -eq $script:Report.InputSha256
    if (-not $script:Report.SourceUnchanged) { $script:Report.Status = 'SourceChanged'; $resultCode = 1 }
    $script:Report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $script:ReportDirectory 'report.json') -Encoding UTF8
    Write-Host "Status: $($script:Report.Status) | Report: $script:ReportDirectory"
    Write-Host ('Total elapsed: ' + (Format-RepairElapsed $script:RepairTotalClock.Elapsed.TotalSeconds)) -ForegroundColor Cyan
}
exit $resultCode
