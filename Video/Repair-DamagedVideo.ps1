<#
.SYNOPSIS
    Detects damaged H.264-in-MP4 packet ranges and optionally repairs the file by re-encoding only affected patch windows.

.DESCRIPTION
    This is a saved prototype from the 3.mp4 repair workflow. It focuses on MP4 files that use AVC/H.264 in AVCC format
    with 4-byte NAL lengths.

    Detection:
    - Uses ffprobe packet metadata for video packets.
    - Reads each packet payload from the MP4 file.
    - Validates AVCC NAL unit length prefixes.
    - Converts bad packets into conservative visual-damage ranges by padding start time, extending to the next keyframe,
      and merging nearby clusters.

    Repair:
    - Copies clean regions outside damaged patch windows.
    - Re-encodes only kept regions inside damaged patch windows.
    - Cuts optional audio with the same timeline and re-encodes AAC in patch regions.
    - Concatenates all pieces back into a repaired MP4.
    - Refuses existing outputs and verifies the final stream structure and a full decode.

    This is intentionally conservative. It is meant to preserve the successful prototype and provide a base for future tools,
    not to be treated as a universal final repair engine for every codec/container.

.PARAMETER Path
    Input MP4 file path.

.PARAMETER OutputPath
    Repaired output path. Defaults to "<input>_smart_repaired.mp4".

.PARAMETER DetectOnly
    Only detect and print damaged ranges.

.PARAMETER DryRun
    Detect and print planned repair segments without writing output.

.PARAMETER StartPadding
    Seconds to move each detected range start earlier. Default: 0.75.

.PARAMETER MergeGap
    Seconds between ranges that should be merged. Default: 1.0.

.PARAMETER Encoder
    Video encoder for patch regions. Default: h264_nvenc.

.PARAMETER Cq
    Patch quality value: NVENC CQ or libx264 CRF. Default: 20.

.PARAMETER Preset
    Encoder preset. Default: fast.

.PARAMETER KeepTemp
    Keep temporary segment files for inspection.

.EXAMPLE
    pwsh -File .\Video\Repair-DamagedVideo.ps1 -Path "D:\Users\joty79\Desktop\3.mp4" -DetectOnly

.EXAMPLE
    pwsh -File .\Video\Repair-DamagedVideo.ps1 -Path "D:\Users\joty79\Desktop\3.mp4" -OutputPath "D:\Users\joty79\Desktop\3_fixed.mp4"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$Path,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$DetectOnly,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0.0, 30.0)]
    [double]$StartPadding = 0.75,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0.0, 60.0)]
    [double]$MergeGap = 1.0,

    [Parameter(Mandatory = $false)]
    [ValidateSet('h264_nvenc', 'libx264')]
    [string]$Encoder = "h264_nvenc",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 51)]
    [int]$Cq = 20,

    [Parameter(Mandatory = $false)]
    [string]$Preset = "fast",

    [Parameter(Mandatory = $false)]
    [switch]$KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:StepRows = [System.Collections.Generic.List[object]]::new()
$script:Ffmpeg = $null
$script:Ffprobe = $null

function Resolve-RequiredCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        throw "Required command '$Name' was not found on PATH."
    }
    return $command.Source
}

function ConvertTo-NativeCommandLineArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
        }
        else {
            if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)) }
            [void]$builder.Append($character)
        }
        $backslashes = 0
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$CommandArgs
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Exe
    $startInfo.Arguments = (($CommandArgs | ForEach-Object {
        ConvertTo-NativeCommandLineArgument -Value $_
    }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout.GetAwaiter().GetResult()
        Stderr = $stderr.GetAwaiter().GetResult()
    }
}

