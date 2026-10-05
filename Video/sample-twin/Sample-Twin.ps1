#Requires -Version 7.2
<#
.SYNOPSIS
    Sample Twin: analyze a video and generate a content-free synthetic twin.

.DESCRIPTION
    Windows Terminal front end for the Synthetic Sample Library. It analyzes the
    selected video (technical properties only), shows whether a synthetic twin of
    the same format can be generated, and generates and verifies it on request.
    The library is used unmodified through sample_twin_bridge.py. Nothing from
    the original pictures or sound is used or stored.

    UI: pinned ClaudeTui template (lib\ClaudeTui.psm1). Canonical source:
    D:\Users\joty79\scripts\ClaudeTui (repo joty79/ClaudeTui).

.PARAMETER Path
    The video to analyze (the Explorer context menu passes "%1").

.PARAMETER ToolRoot
    Folder containing the delivered library.py. Default: Desktop\Avidemux_Sample_Library_v0.1.

.PARAMETER Helpers
    Folder containing ffmpeg.exe and ffprobe.exe. Default: the tool's configuration.json.

.PARAMETER Library
    Sample library folder. Default: the tool's configuration.json.

.PARAMETER Glyphs
    Nerd (Windows Terminal default), Unicode or Ascii. -Plain is the same as -Glyphs Ascii.

.PARAMETER PreviewScreen
    Test hook: render one screen to stdout at PreviewWidth x PreviewHeight and exit.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Path,
    [string]$ToolRoot,
    [string]$Helpers,
    [string]$Library,
    [ValidateSet('Auto', 'Nerd', 'Unicode', 'Ascii')][string]$Glyphs = 'Auto',
    [switch]$Plain,
    [ValidateSet('analyzing', 'overview', 'details', 'generating', 'result', 'error')][string]$PreviewScreen,
    [ValidateRange(40, 400)][int]$PreviewWidth = 120,
    [ValidateRange(12, 200)][int]$PreviewHeight = 36,
    [switch]$PreviewTiming
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture

Import-Module (Join-Path $PSScriptRoot 'lib\ClaudeTui.psm1') -Force
Initialize-TuiGlyphs -Mode $(if ($Plain) { 'Ascii' } else { $Glyphs })
$G = $TuiGlyph

#region Formatting helpers --------------------------------------------------------------

function Get-Val($Object, [string]$Dotted) {
    $node = $Object
    foreach ($part in $Dotted.Split('.')) {
        if ($null -eq $node) { return $null }
        if ($node -is [System.Collections.IDictionary]) { $node = if ($node.Contains($part)) { $node[$part] } else { $null } }
        else { return $null }
    }
    $node
}

function Format-Number([double]$Value, [string]$Pattern = '0.##') { $Value.ToString($Pattern, $Invariant) }

function ConvertTo-Ratio($Value) {
    if ($null -eq $Value) { return $null }
    $parts = ([string]$Value) -split '[/:]'
    if ($parts.Count -ne 2) { return $null }
    $n = 0.0; $d = 0.0
    if (-not [double]::TryParse($parts[0], [System.Globalization.NumberStyles]::Float, $Invariant, [ref]$n)) { return $null }
    if (-not [double]::TryParse($parts[1], [System.Globalization.NumberStyles]::Float, $Invariant, [ref]$d) -or $d -eq 0) { return $null }
    $n / $d
}

function Format-Fps($Value) {
    $r = ConvertTo-Ratio $Value
    if ($null -eq $r -or $r -le 0) { return '?' }
    if ([Math]::Abs($r - [Math]::Round($r)) -lt 0.0005) { return Format-Number ([Math]::Round($r)) '0' }
    Format-Number $r '0.###'
}

function Format-Bitrate($Value) {
    $bps = 0.0
    if ($null -eq $Value -or -not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, $Invariant, [ref]$bps) -or $bps -le 0) { return $null }
    if ($bps -ge 1e6) { return "$(Format-Number ($bps / 1e6) '0.00') Mb/s" }
    "$(Format-Number ($bps / 1e3) '0') kb/s"
}

function Format-Bytes([double]$Bytes) {
    $units = 'B', 'KiB', 'MiB', 'GiB', 'TiB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) { $Bytes /= 1024; $i++ }
    "$(Format-Number $Bytes ($(if ($i -eq 0) { '0' } else { '0.0' }))) $($units[$i])"
}

function Format-Level($Codec, $Level) {
    if ($null -eq $Level -or $Level -isnot [ValueType] -or $Level -le 0) { return $null }
    switch ($Codec) {
        'h264' { return "L$(Format-Number ($Level / 10) '0.0')" }
        'hevc' { return "L$(Format-Number ($Level / 30) '0.0')" }
        default { return "L$Level" }
    }
}

function Format-Utc($Value) {
    # ConvertFrom-Json turns ISO strings into DateTime; show them culture-independently.
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss', $Invariant) + ' UTC' }
    [string]$Value
}

function Get-EmojiLead([string]$Emoji) { if ($Emoji) { "$Emoji  " } else { '' } }

#endregion
#region Environment resolution ----------------------------------------------------------

