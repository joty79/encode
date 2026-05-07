# lib/Metrics.ps1
# Pure math helpers – no policy, no flags, no opinions

function Get-CompressionDensity {
    param (
        [int]$Width,
        [int]$Height,
        [double]$Fps,
        [double]$BitrateMbps
    )

    if ($Width -le 0 -or $Height -le 0 -or $Fps -le 0 -or $BitrateMbps -le 0) {
        return $null
    }

    $bps = $BitrateMbps * 1e6

    return [Math]::Round(
        $bps / ($Width * $Height * $Fps),
        3
    )
}
