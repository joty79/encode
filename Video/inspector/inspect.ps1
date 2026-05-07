# inspect.ps1
# Video / Audio inspection tool (read-only)

param (
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

# --- Load helpers ---
$root = $PSScriptRoot
. "$root\lib\Metrics.ps1"
. "$root\lib\Policy.ps1"
. "$root\lib\Render.ps1"

# --- ffprobe executable ---
$ffprobe = "ffprobe"

foreach ($path in $Paths) {

    # 🔸 FIX: Clean quotes just in case
    $path = $path -replace '"', ''

    # -----------------------------
    # Resolve files to inspect
    # -----------------------------
    $targets = @()
    $videoExtensions = "*.mp4", "*.mkv", "*.avi", "*.mov", "*.wmv", "*.mpg", "*.mpeg", "*.vob"

    # 🔸 FIX: .NET Directory Check
    if ([System.IO.Directory]::Exists($path)) {
        # Folder mode
        $targets = Get-ChildItem `
            -LiteralPath $path `
            -Recurse `
            -File `
            -Include $videoExtensions
    }
    # 🔸 FIX: .NET File Check
    elseif ([System.IO.File]::Exists($path)) {
        # Single file mode
        $targets = @( Get-Item -LiteralPath $path )
    }
    else {
        Write-Warning "Invalid path: $path"
        continue
    }

    if ($targets.Count -eq 0) {
        Write-Warning "No video files found in folder: $path"
        continue
    }

    foreach ($file in $targets) {

        $path = $file.FullName

        # --- ffprobe JSON ---
        $json = & $ffprobe `
            -v error `
            -print_format json `
            -show_streams `
            -show_format `
            "$path" | ConvertFrom-Json


        if (-not $json) {
            Write-Warning "ffprobe failed: $path"
            continue
        }

        # --- Select streams ---
        $video = $json.streams | Where-Object codec_type -eq "video" | Select-Object -First 1
        $audio = $json.streams | Where-Object codec_type -eq "audio" | Select-Object -First 1

        if (-not $video) {
            Write-Warning "No video stream found: $path"
            continue
        }

        # =============================
        # VIDEO INFO
        # =============================

        $width = [int]$video.width
        $height = [int]$video.height

        # SAR / DAR
        $sar = $video.sample_aspect_ratio
        if (-not $sar -or $sar -eq "0:1") { $sar = "1:1" }

        $dar = $video.display_aspect_ratio

        # FPS
        $avgFps = 0.0
        if ($video.avg_frame_rate -and $video.avg_frame_rate -ne "0/0") {
            $n, $d = $video.avg_frame_rate -split '/'
            if ($d -ne 0) {
                $avgFps = [math]::Round($n / $d, 3)
            }
        }

        $fpsMode = "CFR"
        if ($video.r_frame_rate -and $video.avg_frame_rate -and
            $video.r_frame_rate -ne $video.avg_frame_rate) {
            $fpsMode = "VFR"
        }

        # Scan type
        $scan = if ($video.field_order -and $video.field_order -ne "progressive") {
            "Interlaced"
        }
        else {
            "Progressive"
        }

        # =============================
        # BITRATE (robust)
        # =============================
        $bitrateMbps = 0.0

        # 1) stream bitrate (best)
        if ($video.bit_rate -and $video.bit_rate -gt 0) {
            $bitrateMbps = [math]::Round($video.bit_rate / 1e6, 2)
        }

        # 2) container / format bitrate (common for MPEG)
        elseif ($json.format.bit_rate -and $json.format.bit_rate -gt 0) {
            $bitrateMbps = [math]::Round($json.format.bit_rate / 1e6, 2)
        }

        # 3) fallback: compute from file size / duration
        elseif ($json.format.duration -and $json.format.duration -gt 0) {
            # 🔸 FIX: LiteralPath for size
            $fileSizeBytes = (Get-Item -LiteralPath $path).Length
            $bitrateMbps = [math]::Round(
                ($fileSizeBytes * 8) / $json.format.duration / 1e6,
                2
            )
        }


        # Codec
        $codec = $video.codec_name.ToUpper()

        # =============================
        # METRICS / POLICY
        # =============================

        $density = $null
        if ($bitrateMbps -gt 0 -and $avgFps -gt 0) {
            $density = Get-CompressionDensity $width $height $avgFps $bitrateMbps
        }

        $policy = Get-BitratePolicy $height $avgFps $bitrateMbps

        # =============================
        # RENDER OUTPUT
        # =============================

        # File (only filename, not full path)
        # 🔸 FIX: .NET Safe Filename
        Render-File ([System.IO.Path]::GetFileName($path))

        # Video
        Render-Video `
            "$width`x$height" `
            "$bitrateMbps" `
            "$avgFps" `
            $scan `
            $fpsMode

        # Compression
        $densityText = if ($density -ne $null) {
            "{0:N3}" -f $density
        }
        else {
            "N/A"
        }

        Render-Compression `
            $densityText `
            $policy `
            $codec

        # Geometry
        Render-Geometry `
            $sar `
            $dar

		
        # Audio
        if ($audio -and $audio.sample_rate) {
            Render-Audio $audio.sample_rate
        }
        else {
            Render-Audio "none"
        }
    }

}