function Resolve-Python {
    # Read (never execute) the Miniconda candidate list from the PowerShell 7 profile.
    $candidates = [System.Collections.Generic.List[string]]::new()
    try {
        $profileText = Get-Content -LiteralPath $PROFILE.CurrentUserCurrentHost -Raw -ErrorAction Stop
        $block = [regex]::Match($profileText, '(?s)\$condaRoot\s*=\s*Get-FirstExistingPath\s*@\((.*?)\)')
        if ($block.Success) { foreach ($m in [regex]::Matches($block.Groups[1].Value, "'([^']+)'")) { $candidates.Add($m.Groups[1].Value) } }
    } catch { }
    foreach ($fallback in 'E:\Compilers\miniconda', 'D:\Compilers\miniconda', 'C:\Compilers\miniconda') { $candidates.Add($fallback) }
    foreach ($root in $candidates) {
        # Path.Combine, not Join-Path: Join-Path throws when the drive does not exist (E: on LAPTOP).
        $python = [System.IO.Path]::Combine($root, 'python.exe')
        if (Test-Path -LiteralPath $python -PathType Leaf) { return $python }
    }
    throw 'Python was not found: none of the Miniconda roots listed in the PowerShell 7 profile exists.'
}

function Resolve-Environment {
    $tool = if ($ToolRoot) { $ToolRoot } else { Join-Path ([Environment]::GetFolderPath('Desktop')) 'Avidemux_Sample_Library_v0.1' }
    if (-not (Test-Path -LiteralPath (Join-Path $tool 'library.py') -PathType Leaf)) { throw "The Sample Library (library.py) was not found in: $tool" }
    $config = @{}
    $configPath = Join-Path $tool 'configuration.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) { $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable }
    $helperDir = if ($Helpers) { $Helpers } else { Get-Val $config 'helpers' }
    $libraryDir = if ($Library) { $Library } else { Get-Val $config 'library' }
    if (-not $libraryDir) { $libraryDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Avidemux Sample Library' }
    foreach ($helper in 'ffmpeg.exe', 'ffprobe.exe') {
        if (-not $helperDir -or -not (Test-Path -LiteralPath (Join-Path $helperDir $helper) -PathType Leaf)) { throw "$helper is missing from the helper folder: $helperDir" }
    }
    $bridge = Join-Path $PSScriptRoot 'sample_twin_bridge.py'
    if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw "The bridge script is missing: $bridge" }
    @{ Python = (Resolve-Python); Tool = $tool; Helpers = $helperDir; Library = $libraryDir; Bridge = $bridge }
}

#endregion
#region State and bridge jobs -----------------------------------------------------------

$S = @{
    Screen = 'analyzing'; Tab = 1; Scroll = (New-TuiScroll); Steps = @(); Started = [datetime]::Now
    Analysis = $null; Generated = $null; Error = $null; Cancelled = $false; Seconds = 15
    Toast = $null; ToastUntil = [datetime]::MinValue; ToastTone = 'Teal'; Job = $null; JobKind = $null
    JobOutcome = $null; ProfileTemp = $null; ErrorFrom = $null; Library = $null
}

function Show-Toast([string]$Text, [string]$Tone = 'Teal') { $S.Toast = $Text; $S.ToastTone = $Tone; $S.ToastUntil = [datetime]::Now.AddSeconds(6) }

function Start-BridgeJob([string]$Kind, [string[]]$Arguments) {
    $S.JobKind = $Kind; $S.JobOutcome = $null
    $S.Job = Start-TuiProcess $Ctx.Python (@('-B', $Ctx.Bridge, '--tool-root', $Ctx.Tool, '--helpers', $Ctx.Helpers) + $Arguments) @{ PYTHONIOENCODING = 'utf-8' }
}

function Start-Analysis {
    $S.Screen = 'analyzing'; $S.Error = $null; $S.Started = [datetime]::Now
    $S.Steps = New-TuiSteps @('Read technical properties', 'Sample video timing (first 12 s)', 'Check whether a twin can be generated')
    Set-TuiStep $S.Steps 0
    Start-BridgeJob 'analysis' @('analyze', $Path)
}

function Start-Generation {
    $S.ProfileTemp = Join-Path ([System.IO.Path]::GetTempPath()) "sample-twin-$([guid]::NewGuid().ToString('N')).json"
    $S.Analysis['profile'] | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $S.ProfileTemp -Encoding utf8NoBOM
    $S.Screen = 'generating'; $S.Error = $null; $S.Started = [datetime]::Now; $S.Scroll.Offset = 0
    $S.Steps = New-TuiSteps @('Plan the synthetic recipe', "Encode the twin ($($S.Seconds) s)", 'Verify codecs, frames, audio, strict decode', 'Write manifest and checksums')
    Set-TuiStep $S.Steps 0
    Start-BridgeJob 'generate' @('generate', $S.ProfileTemp, $S.Library, '--seconds', [string]$S.Seconds)
}

function Update-FromProgress([string]$Text) {
    if ($S.Screen -eq 'analyzing') {
        if ($Text -like 'Reading*') { Set-TuiStep $S.Steps 0 } elseif ($Text -like 'Sampling*') { Set-TuiStep $S.Steps 1 } elseif ($Text -like 'Checking*') { Set-TuiStep $S.Steps 2 }
    } elseif ($S.Screen -eq 'generating') {
        if ($Text -like 'Encoding*') { Set-TuiStep $S.Steps 1 } elseif ($Text -like 'Verifying*') { Set-TuiStep $S.Steps 2 } elseif ($Text -like 'Complete*') { Set-TuiStep $S.Steps 3 }
    }
}

function Remove-ProfileTemp {
    if ($S.ProfileTemp -and (Test-Path -LiteralPath $S.ProfileTemp)) { Remove-Item -LiteralPath $S.ProfileTemp -Force -ErrorAction SilentlyContinue }
    $S.ProfileTemp = $null
}