function Format-RepairTime {
    param([double]$Seconds)

    # Use a floating-point zero so PowerShell binds the Double overload. With
    # integer 0, values below 0.5 seconds were rounded to zero before Max().
    $safeSeconds = [Math]::Max(0.0, $Seconds)
    $timeSpan = [TimeSpan]::FromSeconds($safeSeconds)
    $hours = [int][Math]::Floor($timeSpan.TotalHours)
    return "{0:00}:{1:00}:{2:00}.{3:000}" -f `
        $hours, $timeSpan.Minutes, $timeSpan.Seconds, $timeSpan.Milliseconds
}

function Convert-InvariantDouble {
    param([object]$Value)

    if ($null -eq $Value) { return 0.0 }
    return [double]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Convert-InvariantString {
    param([double]$Value)

    return $Value.ToString("0.###", [Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-RepairCommand {
    param(
        [string]$Step,
        [string[]]$CommandArgs,
        [string]$OutputFile
    )

    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $nativeResult = Invoke-NativeCapture -Exe $script:Ffmpeg -CommandArgs $CommandArgs
    $lines = @(($nativeResult.Stdout + $nativeResult.Stderr) -split "`r?`n" | Where-Object { $_ })
    $exitCode = $nativeResult.ExitCode
    $stopwatch.Stop()

    $script:StepRows.Add([pscustomobject]@{
        Step     = $Step
        ExitCode = $exitCode
        Seconds  = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        Warnings = $lines.Count
        Bytes    = if ($OutputFile -and (Test-Path -LiteralPath $OutputFile)) { (Get-Item -LiteralPath $OutputFile).Length } else { 0 }
    })

    if ($exitCode -ne 0) {
        throw "$Step failed with ffmpeg exit code $exitCode.`n$($lines -join [Environment]::NewLine)"
    }
    if ($OutputFile -and (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf) -or
        (Get-Item -LiteralPath $OutputFile).Length -le 0)) {
        throw "$Step returned success but did not create a non-empty output file."
    }
}

function Test-RepairedOutput {
    param([Parameter(Mandatory = $true)][string]$OutputFile)

    $probeResult = Invoke-NativeCapture -Exe $script:Ffprobe -CommandArgs @(
        '-hide_banner', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', $OutputFile
    )
    if ($probeResult.ExitCode -ne 0) {
        throw "Final output probe failed. $($probeResult.Stderr)"
    }
    try {
        $probe = $probeResult.Stdout | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'Final output probe returned invalid JSON.'
    }
    if (@($probe.streams | Where-Object { $_.codec_type -eq 'video' }).Count -ne 1) {
        throw 'Final output validation did not find exactly one video stream.'
    }

    $decodeResult = Invoke-NativeCapture -Exe $script:Ffmpeg -CommandArgs @(
        '-hide_banner', '-v', 'error', '-i', $OutputFile,
        '-map', '0:v:0', '-map', '0:a:0?', '-f', 'null', '-'
    )
    if ($decodeResult.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($decodeResult.Stderr)) {
        throw "Final output full-decode verification failed with exit code $($decodeResult.ExitCode). $($decodeResult.Stderr)"
    }
}

function Get-VideoMetadata {
    param([string]$ResolvedPath)

    $probeResult = Invoke-NativeCapture -Exe $script:Ffprobe -CommandArgs @(
        '-hide_banner', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=codec_name,codec_tag_string,is_avc,nal_length_size,profile,width,height,pix_fmt,level,avg_frame_rate,r_frame_rate,time_base,nb_frames,duration',
        '-show_entries', 'format=format_name,duration,size', '-of', 'json', $ResolvedPath
    )
    if ($probeResult.ExitCode -ne 0) {
        throw "ffprobe metadata read failed. $($probeResult.Stderr)"
    }

    $data = $probeResult.Stdout | ConvertFrom-Json
    if (-not $data.streams -or $data.streams.Count -lt 1) {
        throw "No video stream found."
    }

    return [pscustomobject]@{
        Stream        = $data.streams[0]
        Format        = $data.format
        Duration      = Convert-InvariantDouble $data.format.duration
        DurationLabel = Format-RepairTime (Convert-InvariantDouble $data.format.duration)
    }
}

