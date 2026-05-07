# lib/Policy.ps1
# Personal bitrate policy – subjective by design
# 1080p is the reference resolution

# --- FPS classification ---
function Get-FpsBucket {
    param ([double]$Fps)

    if ($Fps -ge 45 -and $Fps -le 65) {
        return "High"
    }
    elseif ($Fps -ge 20 -and $Fps -le 32) {
        return "Low"
    }
    else {
        return "Unknown"
    }
}

# --- Bitrate policy ---
function Get-BitratePolicy {
    param (
        [int]$Height,
        [double]$Fps,
        [double]$BitrateMbps
    )

    if ($Height -le 0 -or $Fps -le 0 -or $BitrateMbps -le 0) {
        return "Unknown"
    }

    $fpsBucket = Get-FpsBucket $Fps

    # --- Normal bitrate ceilings by resolution ---
    if ($Height -ge 2160) {
        # 4K
        $normalMax = ($fpsBucket -eq "High") ? 35 : 25
    }
    elseif ($Height -ge 1080) {
        # 1080p (reference)
        $normalMax = ($fpsBucket -eq "High") ? 25 : 12
    }
    elseif ($Height -ge 720) {
        # 720p class
        $normalMax = ($fpsBucket -eq "High") ? 12 : 6
    }
    elseif ($Height -gt 480) {
        # In-between (540p / 576p etc.)
        $normalMax = ($fpsBucket -eq "High") ? 8 : 4
    }
    else {
        # 480p and lower
        $normalMax = ($fpsBucket -eq "High") ? 4 : 2
    }

    # --- Tier thresholds ---
    $lowMax = $normalMax * 0.4

    if ($BitrateMbps -le $lowMax) {
        return "Low"
    }
    elseif ($BitrateMbps -le $normalMax) {
        return "Normal"
    }
    elseif ($BitrateMbps -le $normalMax * 1.5) {
        return "High"
    }
    elseif ($BitrateMbps -le 75) {
        return "Very high"
    }
    else {
        return "Extreme"
    }
}