function Set-ErrorState([string]$Message, [bool]$Cancelled) {
    Complete-TuiSteps $S.Steps 'failed'
    $S.Error = ConvertTo-TuiSafeText $Message; $S.Cancelled = $Cancelled
    $S.ErrorFrom = $S.Screen; $S.Screen = 'error'; $S.Scroll.Offset = 0
    Remove-ProfileTemp
}

function Update-Job {
    if ($null -eq $S.Job) { return $false }
    $changed = $false
    foreach ($line in (Receive-TuiProcessLines $S.Job)) {
        if (-not $line.Trim()) { continue }
        $changed = $true
        try { $evt = $line | ConvertFrom-Json -AsHashtable } catch { $evt = @{ event = 'progress'; text = $line } }
        switch ($evt['event']) {
            'progress' { Update-FromProgress ([string]$evt['text']) }
            'result' {
                $S.JobOutcome = $evt
                Complete-TuiSteps $S.Steps
                if ($evt['kind'] -eq 'analysis') {
                    $S.Analysis = $evt
                    $rec = Get-Val $evt 'support.plan.recommended_seconds'
                    $S.Seconds = if ($rec) { [int]$rec } else { 15 }
                    $S.Screen = 'overview'; $S.Tab = 1; $S.Scroll.Offset = 0
                } else {
                    $S.Generated = $evt; $S.Screen = 'result'; $S.Scroll.Offset = 0
                    Remove-ProfileTemp
                }
            }
            'error' { $S.JobOutcome = $evt; Set-ErrorState ([string]$evt['message']) ([bool]$evt['cancelled']) }
        }
    }
    if ($S.Job.Done) {
        if ($null -eq $S.JobOutcome) {
            $tail = (($S.Job.StdErr -split "\r?\n") | Where-Object { $_ } | Select-Object -Last 6) -join "`n"
            Set-ErrorState "The helper ended unexpectedly (exit $($S.Job.ExitCode)).`n$tail" $false
        }
        $S.Job = $null; $changed = $true
    }
    $changed
}

#endregion
#region Screens -------------------------------------------------------------------------

function Get-ProgressBody([int]$Width, [string]$Title, [string]$Note) {
    $cardWidth = [Math]::Min($Width, 78)
    $body = [System.Collections.Generic.List[string]]::new()
    $body.Add('')
    foreach ($l in (TuiSteps $S.Steps)) { $body.Add("  $l") }
    $body.Add('')
    $body.Add("  $(TuiPaint Muted 'Elapsed') $(TuiBold Teal (TuiElapsed ([datetime]::Now - $S.Started)))")
    if ($Note) { foreach ($l in (TuiWrap $Note ($cardWidth - 8))) { $body.Add("  $(TuiPaint Dim $l)") } }
    $body.Add('')
    $pad = ' ' * [Math]::Max(0, [int](($Width - $cardWidth) / 2))
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('')
    foreach ($l in (TuiCard $Title $G.Wand 'Violet' $body.ToArray() $cardWidth)) { $out.Add($pad + $l) }
    , $out.ToArray()
}

function Get-TypeBar($Types, [int]$Width) {
    $segments = [System.Collections.Generic.List[object]]::new()
    $known = 0; $total = 0
    foreach ($k in $Types.Keys) { $total += [int]$Types[$k] }
    foreach ($pair in @(@('I', 'Amber'), @('P', 'Teal'), @('B', 'Violet'))) {
        $n = if ($Types.Contains($pair[0])) { [int]$Types[$pair[0]] } else { 0 }
        $known += $n
        $segments.Add(@{ Label = $pair[0]; Count = $n; Color = $pair[1] })
    }
    if ($known -lt $total) { $segments.Add(@{ Label = 'other'; Count = $total - $known; Color = 'Dim' }) }
    TuiStackBar $segments.ToArray() $Width
}

function Get-GopStrip($Intervals, [int]$Width) {
    $values = @($Intervals | ForEach-Object { [int]$_ })
    if ($values.Count -eq 0) { return (TuiPaint Amber 'one keyframe in the sample: 2-second GOP will be assumed') }
    $sum = ($values | Measure-Object -Sum).Sum
    $sb = ''
    $used = 0
    foreach ($gop in $values) {
        if ($used -ge $Width) { break }
        $cells = [Math]::Max(2, [int][Math]::Round($Width * $gop / $sum))
        $cells = [Math]::Min($cells, $Width - $used)
        $sb += (TuiPaint Amber $G.Tick) + (TuiPaint Teal ($G.Bar * [Math]::Max(0, $cells - 1)))
        $used += $cells
    }
    if ($used -lt $Width) { $sb += TuiPaint Amber $G.Tick }
    $sb
}

