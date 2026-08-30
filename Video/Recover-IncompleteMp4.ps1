<#
.SYNOPSIS
    Recovers H.264 and experimental AAC from a truncated Microsoft-encoder MP4 that is missing its final moov atom.

.DESCRIPTION
    This terminal-only recovery tool targets the characterized layout produced by
    Microsoft H.264 Encoder V1.5.3: MP4 ftyp/free/mdat, length-prefixed H.264,
    interleaved raw AAC-LC, and no final moov because the download ended early.

    The source is always preserved. The script reconstructs elementary tracks in
    a unique temporary directory, remuxes them with FFmpeg, refuses collisions,
    validates the video with a full strict decode, and reports audio decode
    warnings separately because perceptually correct recovered AAC can remain
    stricter-decoder-incompatible.

    This is not a generic "repair any MP4" utility. Unknown encoders, healthy MP4
    files, files without a truncated mdat, and non-H.264 layouts are rejected.

.PARAMETER Path
    Truncated .mp4 input. It is opened read-only and never replaced or deleted.

.PARAMETER OutputPath
    New MP4 output. Defaults to <name>_recovered_av.mp4, or
    <name>_recovered_video_only.mp4 with -VideoOnly.

.PARAMETER VideoOnly
    Recover only H.264. This is the strictest path when AAC reconstruction is not wanted.

.PARAMETER RequireCleanAudioDecode
    Treat any FFmpeg audio decode diagnostic as failure. Without this switch,
    audio warnings are reported as PLAYBACK_REVIEW while structurally valid video
    can still be delivered for manual listening.

.PARAMETER NoVerify
    Skip full video/audio decode. Structural ffprobe validation still runs.

.PARAMETER KeepTemp
    Preserve raw recovered tracks and the JSON recovery report for investigation.

.EXAMPLE
    pwsh -File '.\Video\Recover-IncompleteMp4.ps1' -Path 'D:\Video\broken.mp4'

.EXAMPLE
    pwsh -File '.\Video\Recover-IncompleteMp4.ps1' -Path 'D:\Video\broken.mp4' -VideoOnly
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$Path,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$VideoOnly,

    [Parameter()]
    [switch]$RequireCleanAudioDecode,

    [Parameter()]
    [switch]$NoVerify,

    [Parameter()]
    [switch]$KeepTemp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Application {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Candidates = @()
    )

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\WindowsApps\\' } |
        Select-Object -First 1
    if (-not $command) {
        throw "Required application '$Name' was not found."
    }
    return $command.Source
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$NativeArguments
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    foreach ($nativeArgument in $NativeArguments) {
        [void]$startInfo.ArgumentList.Add($nativeArgument)
    }
    $process = [Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout   = $stdoutTask.GetAwaiter().GetResult()
        Stderr   = $stderrTask.GetAwaiter().GetResult()
    }
}