function Get-DamagedRanges {
    param(
        [string]$ResolvedPath,
        [double]$PaddingSeconds,
        [double]$ClusterMergeGap
    )

    Write-Host "Scanning video packet payloads..." -ForegroundColor Cyan
    $probeResult = Invoke-NativeCapture -Exe $script:Ffprobe -CommandArgs @(
        '-hide_banner', '-v', 'error', '-select_streams', 'v:0', '-show_packets',
        '-show_entries', 'packet=pts_time,duration_time,size,pos,flags', '-of', 'json', $ResolvedPath
    )
    if ($probeResult.ExitCode -ne 0) {
        throw "ffprobe packet read failed. $($probeResult.Stderr)"
    }

    $packets = @((($probeResult.Stdout | ConvertFrom-Json).packets))
    if ($packets.Count -eq 0) {
        throw "No video packets found."
    }

    $fileStream = [System.IO.File]::Open($ResolvedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $badPackets = [System.Collections.Generic.List[object]]::new()
        $keyframes = [System.Collections.Generic.List[object]]::new()
        $buffer = New-Object byte[] 1048576

        for ($index = 0; $index -lt $packets.Count; $index++) {
            $packet = $packets[$index]
            $packetPts = Convert-InvariantDouble $packet.pts_time
            $packetDuration = Convert-InvariantDouble $packet.duration_time
            $packetSize = [int]($packet.size)
            $packetPos = [int64]($packet.pos)

            if ([string]($packet.flags) -match "K") {
                $keyframes.Add([pscustomobject]@{
                    Index = $index
                    Pts   = $packetPts
                })
            }

            if ($packetSize -le 0) { continue }
            if ($buffer.Length -lt $packetSize) {
                $buffer = New-Object byte[] $packetSize
            }

            $fileStream.Seek($packetPos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $read = 0
            while ($read -lt $packetSize) {
                $bytesRead = $fileStream.Read($buffer, $read, $packetSize - $read)
                if ($bytesRead -le 0) { break }
                $read += $bytesRead
            }

            $isBad = $read -ne $packetSize
            $offset = 0

            while (-not $isBad -and $offset -lt $packetSize) {
                $remaining = $packetSize - $offset
                if ($remaining -lt 4) {
                    $isBad = $true
                    break
                }

                $nalSize = ([uint32]$buffer[$offset] -shl 24) -bor
                    ([uint32]$buffer[$offset + 1] -shl 16) -bor
                    ([uint32]$buffer[$offset + 2] -shl 8) -bor
                    [uint32]$buffer[$offset + 3]

                $payloadRemaining = $remaining - 4
                if ($nalSize -eq 0 -or $nalSize -gt $payloadRemaining) {
                    $isBad = $true
                    break
                }

                $offset += 4 + [int]$nalSize
            }

            if ($isBad) {
                Write-Verbose ("Bad packet metadata: pts_time={0}, parsed_pts={1}, pos={2}, size={3}" -f `
                    $packet.pts_time, $packetPts, $packetPos, $packetSize)
                $badPackets.Add([pscustomobject]@{
                    Index = $index
                    Pts   = $packetPts
                    End   = $packetPts + $packetDuration
                    Size  = $packetSize
                    Pos   = $packetPos
                })
            }
        }
    }
    finally {
        $fileStream.Dispose()
    }

    if ($badPackets.Count -eq 0) {
        return [pscustomobject]@{
            BadPackets = $badPackets
            Keyframes  = $keyframes
            Ranges     = @()
        }
    }

    if ($keyframes.Count -eq 0) {
        throw "No keyframes found; cannot build conservative visual ranges."
    }

    $intervals = foreach ($badPacket in $badPackets) {
        $nextKeyframe = $keyframes | Where-Object { $_.Pts -gt ($badPacket.Pts + 0.0001) } | Select-Object -First 1
        $end = if ($nextKeyframe) { [double]($nextKeyframe.Pts) } else { [double]($badPacket.End) }

        [pscustomobject]@{
            Start = [Math]::Max(0.0, [double]($badPacket.Pts) - $PaddingSeconds)
            End   = $end
        }
    }

    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($interval in ($intervals | Sort-Object Start)) {
        if ($merged.Count -eq 0) {
            $merged.Add([pscustomobject]@{ Start = [double]($interval.Start); End = [double]($interval.End) })
            continue
        }

        $last = $merged[$merged.Count - 1]
        if ($interval.Start -le ($last.End + $ClusterMergeGap)) {
            if ($interval.End -gt $last.End) {
                $last.End = [double]($interval.End)
            }
        }
        else {
            $merged.Add([pscustomobject]@{ Start = [double]($interval.Start); End = [double]($interval.End) })
        }
    }

    return [pscustomobject]@{
        BadPackets = $badPackets
        Keyframes  = $keyframes
        Ranges     = @($merged)
    }
}

function Get-PreviousKeyframe {
    param(
        [object[]]$Keyframes,
        [double]$Time
    )

    $previous = $Keyframes | Where-Object { $_.Pts -le $Time } | Select-Object -Last 1
    if ($previous) { return [double]($previous.Pts) }
    return 0.0
}

function Get-NextKeyframe {
    param(
        [object[]]$Keyframes,
        [double]$Time,
        [double]$Duration
    )

    $next = $Keyframes | Where-Object { $_.Pts -ge $Time } | Select-Object -First 1
    if ($next) { return [double]($next.Pts) }
    return $Duration
}

function Get-PatchGroups {
    param(
        [object[]]$Ranges,
        [object[]]$Keyframes,
        [double]$Duration
    )

    $rawGroups = foreach ($range in $Ranges) {
        [pscustomobject]@{
            PatchStart = Get-PreviousKeyframe -Keyframes $Keyframes -Time $range.Start
            PatchEnd   = Get-NextKeyframe -Keyframes $Keyframes -Time $range.End -Duration $Duration
            Ranges     = @($range)
        }
    }

    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($group in ($rawGroups | Sort-Object PatchStart)) {
        if ($groups.Count -eq 0) {
            $groups.Add($group)
            continue
        }

        $last = $groups[$groups.Count - 1]
        if ($group.PatchStart -le $last.PatchEnd) {
            if ($group.PatchEnd -gt $last.PatchEnd) {
                $last.PatchEnd = [double]($group.PatchEnd)
            }
            $last.Ranges = @($last.Ranges + $group.Ranges)
        }
        else {
            $groups.Add($group)
        }
    }

    return @($groups)
}

function Add-CopySegment {
    param(
        [string]$ResolvedPath,
        [string]$TempRoot,
        [System.Collections.Generic.List[string]]$Segments,
        [int]$Index,
        [double]$Start,
        [double]$End
    )

    if (($End - $Start) -lt 0.04) { return $Index }

    $segmentPath = Join-Path $TempRoot ("{0:000}_copy.mp4" -f $Index)
    $commandArgs = @(
        "-hide_banner", "-y", "-v", "warning",
        "-ss", (Convert-InvariantString $Start),
        "-t", (Convert-InvariantString ($End - $Start)),
        "-i", $ResolvedPath,
        "-map", "0:v:0", "-map", "0:a:0?",
        "-c", "copy",
        "-avoid_negative_ts", "make_zero",
        "-movflags", "+faststart",
        $segmentPath
    )

    Invoke-RepairCommand -Step ("copy {0}" -f $Index) -CommandArgs $commandArgs -OutputFile $segmentPath
    $Segments.Add($segmentPath)
    return ($Index + 1)
}

function Add-ReencodedSegment {
    param(
        [string]$ResolvedPath,
        [string]$TempRoot,
        [System.Collections.Generic.List[string]]$Segments,
        [int]$Index,
        [double]$Start,
        [double]$End,
        [string]$VideoEncoder,
        [string]$EncoderPreset,
        [int]$Quality
    )

    if (($End - $Start) -lt 0.04) { return $Index }

    $segmentPath = Join-Path $TempRoot ("{0:000}_patch.mp4" -f $Index)
    $commandArgs = @(
        "-hide_banner", "-y", "-v", "warning",
        "-ss", (Convert-InvariantString $Start),
        "-t", (Convert-InvariantString ($End - $Start)),
        "-i", $ResolvedPath,
        "-map", "0:v:0", "-map", "0:a:0?",
        "-c:v", $VideoEncoder,
        "-preset", $EncoderPreset
    )

    if ($VideoEncoder -eq 'h264_nvenc') {
        $commandArgs += @('-cq', ([string]$Quality))
    }
    else {
        $commandArgs += @('-crf', ([string]$Quality))
    }

    $commandArgs += @(
        "-pix_fmt", "yuv420p",
        "-fps_mode", "vfr",
        "-c:a", "aac",
        "-b:a", "160k",
        "-ar", "48000",
        "-ac", "2",
        "-movflags", "+faststart",
        $segmentPath
    )

    Invoke-RepairCommand -Step ("patch {0}" -f $Index) -CommandArgs $commandArgs -OutputFile $segmentPath
    $Segments.Add($segmentPath)
    return ($Index + 1)
}

$script:Ffmpeg = Resolve-RequiredCommand -Name 'ffmpeg'
$script:Ffprobe = Resolve-RequiredCommand -Name 'ffprobe'
$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
    throw "Input path is not a file: $resolvedPath"
}
if (-not $OutputPath) {
    $inputItem = Get-Item -LiteralPath $resolvedPath
    $OutputPath = Join-Path $inputItem.DirectoryName ("{0}_smart_repaired{1}" -f $inputItem.BaseName, $inputItem.Extension)
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not ($DetectOnly -or $DryRun)) {
    if ([string]::Equals($outputFullPath, $resolvedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OutputPath must not overwrite the input file.'
    }
    if (-not [string]::Equals([IO.Path]::GetExtension($outputFullPath), '.mp4', [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputPath must use the .mp4 extension: $outputFullPath"
    }
    if (Test-Path -LiteralPath $outputFullPath) {
        throw "Output already exists; nothing was overwritten: $outputFullPath"
    }
    $outputDirectory = [IO.Path]::GetDirectoryName($outputFullPath)
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        [void][IO.Directory]::CreateDirectory($outputDirectory)
    }
}

$metadata = Get-VideoMetadata -ResolvedPath $resolvedPath
Write-Host "Input: $resolvedPath" -ForegroundColor Cyan
Write-Host ("Duration: {0} | Codec: {1} | {2}x{3}" -f $metadata.DurationLabel, $metadata.Stream.codec_name, $metadata.Stream.width, $metadata.Stream.height) -ForegroundColor Gray

$isAvc = if ($metadata.Stream.PSObject.Properties['is_avc']) { [string]($metadata.Stream.is_avc) } else { '' }
$nalLengthSize = if ($metadata.Stream.PSObject.Properties['nal_length_size']) { [string]($metadata.Stream.nal_length_size) } else { '' }
if ($metadata.Stream.codec_name -ne 'h264' -or $isAvc -ne 'true' -or
    $nalLengthSize -ne '4' -or [string]($metadata.Format.format_name) -notmatch '(^|,)mp4(,|$)|(^|,)mov(,|$)') {
    throw ('This prototype only supports MP4/MOV H.264 AVCC with 4-byte NAL lengths. ' +
        "Detected format=$($metadata.Format.format_name), codec=$($metadata.Stream.codec_name), " +
        "is_avc=$isAvc, nal_length_size=$nalLengthSize.")
}

$detection = Get-DamagedRanges -ResolvedPath $resolvedPath -PaddingSeconds $StartPadding -ClusterMergeGap $MergeGap

Write-Host "------------------------------------------------------------------"
Write-Host ("Bad packets: {0}" -f $detection.BadPackets.Count) -ForegroundColor Gray
if ($detection.BadPackets.Count -gt 0) {
    $firstBadPacket = $detection.BadPackets | Sort-Object Pts | Select-Object -First 1
    $lastBadPacket = $detection.BadPackets | Sort-Object Pts | Select-Object -Last 1
    Write-Host ("Bad packet PTS span: {0} - {1} | file positions: {2} - {3}" -f `
        (Format-RepairTime $firstBadPacket.Pts), `
        (Format-RepairTime $lastBadPacket.Pts), `
        $firstBadPacket.Pos, `
        $lastBadPacket.Pos) -ForegroundColor Gray
}

if ($detection.Ranges.Count -eq 0) {
    Write-Host "No damaged H.264 packet ranges detected." -ForegroundColor Green
    return
}

Write-Host "Detected visual-risk ranges:" -ForegroundColor Yellow
foreach ($range in $detection.Ranges) {
    Write-Host ("  {0} - {1} ({2:n3}s)" -f (Format-RepairTime $range.Start), (Format-RepairTime $range.End), ($range.End - $range.Start)) -ForegroundColor Yellow
}

$patchGroups = @(Get-PatchGroups -Ranges $detection.Ranges -Keyframes $detection.Keyframes -Duration $metadata.Duration)
Write-Host "Patch windows:" -ForegroundColor Cyan
foreach ($group in $patchGroups) {
    Write-Host ("  {0} - {1}" -f (Format-RepairTime $group.PatchStart), (Format-RepairTime $group.PatchEnd)) -ForegroundColor Cyan
}

if ($DetectOnly -or $DryRun) {
    if ($DryRun) {
        Write-Host "Dry run complete. No files were written." -ForegroundColor Green
    }
    exit 2
}

$tempRoot = Join-Path $env:TEMP ("repair_damaged_video_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$keepOutput = $false

try {
    $segments = [System.Collections.Generic.List[string]]::new()
    $segmentIndex = 0
    $cursor = 0.0

    foreach ($group in $patchGroups) {
        $segmentIndex = Add-CopySegment -ResolvedPath $resolvedPath -TempRoot $tempRoot -Segments $segments -Index $segmentIndex -Start $cursor -End $group.PatchStart

        $patchCursor = [double]($group.PatchStart)
        foreach ($range in ($group.Ranges | Sort-Object Start)) {
            $segmentIndex = Add-ReencodedSegment -ResolvedPath $resolvedPath -TempRoot $tempRoot -Segments $segments -Index $segmentIndex -Start $patchCursor -End $range.Start -VideoEncoder $Encoder -EncoderPreset $Preset -Quality $Cq
            if ($range.End -gt $patchCursor) {
                $patchCursor = [double]($range.End)
            }
        }

        $segmentIndex = Add-ReencodedSegment -ResolvedPath $resolvedPath -TempRoot $tempRoot -Segments $segments -Index $segmentIndex -Start $patchCursor -End $group.PatchEnd -VideoEncoder $Encoder -EncoderPreset $Preset -Quality $Cq
        $cursor = [double]($group.PatchEnd)
    }

    $segmentIndex = Add-CopySegment -ResolvedPath $resolvedPath -TempRoot $tempRoot -Segments $segments -Index $segmentIndex -Start $cursor -End $metadata.Duration

    $concatList = Join-Path $tempRoot "concat.txt"
    $segments | ForEach-Object { "file '$($_.Replace("'", "'\''"))'" } | Set-Content -LiteralPath $concatList -Encoding ASCII

    $concatArgs = @(
        "-hide_banner", "-n", "-v", "warning",
        "-f", "concat",
        "-safe", "0",
        "-i", $concatList,
        "-map", "0",
        "-c", "copy",
        "-movflags", "+faststart",
        $outputFullPath
    )

    Invoke-RepairCommand -Step "concat final" -CommandArgs $concatArgs -OutputFile $outputFullPath
    Test-RepairedOutput -OutputFile $outputFullPath
    $keepOutput = $true

    Write-Host "------------------------------------------------------------------"
    Write-Host "Repair output: $outputFullPath" -ForegroundColor Green
    $script:StepRows | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "Automated stream probe and full-decode verification passed. Visual review is still required." -ForegroundColor Yellow
}
finally {
    if ($KeepTemp) {
        Write-Host "Temporary files kept at: $tempRoot" -ForegroundColor Yellow
    }
    elseif (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    if ((-not $keepOutput) -and (Test-Path -LiteralPath $outputFullPath -PathType Leaf)) {
        Remove-Item -LiteralPath $outputFullPath -Force -ErrorAction SilentlyContinue
    }
}