function Get-OverviewBody([int]$Width) {
    $a = $S.Analysis
    $p = $a['profile']; $v = $p['video']; $obs = $p['timing_observation']
    $ok = [bool](Get-Val $a 'support.ok')
    $plan = Get-Val $a 'support.plan'
    $reasonText = ConvertTo-TuiSafeText ([string](Get-Val $a 'support.reason'))
    $out = [System.Collections.Generic.List[string]]::new()

    if ($ok) {
        $out.Add((TuiBanner Green "  $(Get-EmojiLead $TuiEmoji.Ready)TWIN READY   $($G.Sep)  this format can be synthesized as a content-free twin" $Width))
    } else {
        $out.Add((TuiBanner Amber "  $(Get-EmojiLead $TuiEmoji.Receipt)PROFILE ONLY   $($G.Sep)  $((TuiWrap $reasonText 400)[0])" $Width))
    }
    $out.Add('')

    $twoColumns = $Width -ge 104
    $colWidth = if ($twoColumns) { [int](($Width - 2) / 2) } else { $Width }
    $inner = $colWidth - 4

    # Video
    $codec = [string]$v['codec_name']
    $head = @((TuiBold Blue $codec.ToUpperInvariant()), (TuiPaint Text ([string]$v['profile'])), (TuiPaint Muted (Format-Level $codec $v['level']))) | Where-Object { TuiWidth $_ }
    $sar = [string]$v['sample_aspect_ratio']
    $sarText = if ($sar -and $sar -notin '1:1', '0:1') { TuiPaint Amber "  SAR $sar" } elseif ($sar) { TuiPaint Dim "  SAR $sar" } else { '' }
    $fps = Format-Fps $v['avg_frame_rate']
    $rfps = Format-Fps $v['r_frame_rate']
    $fpsText = (TuiBold Text "$fps fps") + $(if ($rfps -ne $fps -and $rfps -ne '?') { TuiPaint Muted "  (nominal $rfps)" } else { '' })
    $colorTags = @($v['color_space'], $v['color_transfer'], $v['color_primaries']) | Where-Object { $_ }
    $range = if ($v['color_range']) { TuiPaint Muted "  $($v['color_range']) range" } else { '' }
    $interlaced = [bool]$obs['interlaced'] -or ($v['field_order'] -and $v['field_order'] -notin 'progressive', 'unknown')
    $scan = if ($interlaced) { TuiPaint Amber "interlaced ($($v['field_order']))" } else { TuiPaint Text 'progressive' }
    $videoBody = @(
        ($head -join (TuiPaint Dim " $($G.Sep) ")),
        (TuiKV 'Size' ((TuiBold Text "$($v['width']) × $($v['height'])") + $sarText)),
        (TuiKV 'Frame rate' $fpsText),
        (TuiKV 'Pixels' ((TuiPaint Text ([string]$v['pix_fmt'])) + $range)),
        (TuiKV 'Color' $(if ($colorTags) { TuiPaint Text ($colorTags -join ' / ') } else { TuiPaint Dim 'untagged' })),
        (TuiKV 'Bitrate' $(if (Format-Bitrate $v['bit_rate']) { TuiPaint Text (Format-Bitrate $v['bit_rate']) } else { TuiPaint Dim 'not reported' })),
        (TuiKV 'Scan' $scan)
    )
    $videoCard = TuiCard 'Video' $G.Video 'Blue' $videoBody $colWidth

    # Audio
    $audioBody = [System.Collections.Generic.List[string]]::new()
    $tracks = @($p['audio'])
    if ($tracks.Count -eq 0 -or $null -eq $tracks[0]) { $audioBody.Add((TuiPaint Dim 'no audio tracks')) }
    else {
        $n = 0
        foreach ($t in $tracks) {
            $n++
            $bits = @(
                (TuiBold Pink ([string]$t['codec_name'])),
                $(if ($t['profile']) { TuiPaint Muted ([string]$t['profile']) }),
                (TuiPaint Text "$(Format-Number (([double]$t['sample_rate']) / 1000) '0.###') kHz"),
                (TuiPaint Text ([string]$t['channel_layout'])),
                $(if (Format-Bitrate $t['bit_rate']) { TuiPaint Muted (Format-Bitrate $t['bit_rate']) })
            ) | Where-Object { $_ }
            $audioBody.Add("$(TuiPaint Dim "#$n")  " + ($bits -join '  '))
        }
    }
    $audioCard = TuiCard "Audio $(TuiPaint Dim "($($tracks.Count))")" $G.Audio 'Pink' $audioBody.ToArray() $colWidth

    # Container
    $bytes = [double](Get-Val $p 'reference_identity.bytes')
    $excluded = [int]$p['excluded_stream_count']
    $containerBody = @(
        (TuiKV 'Format' (TuiBold Violet ([string]$p['container']))),
        (TuiKV 'File size' (TuiPaint Text (Format-Bytes $bytes))),
        (TuiKV 'Excluded' $(if ($excluded) { TuiPaint Amber "$excluded subtitle/attachment/cover stream(s)" } else { TuiPaint Dim 'nothing' }))
    )
    $containerCard = TuiCard 'Container' $G.Box 'Violet' $containerBody $colWidth

    # Timing
    $typeBar = Get-TypeBar $obs['picture_types'] ([Math]::Max(10, $inner - 11))
    $gaps = @($obs['keyframe_intervals_frames'])
    $fpsValue = ConvertTo-Ratio $v['avg_frame_rate']
    if ($gaps.Count -gt 0 -and $null -ne $gaps[0]) {
        $sorted = @($gaps | ForEach-Object { [int]$_ } | Sort-Object)
        $gopMedian = $sorted[[int][Math]::Floor(($sorted.Count - 1) / 2)]
        $gopText = (TuiBold Text "$gopMedian frames") + $(if ($fpsValue) { TuiPaint Muted "  $(Format-Number ($gopMedian / $fpsValue) '0.0#') s" } else { '' })
        if ($sorted[0] -ne $sorted[-1]) { $gopText += TuiPaint Amber "  varies $($sorted[0])–$($sorted[-1])" }
    } else { $gaps = @(); $gopText = TuiPaint Amber 'unknown (single keyframe)' }
    $median = [double]$obs['median_delta']; $low = [double]$obs['min_delta']; $high = [double]$obs['max_delta']
    $jitter = ($high - $low) * 1000
    $cadenceTone = if ($jitter -lt 0.05) { 'Green' } else { 'Amber' }
    $timingBody = @(
        (TuiKV 'Sampled' ((TuiBold Text "$($obs['frames']) frames") + (TuiPaint Muted "  first $($obs['sample_seconds_requested']) s"))),
        (TuiKV 'Pictures' $typeBar[0]),
        ((' ' * 11) + $typeBar[1]),
        (TuiKV 'GOP' $gopText),
        (TuiKV 'Keyframes' (Get-GopStrip $gaps ([Math]::Max(10, $inner - 11)))),
        (TuiKV 'B-run' ((TuiPaint Text "max $($obs['max_consecutive_b_frames'])") + (TuiPaint Muted ' consecutive B'))),
        (TuiKV 'Cadence' ((TuiPaint Text "$(Format-Number ($median * 1000) '0.000') ms") + (TuiPaint $cadenceTone "  jitter $(Format-Number $jitter '0.000') ms"))),
        (TuiKV 'Timestamps' $(if ($obs['all_pts_present']) { TuiPaint Green 'all present' } else { TuiPaint Red 'missing PTS' }))
    )
    $timingCard = TuiCard 'Timing' $G.Clock 'Amber' $timingBody $colWidth

    if ($twoColumns) {
        $left = @($videoCard) + @($audioCard)
        $right = @($containerCard) + @($timingCard)
        foreach ($l in (TuiColumns $left $colWidth $right ($Width - $colWidth - 2))) { $out.Add($l) }
    } else {
        foreach ($card in @($videoCard, $audioCard, $containerCard, $timingCard)) { foreach ($l in $card) { $out.Add($l) } }
    }

    # Twin plan, or why only a profile can be saved
    if ($ok) {
        $rate = Format-Bitrate $plan['video_bitrate_target']
        $planBody = @(
            ((TuiKV 'GOP target' (TuiBold Text "$($plan['gop'])")) + '     ' + (TuiKV 'B-frames' (TuiBold Text "$($plan['bframes'])") 10) + '     ' + (TuiKV 'Video rate' $(if ($rate) { TuiPaint Text "$rate average" } else { TuiPaint Muted 'quality default' }) 12)),
            (TuiKV 'Encoders' (TuiPaint Teal (@($plan['encoders']) -join ' + '))),
            '',
            (TuiKV 'Duration' ("$(TuiPaint Teal $G.Left) $(TuiBold Text "$($S.Seconds) s") $(TuiPaint Teal $G.Right)" + (TuiPaint Muted "     recommended $($plan['recommended_seconds']) s  $($G.Sep)  2–120 s  $($G.Sep)  $($G.LeftArrow)/$($G.RightArrow) to change")))
        )
        $planCard = TuiCard 'Twin recipe' $G.Wand 'Teal' $planBody $Width
    } else {
        $why = [System.Collections.Generic.List[string]]::new()
        foreach ($l in (TuiWrap $reasonText ($Width - 6))) { $why.Add((TuiPaint Amber $l)) }
        $why.Add('')
        foreach ($l in (TuiWrap 'Save the technical profile (S) to keep this case: it holds technical facts only and can be turned into a twin when the library supports this format.' ($Width - 6))) { $why.Add((TuiPaint Muted $l)) }
        $planCard = TuiCard 'Why only a profile' $G.Notes 'Amber' $why.ToArray() $Width
    }
    $out.Add('')
    foreach ($l in $planCard) { $out.Add($l) }
    , $out.ToArray()
}

function Get-DetailsBody([int]$Width) {
    $a = $S.Analysis; $p = $a['profile']
    $out = [System.Collections.Generic.List[string]]::new()
    $textWidth = $Width - 8
    $sections = @()
    $limits = @($p['limitations'])
    $notes = @(Get-Val $a 'support.plan.notes') | Where-Object { $_ -and $_ -notin $limits }
    if ($notes) { $sections += , @('Recipe notes', 'Teal', @($notes)) }
    $sections += , @('Library limitations', 'Amber', $limits)
    foreach ($section in $sections) {
        $body = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $section[2]) {
            $wrapped = TuiWrap ([string]$item) $textWidth
            $body.Add("$(TuiPaint $section[1] $G.Bullet) $(TuiPaint Text $wrapped[0])")
            for ($i = 1; $i -lt $wrapped.Count; $i++) { $body.Add("  $(TuiPaint Text $wrapped[$i])") }
        }
        foreach ($l in (TuiCard $section[0] $G.Notes $section[1] $body.ToArray() $Width)) { $out.Add($l) }
        $out.Add('')
    }
    $hash = [string](Get-Val $p 'reference_identity.first_last_1MiB_sha256')
    $identity = @(
        (TuiKV 'Bytes' (TuiPaint Text ([double](Get-Val $p 'reference_identity.bytes')).ToString('N0', $Invariant)) 16),
        (TuiKV 'Edge SHA256' (TuiPaint Muted $hash) 16),
        (TuiKV 'Profile' (TuiPaint Muted "schema $($p['schema'])  $($G.Sep)  library $($a['version'])  $($G.Sep)  $(Format-Utc $p['created_utc'])") 16),
        '',
        (TuiPaint Dim 'Only allowlisted technical fields are kept: no path, name, title, tags, pictures or sound.')
    )
    foreach ($l in (TuiCard 'Reference identity' $G.Flask 'Violet' $identity $Width)) { $out.Add($l) }
    , $out.ToArray()
}