function Get-NonEmptyLines {
    param([AllowEmptyString()][string]$Text)
    return ,@(($Text -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$recoveryEngineSource = @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

public sealed class IncompleteMp4AudioReport
{
    public bool enabled { get; set; }
    public int frames { get; set; }
    public int exact_regions { get; set; }
    public int ambiguous_regions { get; set; }
    public int fallback_regions { get; set; }
    public int dropped_incomplete_tail_frames { get; set; }
    public double mean_exact_frame_bytes { get; set; }
}

public sealed class IncompleteMp4RecoveryReport
{
    public int width { get; set; }
    public int height { get; set; }
    public int fps_numerator { get; set; }
    public int fps_denominator { get; set; }
    public double fps { get; set; }
    public string fps_ratio { get; set; }
    public long input_bytes { get; set; }
    public long mdat_offset { get; set; }
    public long mdat_declared_bytes { get; set; }
    public long mdat_available_bytes { get; set; }
    public bool truncated_mdat { get; set; }
    public int video_frames { get; set; }
    public int video_nals { get; set; }
    public IncompleteMp4AudioReport audio { get; set; }
}

public static unsafe class IncompleteMp4Recovery
{
    private const int MaxNalSize = 64 * 1024 * 1024;
    private static readonly Regex Parameters = new Regex(
        @"h:(?<height>\d+)\s+w:(?<width>\d+)\s+fps:(?<fps>\d+(?:\.\d+)?)",
        RegexOptions.CultureInvariant);

    private sealed class MdatInfo
    {
        public long Offset;
        public long PayloadStart;
        public long PayloadEnd;
        public long DeclaredSize;
    }

    private sealed class EncoderParameters
    {
        public int Width;
        public int Height;
        public int FpsNumerator;
        public int FpsDenominator;
        public double Fps;
    }

    private sealed class NalRange
    {
        public long Offset;
        public int Size;
    }

    private sealed class VideoRegion
    {
        public long End;
        public int Frames;
        public List<NalRange> Nals = new List<NalRange>();
    }

    private sealed class AudioRegion
    {
        public long Start;
        public long End;
        public int Count;
    }

    private sealed class FrameRange
    {
        public long Offset;
        public int Size;
    }

    private sealed class AudioModel
    {
        public double Mean;
        public double Stdev;
        public int Minimum;
        public int Maximum;
        public int ExactCount;
        public Dictionary<int, int> Signatures = new Dictionary<int, int>();
    }

    private sealed class SplitState
    {
        public double Cost;
        public List<int> Path;
    }

    private sealed class SplitResult
    {
        public List<FrameRange> Frames;
        public bool UsedFallback;
    }

    private static uint ReadU32(byte* data, long offset)
    {
        return ((uint)data[offset] << 24) |
               ((uint)data[offset + 1] << 16) |
               ((uint)data[offset + 2] << 8) |
               data[offset + 3];
    }

    private static ulong ReadU64(byte* data, long offset)
    {
        return ((ulong)ReadU32(data, offset) << 32) | ReadU32(data, offset + 4);
    }

    private static bool BoxType(byte* data, long offset, char a, char b, char c, char d)
    {
        return data[offset + 4] == (byte)a && data[offset + 5] == (byte)b &&
               data[offset + 6] == (byte)c && data[offset + 7] == (byte)d;
    }

    private static MdatInfo FindMdat(byte* data, long fileSize)
    {
        long offset = 0;
        bool sawFtyp = false;
        MdatInfo found = null;

        while (offset >= 0 && offset + 8 <= fileSize)
        {
            uint size32 = ReadU32(data, offset);
            long headerSize = 8;
            long declaredSize;
            if (size32 == 1)
            {
                if (offset + 16 > fileSize) break;
                ulong size64 = ReadU64(data, offset + 8);
                if (size64 > long.MaxValue) throw new InvalidDataException("MP4 box size is unsupported.");
                declaredSize = (long)size64;
                headerSize = 16;
            }
            else if (size32 == 0)
            {
                declaredSize = fileSize - offset;
            }
            else
            {
                declaredSize = size32;
            }

            if (BoxType(data, offset, 'f', 't', 'y', 'p')) sawFtyp = true;
            if (BoxType(data, offset, 'm', 'o', 'o', 'v'))
                throw new InvalidDataException("Input already contains a moov atom; incomplete recovery is not applicable.");
            if (BoxType(data, offset, 'm', 'd', 'a', 't'))
            {
                if (!sawFtyp) throw new InvalidDataException("The input does not have an MP4 ftyp box before mdat.");
                long remaining = fileSize - offset;
                long usableSize = Math.Min(declaredSize, remaining);
                if (usableSize <= headerSize) throw new InvalidDataException("The mdat box has no usable payload.");
                found = new MdatInfo
                {
                    Offset = offset,
                    PayloadStart = offset + headerSize,
                    PayloadEnd = offset + usableSize,
                    DeclaredSize = declaredSize
                };
            }

            if (declaredSize < headerSize || declaredSize > fileSize - offset) break;
            offset += declaredSize;
        }

        if (found == null) throw new InvalidDataException("No usable MP4 mdat box was found.");
        return found;
    }

    private static bool TryNalAt(byte* data, long offset, long end, out int length, out int nalType)
    {
        length = 0;
        nalType = 0;
        if (offset + 5 > end) return false;
        uint rawLength = ReadU32(data, offset);
        nalType = data[offset + 4] & 0x1F;
        if (rawLength < 1 || rawLength > MaxNalSize ||
            !(nalType >= 1 && nalType <= 9) ||
            (data[offset + 4] & 0x80) != 0 ||
            rawLength > (ulong)(end - offset - 4)) return false;
        length = (int)rawLength;
        return true;
    }

    private static bool CandidateIsVideo(byte* data, long offset, long end)
    {
        if (offset + 11 > end || data[offset] != 0 || data[offset + 1] != 0 ||
            data[offset + 2] != 0 || data[offset + 3] != 2 || data[offset + 4] != 9) return false;

        long position = offset;
        for (int index = 0; index < 10; index++)
        {
            int length, nalType;
            if (!TryNalAt(data, position, end, out length, out nalType)) break;
            if (nalType >= 1 && nalType <= 5) return true;
            position += 4L + length;
        }
        return false;
    }

    private static long FindNextVideo(byte* data, long start, long end)
    {
        for (long candidate = Math.Max(0, start); candidate + 5 <= end; candidate++)
        {
            if (data[candidate] == 0 && data[candidate + 1] == 0 &&
                data[candidate + 2] == 0 && data[candidate + 3] == 2 &&
                data[candidate + 4] == 9 && CandidateIsVideo(data, candidate, end)) return candidate;
        }
        return -1;
    }

    private static VideoRegion ParseVideoRegion(byte* data, long start, long end)
    {
        var result = new VideoRegion();
        long position = start;
        bool currentHasSlice = false;
        while (true)
        {
            int length, nalType;
            if (!TryNalAt(data, position, end, out length, out nalType)) break;
            if (nalType == 9)
            {
                if (currentHasSlice) result.Frames++;
                currentHasSlice = false;
            }
            else if (nalType >= 1 && nalType <= 5)
            {
                currentHasSlice = true;
            }
            result.Nals.Add(new NalRange { Offset = position + 4, Size = length });
            position += 4L + length;
        }
        if (currentHasSlice) result.Frames++;
        result.End = position;
        return result;
    }

    private static int[] ApproximateFraction(double value, int maximumDenominator)
    {
        int bestNumerator = (int)Math.Round(value, MidpointRounding.ToEven);
        int bestDenominator = 1;
        double bestError = Math.Abs(value - bestNumerator);
        for (int denominator = 2; denominator <= maximumDenominator; denominator++)
        {
            int numerator = (int)Math.Round(value * denominator, MidpointRounding.ToEven);
            double error = Math.Abs(value - (double)numerator / denominator);
            if (error < bestError)
            {
                bestError = error;
                bestNumerator = numerator;
                bestDenominator = denominator;
            }
        }
        int gcd = GreatestCommonDivisor(Math.Abs(bestNumerator), bestDenominator);
        return new[] { bestNumerator / gcd, bestDenominator / gcd };
    }

    private static int GreatestCommonDivisor(int left, int right)
    {
        while (right != 0)
        {
            int next = left % right;
            left = right;
            right = next;
        }
        return Math.Max(1, left);
    }

    private static EncoderParameters ParseEncoderParameters(byte* data, long payloadStart, long payloadEnd)
    {
        int sampleLength = (int)Math.Min(256 * 1024L, payloadEnd - payloadStart);
        var sample = new byte[sampleLength];
        Marshal.Copy((IntPtr)(data + payloadStart), sample, 0, sampleLength);
        string text = Encoding.ASCII.GetString(sample);
        if (text.IndexOf("Microsoft H.264 Encoder", StringComparison.Ordinal) < 0)
            throw new InvalidDataException("The characterized Microsoft H.264 Encoder signature was not found. This tool deliberately refuses unknown recorder layouts.");
        Match match = Parameters.Match(text);
        if (!match.Success) throw new InvalidDataException("Microsoft encoder parameters (h/w/fps) were not found in mdat.");

        double fpsDecimal = double.Parse(match.Groups["fps"].Value, CultureInfo.InvariantCulture);
        int numerator, denominator;
        if (Math.Abs(fpsDecimal - 29.97) < 0.01) { numerator = 30000; denominator = 1001; }
        else if (Math.Abs(fpsDecimal - 59.94) < 0.01) { numerator = 60000; denominator = 1001; }
        else if (Math.Abs(fpsDecimal - 23.976) < 0.01) { numerator = 24000; denominator = 1001; }
        else
        {
            int[] fraction = ApproximateFraction(fpsDecimal, 1001);
            numerator = fraction[0];
            denominator = fraction[1];
        }

        return new EncoderParameters
        {
            Width = int.Parse(match.Groups["width"].Value, CultureInfo.InvariantCulture),
            Height = int.Parse(match.Groups["height"].Value, CultureInfo.InvariantCulture),
            FpsNumerator = numerator,
            FpsDenominator = denominator,
            Fps = (double)numerator / denominator
        };
    }

    private static bool TryAacHeaderSignature(byte* data, long offset, long totalLength, out int signature)
    {
        signature = 0;
        if (offset + 3 > totalLength) return false;
        int b0 = data[offset], b1 = data[offset + 1], b2 = data[offset + 2];
        if ((b0 != 0x20 && b0 != 0x21) || (b1 & 0x80) != 0) return false;
        int windowSequence = (b1 >> 5) & 3;
        int maxSfb;
        if (windowSequence == 2)
        {
            maxSfb = b1 & 0x0F;
            if (maxSfb > 14) return false;
        }
        else
        {
            maxSfb = ((b1 & 0x0F) << 2) | ((b2 >> 6) & 3);
            if (maxSfb > 49 || (b2 & 0x20) != 0) return false;
        }
        int msMask = -1;
        if (b0 == 0x21 && windowSequence != 2)
        {
            msMask = (b2 >> 3) & 3;
            if (msMask == 3) return false;
        }
        signature = b0 | (windowSequence << 8) | (maxSfb << 16) | ((msMask + 1) << 24);
        return true;
    }

    private static AudioModel LearnAudioModel(byte* data, long dataLength, List<AudioRegion> regions)
    {
        var sizes = new List<int>();
        var signatures = new Dictionary<int, int>();
        foreach (AudioRegion region in regions)
        {
            if (region.Count != 1) continue;
            long rawSize = region.End - region.Start;
            if (rawSize > int.MaxValue) throw new InvalidDataException("An exact AAC region is unexpectedly large.");
            int size = (int)rawSize;
            sizes.Add(size);
            int signature;
            if (TryAacHeaderSignature(data, region.Start, dataLength, out signature))
            {
                int count;
                signatures.TryGetValue(signature, out count);
                signatures[signature] = count + 1;
            }
        }
        if (sizes.Count < 50) throw new InvalidDataException("Too few exact one-frame audio regions to infer AAC boundaries safely.");
        if (signatures.Count == 0) throw new InvalidDataException("Exact audio regions did not expose recognizable AAC-LC headers.");

        double sum = 0;
        int minimum = int.MaxValue, maximum = int.MinValue;
        foreach (int size in sizes)
        {
            sum += size;
            minimum = Math.Min(minimum, size);
            maximum = Math.Max(maximum, size);
        }
        double mean = sum / sizes.Count;
        double squared = 0;
        foreach (int size in sizes) squared += (size - mean) * (size - mean);
        return new AudioModel
        {
            Mean = mean,
            Stdev = Math.Max(Math.Sqrt(squared / sizes.Count), 8.0),
            Minimum = minimum,
            Maximum = maximum,
            ExactCount = sizes.Count,
            Signatures = signatures
        };
    }

    private static SplitState SolveBoundaries(
        int size, int frameCount, double mean, double stdev,
        List<int> candidates, Dictionary<int, double> scores,
        int lowerBound, int upperBound)
    {
        var states = new Dictionary<int, SplitState>();
        states[0] = new SplitState { Cost = 0, Path = new List<int> { 0 } };
        for (int frame = 0; frame < frameCount - 1; frame++)
        {
            var nextStates = new Dictionary<int, SplitState>();
            foreach (KeyValuePair<int, SplitState> state in states)
            {
                int previous = state.Key;
                foreach (int candidate in candidates)
                {
                    int frameSize = candidate - previous;
                    if (candidate <= previous || frameSize < lowerBound || frameSize > upperBound) continue;
                    double score;
                    scores.TryGetValue(candidate, out score);
                    double newCost = state.Value.Cost + Math.Pow((frameSize - mean) / stdev, 2) - score;
                    SplitState current;
                    if (!nextStates.TryGetValue(candidate, out current) || newCost < current.Cost)
                    {
                        var path = new List<int>(state.Value.Path) { candidate };
                        nextStates[candidate] = new SplitState { Cost = newCost, Path = path };
                    }
                }
            }
            states = nextStates;
            if (states.Count == 0) break;
        }

        SplitState best = null;
        foreach (KeyValuePair<int, SplitState> state in states)
        {
            int finalSize = size - state.Key;
            if (finalSize < lowerBound || finalSize > upperBound) continue;
            double total = state.Value.Cost + Math.Pow((finalSize - mean) / stdev, 2);
            if (best == null || total < best.Cost)
            {
                var path = new List<int>(state.Value.Path) { size };
                best = new SplitState { Cost = total, Path = path };
            }
        }
        return best;
    }

    private static SplitResult SplitAudioRegion(byte* data, long dataLength, long start, long end, int frameCount, AudioModel model)
    {
        long rawSize = end - start;
        if (rawSize > int.MaxValue) throw new InvalidDataException("An AAC region is unexpectedly large.");
        int size = (int)rawSize;
        if (frameCount <= 1)
        {
            return new SplitResult
            {
                Frames = new List<FrameRange> { new FrameRange { Offset = start, Size = size } },
                UsedFallback = false
            };
        }

        int minSize = Math.Max(32, (int)(model.Minimum * 0.65));
        int maxSize = (int)(model.Maximum * 1.35);
        int mostCommon = 0;
        foreach (int count in model.Signatures.Values) mostCommon = Math.Max(mostCommon, count);
        var candidates = new List<int> { 0 };
        var scores = new Dictionary<int, double> { [0] = 0 };
        for (int relative = 1; relative < size - 2; relative++)
        {
            int signature;
            if (!TryAacHeaderSignature(data, start + relative, dataLength, out signature)) continue;
            int frequency;
            model.Signatures.TryGetValue(signature, out frequency);
            candidates.Add(relative);
            scores[relative] = 5.0 * Math.Log(1.0 + frequency) / Math.Log(1.0 + mostCommon);
        }

        SplitState best = SolveBoundaries(size, frameCount, model.Mean, model.Stdev, candidates, scores, minSize, maxSize);
        if (best == null)
        {
            double targetSize = (double)size / frameCount;
            best = SolveBoundaries(
                size, frameCount, model.Mean, model.Stdev, candidates, scores,
                Math.Max(32, (int)(targetSize * 0.15)), (int)(targetSize * 3.0));
        }

        bool fallback = best == null;
        List<int> boundaries;
        if (fallback)
        {
            boundaries = new List<int>();
            for (int index = 0; index <= frameCount; index++)
                boundaries.Add((int)Math.Round((double)index * size / frameCount, MidpointRounding.ToEven));
        }
        else
        {
            boundaries = best.Path;
        }

        var frames = new List<FrameRange>();
        for (int index = 0; index < frameCount; index++)
        {
            frames.Add(new FrameRange
            {
                Offset = start + boundaries[index],
                Size = boundaries[index + 1] - boundaries[index]
            });
        }
        return new SplitResult { Frames = frames, UsedFallback = fallback };
    }

    private static byte[] AdtsHeader(int payloadSize)
    {
        int frameLength = payloadSize + 7;
        if (frameLength > 0x1FFF) throw new InvalidDataException("AAC payload is too large for ADTS: " + payloadSize + " bytes");
        const int profile = 1;
        const int sampleRateIndex = 3;
        const int channels = 2;
        return new[]
        {
            (byte)0xFF,
            (byte)0xF1,
            (byte)((profile << 6) | (sampleRateIndex << 2) | (channels >> 2)),
            (byte)(((channels & 3) << 6) | (frameLength >> 11)),
            (byte)((frameLength >> 3) & 0xFF),
            (byte)(((frameLength & 7) << 5) | 0x1F),
            (byte)0xFC
        };
    }

    private static void WriteRange(FileStream output, byte* data, long offset, int count, byte[] buffer)
    {
        int remaining = count;
        long position = offset;
        while (remaining > 0)
        {
            int chunk = Math.Min(remaining, buffer.Length);
            Marshal.Copy((IntPtr)(data + position), buffer, 0, chunk);
            output.Write(buffer, 0, chunk);
            position += chunk;
            remaining -= chunk;
        }
    }

    public static IncompleteMp4RecoveryReport Recover(string inputPath, string videoPath, string audioPath)
    {
        if (!File.Exists(inputPath)) throw new FileNotFoundException("Input file does not exist.", inputPath);
        if (File.Exists(videoPath)) throw new IOException("Refusing existing output: " + videoPath);
        if (audioPath != null && File.Exists(audioPath)) throw new IOException("Refusing existing output: " + audioPath);
        long fileSize = new FileInfo(inputPath).Length;
        if (fileSize < 8) throw new InvalidDataException("Input is too small to be an MP4.");

        using (var map = MemoryMappedFile.CreateFromFile(inputPath, FileMode.Open, null, 0, MemoryMappedFileAccess.Read))
        using (var accessor = map.CreateViewAccessor(0, 0, MemoryMappedFileAccess.Read))
        {
            byte* acquired = null;
            accessor.SafeMemoryMappedViewHandle.AcquirePointer(ref acquired);
            try
            {
                byte* data = acquired + accessor.PointerOffset;
                MdatInfo mdat = FindMdat(data, fileSize);
                EncoderParameters parameters = ParseEncoderParameters(data, mdat.PayloadStart, mdat.PayloadEnd);
                long firstVideo = FindNextVideo(data, mdat.PayloadStart, Math.Min(mdat.PayloadEnd, mdat.PayloadStart + 1024 * 1024L));
                if (firstVideo < 0) throw new InvalidDataException("No valid length-prefixed H.264 access unit was found near mdat start.");

                double audioPerVideo = 48000.0 * parameters.FpsDenominator / (1024.0 * parameters.FpsNumerator);
                int videoFrames = 0;
                int scheduledAudio = 0;
                var audioRegions = new List<AudioRegion>();
                var videoNals = new List<NalRange>();
                long position = firstVideo;
                while (position >= 0 && position < mdat.PayloadEnd)
                {
                    VideoRegion region = ParseVideoRegion(data, position, mdat.PayloadEnd);
                    if (region.Frames == 0) break;
                    videoNals.AddRange(region.Nals);
                    videoFrames += region.Frames;
                    long nextVideo = FindNextVideo(data, region.End, mdat.PayloadEnd);
                    long audioEnd = nextVideo >= 0 ? nextVideo : mdat.PayloadEnd;
                    if (audioEnd > region.End)
                    {
                        int expectedAudio = (int)Math.Round(videoFrames * audioPerVideo, MidpointRounding.ToEven);
                        int regionAudioFrames = Math.Max(1, expectedAudio - scheduledAudio);
                        audioRegions.Add(new AudioRegion { Start = region.End, End = audioEnd, Count = regionAudioFrames });
                        scheduledAudio += regionAudioFrames;
                    }
                    position = nextVideo;
                }
                if (videoFrames < 2 || videoNals.Count == 0)
                    throw new InvalidDataException("The mdat scan did not recover enough complete H.264 frames.");

                var copyBuffer = new byte[1024 * 1024];
                using (var videoOutput = new FileStream(videoPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, copyBuffer.Length, FileOptions.SequentialScan))
                {
                    byte[] annexB = { 0, 0, 0, 1 };
                    foreach (NalRange nal in videoNals)
                    {
                        videoOutput.Write(annexB, 0, annexB.Length);
                        WriteRange(videoOutput, data, nal.Offset, nal.Size, copyBuffer);
                    }
                }

                var audioReport = new IncompleteMp4AudioReport { enabled = audioPath != null };
                if (audioPath != null)
                {
                    AudioModel model = LearnAudioModel(data, fileSize, audioRegions);
                    var recoveredAudio = new List<FrameRange>();
                    int fallbackRegions = 0, ambiguousRegions = 0, droppedTailFrames = 0;
                    for (int regionIndex = 0; regionIndex < audioRegions.Count; regionIndex++)
                    {
                        AudioRegion region = audioRegions[regionIndex];
                        long regionBytes = region.End - region.Start;
                        if (regionBytes > 0x1FF8L * region.Count)
                        {
                            if (regionIndex != audioRegions.Count - 1)
                                throw new InvalidDataException("An implausibly large non-tail audio region was found; refusing to guess across possible payload damage.");
                            droppedTailFrames += region.Count;
                            continue;
                        }
                        SplitResult split = SplitAudioRegion(data, fileSize, region.Start, region.End, region.Count, model);
                        recoveredAudio.AddRange(split.Frames);
                        if (region.Count > 1) ambiguousRegions++;
                        if (split.UsedFallback) fallbackRegions++;
                    }

                    using (var audioOutput = new FileStream(audioPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, copyBuffer.Length, FileOptions.SequentialScan))
                    {
                        foreach (FrameRange frame in recoveredAudio)
                        {
                            byte[] header = AdtsHeader(frame.Size);
                            audioOutput.Write(header, 0, header.Length);
                            WriteRange(audioOutput, data, frame.Offset, frame.Size, copyBuffer);
                        }
                    }
                    audioReport = new IncompleteMp4AudioReport
                    {
                        enabled = true,
                        frames = recoveredAudio.Count,
                        exact_regions = model.ExactCount,
                        ambiguous_regions = ambiguousRegions,
                        fallback_regions = fallbackRegions,
                        dropped_incomplete_tail_frames = droppedTailFrames,
                        mean_exact_frame_bytes = Math.Round(model.Mean, 3)
                    };
                }

                long availableBytes = mdat.PayloadEnd - mdat.Offset;
                return new IncompleteMp4RecoveryReport
                {
                    width = parameters.Width,
                    height = parameters.Height,
                    fps_numerator = parameters.FpsNumerator,
                    fps_denominator = parameters.FpsDenominator,
                    fps = parameters.Fps,
                    fps_ratio = parameters.FpsNumerator + "/" + parameters.FpsDenominator,
                    input_bytes = fileSize,
                    mdat_offset = mdat.Offset,
                    mdat_declared_bytes = mdat.DeclaredSize,
                    mdat_available_bytes = availableBytes,
                    truncated_mdat = mdat.DeclaredSize > availableBytes,
                    video_frames = videoFrames,
                    video_nals = videoNals.Count,
                    audio = audioReport
                };
            }
            finally
            {
                accessor.SafeMemoryMappedViewHandle.ReleasePointer();
            }
        }
    }
}
'@

if (-not ('IncompleteMp4Recovery' -as [type])) {
    Add-Type -TypeDefinition $recoveryEngineSource -Language CSharp -CompilerOptions '/unsafe'
}

if ($VideoOnly -and $RequireCleanAudioDecode) {
    throw '-RequireCleanAudioDecode cannot be combined with -VideoOnly.'
}

$resolvedInput = (Resolve-Path -LiteralPath $Path).Path
if (-not [string]::Equals([IO.Path]::GetExtension($resolvedInput), '.mp4', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Input must use the .mp4 extension: $resolvedInput"
}

if ($OutputPath) {
    $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
}
else {
    $inputDirectory = [IO.Path]::GetDirectoryName($resolvedInput)
    $inputBaseName = [IO.Path]::GetFileNameWithoutExtension($resolvedInput)
    $suffix = if ($VideoOnly) { '_recovered_video_only.mp4' } else { '_recovered_av.mp4' }
    $resolvedOutput = Join-Path $inputDirectory ($inputBaseName + $suffix)
}

if (-not [string]::Equals([IO.Path]::GetExtension($resolvedOutput), '.mp4', [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputPath must use the .mp4 extension: $resolvedOutput"
}
if ([string]::Equals($resolvedInput, $resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputPath must not be the source path.'
}
if (Test-Path -LiteralPath $resolvedOutput) {
    throw "Refusing existing output: $resolvedOutput"
}
$outputDirectory = [IO.Path]::GetDirectoryName($resolvedOutput)
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "Output directory does not exist: $outputDirectory"
}

$ffmpeg = Resolve-Application -Name 'ffmpeg.exe' -Candidates @('E:\Compilers\ffmpeg\bin\ffmpeg.exe')
$ffprobe = Resolve-Application -Name 'ffprobe.exe' -Candidates @('E:\Compilers\ffmpeg\bin\ffprobe.exe')
$sourceBefore = Get-Item -LiteralPath $resolvedInput
$sourceLength = $sourceBefore.Length
$sourceWriteTime = $sourceBefore.LastWriteTimeUtc
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('encode-truncated-mp4-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempRoot)
$rawVideo = Join-Path $tempRoot 'recovered.h264'
$rawAudio = Join-Path $tempRoot 'recovered.aac'
$reportPath = Join-Path $tempRoot 'recovery.json'
$partialOutput = Join-Path $outputDirectory ('.{0}.partial.{1}.mp4' -f [IO.Path]::GetFileNameWithoutExtension($resolvedOutput), [guid]::NewGuid().ToString('N'))
$completed = $false

try {
    Write-Host ''
    Write-Host 'Incomplete MP4 recovery' -ForegroundColor Cyan
    Write-Host ('Input:  {0}' -f $resolvedInput)
    Write-Host ('Output: {0}' -f $resolvedOutput)
    Write-Host ('Mode:   {0}' -f $(if ($VideoOnly) { 'strict video-only' } else { 'video + experimental original AAC' }))
    Write-Host ''

    $audioRecoveryPath = if ($VideoOnly) { $null } else { $rawAudio }
    try {
        $report = [IncompleteMp4Recovery]::Recover($resolvedInput, $rawVideo, $audioRecoveryPath)
    }
    catch {
        throw "Recovery engine failed. $($_.Exception.GetBaseException().Message)"
    }
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

    Write-Host ('Detected: {0}x{1}, {2} fps, {3:N0} video frames' -f `
        $report.width, $report.height, $report.fps_ratio, $report.video_frames) -ForegroundColor Green
    Write-Host ('mdat: declared {0:N0} bytes; available {1:N0} bytes; truncated={2}' -f `
        $report.mdat_declared_bytes, $report.mdat_available_bytes, $report.truncated_mdat)
    if (-not $VideoOnly) {
        Write-Host ('AAC: {0:N0} frames; exact regions={1:N0}; ambiguous regions={2:N0}; fallbacks={3:N0}; dropped EOF frames={4:N0}' -f `
            $report.audio.frames, $report.audio.exact_regions,
            $report.audio.ambiguous_regions, $report.audio.fallback_regions,
            $report.audio.dropped_incomplete_tail_frames)
    }

    $muxArguments = @(
        '-hide_banner', '-v', 'warning', '-n',
        '-fflags', '+genpts',
        '-r', [string]$report.fps_ratio,
        '-f', 'h264', '-i', $rawVideo
    )
    if (-not $VideoOnly) {
        $muxArguments += @('-f', 'aac', '-i', $rawAudio)
    }
    $muxArguments += @('-map', '0:v:0')
    if (-not $VideoOnly) {
        $muxArguments += @('-map', '1:a:0')
    }
    $muxArguments += @('-c', 'copy')
    $muxArguments += @('-movflags', '+faststart', $partialOutput)

    $muxResult = Invoke-NativeCapture -Executable $ffmpeg -NativeArguments $muxArguments
    if ($muxResult.ExitCode -ne 0) {
        throw "FFmpeg remux failed with exit code $($muxResult.ExitCode).`n$($muxResult.Stderr)"
    }
    if (-not (Test-Path -LiteralPath $partialOutput -PathType Leaf) -or
        (Get-Item -LiteralPath $partialOutput).Length -le 0) {
        throw 'FFmpeg returned success without a non-empty MP4 output.'
    }

    $probeResult = Invoke-NativeCapture -Executable $ffprobe -NativeArguments @(
        '-hide_banner', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', $partialOutput
    )
    if ($probeResult.ExitCode -ne 0) {
        throw "Recovered MP4 probe failed. $($probeResult.Stderr)"
    }
    $probe = $probeResult.Stdout | ConvertFrom-Json
    $videoStreams = @($probe.streams | Where-Object codec_type -eq 'video')
    $audioStreams = @($probe.streams | Where-Object codec_type -eq 'audio')
    if ($videoStreams.Count -ne 1 -or [string]$videoStreams[0].codec_name -ne 'h264') {
        throw 'Recovered MP4 does not contain exactly one H.264 video stream.'
    }
    if ($VideoOnly -and $audioStreams.Count -ne 0) {
        throw 'Video-only output unexpectedly contains audio.'
    }
    if (-not $VideoOnly -and ($audioStreams.Count -ne 1 -or [string]$audioStreams[0].codec_name -ne 'aac')) {
        throw 'Recovered A/V MP4 does not contain exactly one AAC audio stream.'
    }

    $audioDiagnosticLines = @()
    if (-not $NoVerify) {
        Write-Host 'Running full strict video decode...'
        $videoDecode = Invoke-NativeCapture -Executable $ffmpeg -NativeArguments @(
            '-hide_banner', '-v', 'error', '-xerror',
            '-r', [string]$report.fps_ratio, '-f', 'h264', '-i', $rawVideo,
            '-map', '0:v:0', '-an', '-f', 'null', 'NUL'
        )
        $videoDiagnosticLines = Get-NonEmptyLines -Text $videoDecode.Stderr
        if ($videoDecode.ExitCode -ne 0 -or $videoDiagnosticLines.Count -ne 0) {
            throw "Recovered video full decode failed.`n$($videoDiagnosticLines -join [Environment]::NewLine)"
        }
        Write-Host 'Video verification: STRICT-CLEAN' -ForegroundColor Green

        if (-not $VideoOnly) {
            Write-Host 'Running recovered audio decode assessment...'
            $audioDecode = Invoke-NativeCapture -Executable $ffmpeg -NativeArguments @(
                '-hide_banner', '-v', 'error', '-i', $partialOutput,
                '-map', '0:a:0', '-vn', '-f', 'null', 'NUL'
            )
            $audioDiagnosticLines = Get-NonEmptyLines -Text $audioDecode.Stderr
            if ($audioDecode.ExitCode -ne 0 -or $audioDiagnosticLines.Count -ne 0) {
                if ($RequireCleanAudioDecode) {
                    throw "Recovered AAC is not strict-clean ($($audioDiagnosticLines.Count) diagnostic lines)."
                }
                $audioWarning = ("Audio verification: PLAYBACK-REVIEW ({0} FFmpeg diagnostic lines). " +
                    'Manual listening is authoritative for this experimental raw-AAC reconstruction.') -f $audioDiagnosticLines.Count
                Write-Warning $audioWarning
            }
            else {
                Write-Host 'Audio verification: STRICT-CLEAN' -ForegroundColor Green
            }
        }
    }

    $sourceAfter = Get-Item -LiteralPath $resolvedInput
    if ($sourceAfter.Length -ne $sourceLength -or $sourceAfter.LastWriteTimeUtc -ne $sourceWriteTime) {
        throw 'Source size or last-write timestamp changed during recovery.'
    }

    Move-Item -LiteralPath $partialOutput -Destination $resolvedOutput -ErrorAction Stop
    $completed = $true
    Write-Host ''
    Write-Host ('Recovery complete: {0}' -f $resolvedOutput) -ForegroundColor Green
    Write-Host ('Output bytes: {0:N0}' -f (Get-Item -LiteralPath $resolvedOutput).Length)
    if ($audioDiagnosticLines.Count -gt 0) {
        Write-Host 'Result status: verified video; recovered original AAC requires manual listening.' -ForegroundColor Yellow
    }
}
finally {
    if (-not $completed -and (Test-Path -LiteralPath $partialOutput -PathType Leaf)) {
        Remove-Item -LiteralPath $partialOutput -Force -ErrorAction SilentlyContinue
    }
    if ($KeepTemp) {
        Write-Host ('Temporary recovery data kept at: {0}' -f $tempRoot) -ForegroundColor Yellow
    }
    elseif (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