function Get-ResultBody([int]$Width) {
    $gen = $S.Generated; $m = $gen['manifest']
    $status = [string]$m['status']
    $out = [System.Collections.Generic.List[string]]::new()
    switch ($status) {
        'verified_core' { $out.Add((TuiBanner Green "  $(Get-EmojiLead $TuiEmoji.Ready)VERIFIED CORE   $($G.Sep)  every required media property matches the reference profile" $Width)) }
        'mismatch' { $out.Add((TuiBanner Amber "  $(Get-EmojiLead $TuiEmoji.Mismatch)MISMATCH   $($G.Sep)  the twin was generated but a required property differs" $Width)) }
        default { $out.Add((TuiBanner Red "  $(Get-EmojiLead $TuiEmoji.Failed)$($status.ToUpperInvariant())" $Width)) }
    }
    $out.Add('')
    $folder = [string]$gen['folder']
    $media = Join-Path $folder ([string]$m['media'])
    $size = if (Test-Path -LiteralPath $media) { Format-Bytes (Get-Item -LiteralPath $media).Length } else { '?' }
    $caseBody = @(
        (TuiKV 'Case' (TuiBold Teal ([string]$m['id'])) 9),
        (TuiKV 'Media' ((TuiPaint Text ([string]$m['media'])) + (TuiPaint Muted "  $size  $($G.Sep)  $($m['plan']['duration']) s")) 9),
        (TuiKV 'SHA256' (TuiPaint Muted ([string]$m['media_sha256'])) 9),
        (TuiKV 'Folder' (TuiPaint Muted (ConvertTo-TuiSafeText $folder -SingleLine)) 9)
    )
    foreach ($l in (TuiCard 'Sample case' $G.Folder 'Teal' $caseBody $Width)) { $out.Add($l) }
    $out.Add('')

    $checks = @(Get-Val $m 'verification.checks')
    $propWidth = [Math]::Min(40, 2 + (@($checks | ForEach-Object { ([string]$_['property']).Length }) + 8 | Measure-Object -Maximum).Maximum)
    $columns = @(@{ Title = ''; Width = 1 }, @{ Title = 'property'; Width = $propWidth }, @{ Title = 'expected (reference)'; Width = 0 }, @{ Title = 'actual (twin)'; Width = 0 })
    $table = [System.Collections.Generic.List[string]]::new()
    $first = $true
    foreach ($group in @(@($true, 'Required'), @($false, 'Informational'))) {
        $rows = @($checks | Where-Object { [bool]$_['required'] -eq $group[0] })
        if ($rows.Count -eq 0) { continue }
        $matched = @($rows | Where-Object { $_['match'] }).Count
        # Rows are arrays: collect them in a list so a single row is not unrolled.
        $cells = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $rows) {
            $icon = if ($row['match']) { TuiPaint Green $G.Ok } elseif ($row['required']) { TuiPaint Red $G.Bad } else { TuiPaint Amber $G.Warn }
            $tone = if ($row['match']) { 'Text' } elseif ($row['required']) { 'Red' } else { 'Amber' }
            $expected = if ($null -eq $row['expected']) { '—' } else { [string]$row['expected'] }
            $actual = if ($null -eq $row['actual']) { '—' } else { [string]$row['actual'] }
            $cells.Add(@($icon, (TuiPaint $tone ([string]$row['property'])), (TuiPaint Muted $expected), (TuiPaint $tone $actual)))
        }
        $lines = TuiTable $columns $cells.ToArray() ($Width - 4)
        if ($first) { $table.Add($lines[0]); $table.Add(''); $first = $false }
        $table.Add((TuiBold Muted "$($group[1].ToUpperInvariant())") + (TuiPaint Dim "  $matched/$($rows.Count) match"))
        for ($i = 1; $i -lt $lines.Count; $i++) { $table.Add($lines[$i]) }
        $table.Add('')
    }
    $table.Add((TuiPaint Dim ([string](Get-Val $m 'verification.meaning'))))
    foreach ($l in (TuiCard 'Verification' $G.Flask 'Violet' $table.ToArray() $Width)) { $out.Add($l) }
    , $out.ToArray()
}

function Get-ErrorBody([int]$Width) {
    $title = if ($S.Cancelled) { 'Cancelled' } else { 'Something went wrong' }
    $tone = if ($S.Cancelled) { 'Amber' } else { 'Red' }
    $emoji = if ($S.Cancelled) { $TuiEmoji.Stop } else { $TuiEmoji.Failed }
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add((TuiBanner $tone "  $(Get-EmojiLead $emoji)$($title.ToUpperInvariant())" $Width))
    $out.Add('')
    $body = [System.Collections.Generic.List[string]]::new()
    foreach ($l in (TuiWrap ([string]$S.Error) ($Width - 6))) { $body.Add((TuiPaint Text $l)) }
    if ($S.ErrorFrom -eq 'generating') {
        $body.Add('')
        $body.Add((TuiPaint Muted 'An incomplete case folder is kept and marked failed or cancelled; it is never shown as verified.'))
    }
    foreach ($l in (TuiCard 'Details' $G.Notes $tone $body.ToArray() $Width)) { $out.Add($l) }
    , $out.ToArray()
}

function Get-Chips {
    switch ($S.Screen) {
        { $_ -in 'analyzing', 'generating' } { return , @((TuiChip 'Esc' 'Cancel' 'Red')) }
        'overview' {
            $ok = [bool](Get-Val $S.Analysis 'support.ok')
            return , @((TuiChip 'G' 'Generate twin' 'Green' -Disabled:(-not $ok)), (TuiChip "$($G.LeftArrow)$($G.RightArrow)" 'Duration' 'Teal' -Disabled:(-not $ok)),
                (TuiChip 'S' 'Save profile' 'Violet'), (TuiChip 'O' 'Library' 'Blue'), (TuiChip 'Tab' $(if ($S.Tab -eq 1) { 'Details' } else { 'Overview' }) 'Pink'), (TuiChip 'Q' 'Quit' 'Red'))
        }
        'result' { return , @((TuiChip 'O' 'Open case' 'Blue'), (TuiChip 'P' 'Play twin' 'Green'), (TuiChip 'B' 'Back' 'Violet'), (TuiChip 'Q' 'Quit' 'Red')) }
        'error' {
            if ($S.Analysis) { return , @((TuiChip 'B' 'Back' 'Violet'), (TuiChip 'Q' 'Quit' 'Red')) }
            if ($S.ErrorFrom -eq 'analyzing') { return , @((TuiChip 'R' 'Retry' 'Green'), (TuiChip 'Q' 'Quit' 'Red')) }
        }
    }
    , @((TuiChip 'Q' 'Quit' 'Red'))
}

function Get-Header([int]$Width) {
    $name = if ($Path) { ConvertTo-TuiSafeText ([System.IO.Path]::GetFileName($Path)) -SingleLine } else { 'no file selected' }
    $title = "  $($G.Flask)  SAMPLE TWIN   content-free problem twins for Smart Cut and seeking"
    $right = "Sample Library $(if ($S.Analysis) { $S.Analysis['version'] } else { '0.1' })  "
    $gap = $Width - (TuiWidth $title) - (TuiWidth $right)
    if ($gap -lt 2) { $title = "  $($G.Flask)  SAMPLE TWIN"; $gap = $Width - (TuiWidth $title) - (TuiWidth $right) }
    $barText = if ($gap -ge 2) { $title + (' ' * $gap) + $right } else { $title }
    $lead = if ($TuiEmoji.Film) { "$($TuiEmoji.Film) " } else { '' }
    $file = " $lead$(TuiBold Text $name)"
    if ($S.Screen -eq 'overview') {
        $tab1 = if ($S.Tab -eq 1) { TuiBold Pink "$($G.Dot) Overview" } else { TuiPaint Dim "$($G.Pending) Overview" }
        $tab2 = if ($S.Tab -eq 2) { TuiBold Pink "$($G.Dot) Details" } else { TuiPaint Dim "$($G.Pending) Details" }
        $tabs = "$tab1   $tab2 "
        $space = $Width - (TuiWidth $file) - (TuiWidth $tabs)
        if ($space -ge 2) { $file = $file + (' ' * $space) + $tabs }
    }
    , @((TuiGradient $barText $Width), $file, '')
}

function Get-Screen([int]$Width, [int]$Height) {
    $bodyWidth = $Width - 4
    $body = switch ($S.Screen) {
        'analyzing' { Get-ProgressBody $bodyWidth 'Analyzing the reference' 'Only technical properties are read. Pictures and sound are never used or stored.' }
        'generating' { Get-ProgressBody $bodyWidth 'Generating the twin' 'FFmpeg runs quietly, so no percentage is available. Esc cancels; the case is then kept and marked cancelled.' }
        'overview' { if ($S.Tab -eq 1) { Get-OverviewBody $bodyWidth } else { Get-DetailsBody $bodyWidth } }
        'result' { Get-ResultBody $bodyWidth }
        'error' { Get-ErrorBody $bodyWidth }
    }
    $status = if ($S.Toast -and [datetime]::Now -lt $S.ToastUntil) { TuiPaint $S.ToastTone $S.Toast } else { '' }
    New-TuiFrame -Width $Width -Height $Height -Header (Get-Header $Width) -Body $body -Chips (Get-Chips) -Status $status -Scroll $S.Scroll -MinHeight 18
}

#endregion
#region Actions -------------------------------------------------------------------------

function Save-Profile {
    $p = $S.Analysis['profile']
    $folder = Join-Path $S.Library '_profiles'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $stem = 'profile-{0}-{1}-{2}' -f [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss', $Invariant), $p['video']['codec_name'], $p['container']
    $target = Join-Path $folder "$stem.json"
    $n = 1
    while (Test-Path -LiteralPath $target) { $n++; $target = Join-Path $folder "$stem-$n.json" }
    $p | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $target -Encoding utf8NoBOM
    Show-Toast "$($G.Ok) Profile saved: $target"
}

function Open-Folder([string]$Folder) {
    if (Test-Path -LiteralPath $Folder -PathType Container) { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Folder`""; Show-Toast "$($G.Folder) Opened $Folder" 'Blue' }
    else { Show-Toast "Folder not found: $Folder" 'Amber' }
}

# Returns $false to leave the tool.
function Invoke-Key([System.ConsoleKeyInfo]$Key) {
    $char = [char]::ToUpperInvariant($Key.KeyChar)
    $quit = Test-TuiQuitKey $Key
    switch ($S.Screen) {
        { $_ -in 'analyzing', 'generating' } {
            if ($quit) { Send-TuiProcessLine $S.Job 'cancel'; Show-Toast 'Cancelling…' 'Amber' }
            return $true
        }
        'overview' {
            $ok = [bool](Get-Val $S.Analysis 'support.ok')
            if ($quit) { return $false }
            if ($Key.Key -eq 'Tab' -or $char -eq '1' -or $char -eq '2') {
                $S.Tab = if ($char -eq '1') { 1 } elseif ($char -eq '2') { 2 } else { 3 - $S.Tab }
                $S.Scroll.Offset = 0
                return $true
            }
            if ($ok -and ($char -eq 'G' -or $Key.Key -eq 'Enter')) { Start-Generation; return $true }
            if ($ok -and $Key.Key -in 'RightArrow', 'Add', 'OemPlus') { $S.Seconds = [Math]::Min(120, $(if ($S.Seconds -lt 10) { $S.Seconds + 1 } else { $S.Seconds + 5 })); return $true }
            if ($ok -and $Key.Key -in 'LeftArrow', 'Subtract', 'OemMinus') { $S.Seconds = [Math]::Max(2, $(if ($S.Seconds -le 10) { $S.Seconds - 1 } else { $S.Seconds - 5 })); return $true }
            if ($char -eq 'S') { Save-Profile; return $true }
            if ($char -eq 'O') { Open-Folder $S.Library; return $true }
            if ($char -eq 'G') { Show-Toast 'This format cannot be synthesized yet; S saves its technical profile.' 'Amber'; return $true }
        }
        'result' {
            if ($quit) { return $false }
            if ($char -eq 'O') { Open-Folder ([string]$S.Generated['folder']); return $true }
            if ($char -eq 'P') {
                $media = Join-Path ([string]$S.Generated['folder']) ([string]$S.Generated['manifest']['media'])
                if (Test-Path -LiteralPath $media) { Start-Process -FilePath $media; Show-Toast "$($G.Ok) Opened the twin in the default player" }
                return $true
            }
            if ($char -eq 'B' -or $Key.Key -eq 'Backspace') { $S.Screen = 'overview'; $S.Scroll.Offset = 0; return $true }
        }
        'error' {
            if ($quit) { return $false }
            if (($char -eq 'B' -or $Key.Key -eq 'Backspace') -and $S.Analysis) { $S.Screen = 'overview'; $S.Scroll.Offset = 0; return $true }
            if ($char -eq 'R' -and -not $S.Analysis -and $S.ErrorFrom -eq 'analyzing') { Start-Analysis; return $true }
        }
    }
    [void](Invoke-TuiScrollKey $Key $S.Scroll)
    $true
}

#endregion
#region Main ----------------------------------------------------------------------------

function Wait-JobSynchronously { while ($S.Job) { [void](Update-Job); if ($S.Job) { Start-Sleep -Milliseconds 50 } } }

try {
    $Ctx = Resolve-Environment
    $S.Library = $Ctx.Library
} catch {
    $Ctx = $null
    $S.Error = ConvertTo-TuiSafeText $_.Exception.Message; $S.Screen = 'error'; $S.ErrorFrom = 'setup'
}
if ($Ctx -and $Path) {
    try { $Path = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath } catch { }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $S.Error = "The selected video does not exist: $Path"; $S.Screen = 'error'; $S.ErrorFrom = 'setup' }
} elseif ($Ctx -and -not $Path) {
    $S.Error = 'No video was selected. Right-click a video and choose Sample Twin, or pass the file path as the first argument.'
    $S.Screen = 'error'; $S.ErrorFrom = 'setup'
}

if ($PreviewScreen) {
    # Test hook: render one screen as plain ANSI lines (no alternate screen, no input).
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    if ($S.Screen -ne 'error') {
        Start-Analysis
        if ($PreviewScreen -eq 'analyzing') { [void](Update-Job) } else { Wait-JobSynchronously }
        if ($PreviewScreen -eq 'details') { $S.Tab = 2 }
        if ($PreviewScreen -in 'generating', 'result' -and $S.Screen -eq 'overview') {
            if (-not (Get-Val $S.Analysis 'support.ok')) { throw 'This reference cannot be synthesized; no generation preview.' }
            Start-Generation
            if ($PreviewScreen -eq 'generating') { Start-Sleep -Milliseconds 1500; [void](Update-Job) } else { Wait-JobSynchronously }
        }
    }
    if ($PreviewTiming) {
        # Frame build cost while resizing: alternate widths so nothing can be reused.
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt 20; $i++) { [void](Get-Screen ($PreviewWidth - ($i % 2)) $PreviewHeight) }
        [Console]::Error.WriteLine("frame build: $([Math]::Round($watch.Elapsed.TotalMilliseconds / 20, 1)) ms")
    }
    [Console]::Out.Write(((Get-Screen $PreviewWidth $PreviewHeight) -join "`n") + "`n")
    if ($S.Job) { Stop-TuiProcess $S.Job 'cancel' }
    Remove-ProfileTemp
    exit 0
}

$failure = $null
try {
    Start-TuiSession -Title 'Sample Twin'
    if ($S.Screen -eq 'analyzing' -and $Ctx) { Start-Analysis }
    Invoke-TuiLoop -Render { param($w, $h) Get-Screen $w $h } -OnKey { param($key) Invoke-Key $key } -OnPoll {
        $changed = Update-Job
        if ($S.Toast -and [datetime]::Now -ge $S.ToastUntil) { $S.Toast = $null; $changed = $true }
        $changed
    } -Animate { $null -ne $S.Job }
} catch {
    $failure = $_
} finally {
    if ($S.Job) { Stop-TuiProcess $S.Job 'cancel' }
    Remove-ProfileTemp
    Stop-TuiSession
}
if ($failure) {
    Write-Host "Sample Twin stopped: $($failure.Exception.Message)" -ForegroundColor Red
    Write-Host $failure.ScriptStackTrace -ForegroundColor DarkGray
    Read-Host 'Press Enter to close'
    exit 1
}
exit 0

#endregion
