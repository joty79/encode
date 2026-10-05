#Requires -Version 7.2
<#
.SYNOPSIS
    ClaudeTui: Claude's PowerShell 7 TUI template for Windows Terminal.

.DESCRIPTION
    Canonical source: D:\Users\joty79\scripts\ClaudeTui\ClaudeTui.psm1 (repo joty79/ClaudeTui)
    Projects pin a copy (for example lib\ClaudeTui.psm1) and record the version below.

    Two layers:
      1. Engine (mechanics proven in real Windows Terminal on 2026-10-04, Sample Twin):
         - alternate screen, hidden cursor, auto-wrap OFF for the whole session;
         - the screen is cleared once at start, never again: every frame rewrites every
           cell (lines exactly the window width, exactly the window height);
         - each frame is one write wrapped in synchronized output (DEC 2026);
         - the hidden cursor is parked at 1;1 after each frame (WT keeps the cursor row
           visible on shrink; a cursor on the last row pushes the header off-screen);
         - redraw waits until the size is stable for SettleMilliseconds, and a frame is
           discarded if the size changed while it was being built;
         - resize is checked before every key; one key -> one state change -> one frame;
         - Ctrl+C is read as a key so cleanup always runs; host restored in finally.
      2. Design language: truecolor gradient header, rounded cards with icon titles,
         full-width status banners, powerline key chips, spinner step lists, stacked
         bars, responsive two-column layout, wrapped footer, scroll position in the rule.

    Glyph modes: Nerd (Windows Terminal + Nerd Font, default inside WT), Unicode (box
    drawing/blocks/arrows only, default elsewhere), Ascii. Override with
    Initialize-TuiGlyphs -Mode, $env:CLAUDE_TUI_GLYPHS = nerd|unicode|ascii, or the
    shared $env:POWERSHELL_TUI_ASCII=1.

    Read README.md next to this file for the contract, lessons and a usage example.
#>

$script:TuiVersion = '1.0.0'
$E = [char]27
$script:Reset = "$E[0m"
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

#region Theme, glyphs, icons ------------------------------------------------------------

# Exported and mutated in place (never reassigned) so importers always see current values.
$TuiTheme = @{
    Text = '#E5E7EB'; Muted = '#9CA3AF'; Dim = '#6B7280'; Border = '#4B5563'; Ink = '#0F172A'
    Violet = '#A78BFA'; Teal = '#2DD4BF'; Pink = '#F472B6'; Amber = '#FBBF24'
    Green = '#4ADE80'; Red = '#F87171'; Blue = '#60A5FA'; Slate = '#334155'
    GradFrom = '#6D28D9'; GradTo = '#0E7490'
}
$TuiGlyph = @{}
$TuiEmoji = @{}
$script:TuiGlyphMode = $null
$script:ColorCache = @{}

function U([int]$CodePoint) { [char]::ConvertFromUtf32($CodePoint) }

# Name = Nerd glyph, Unicode fallback, ASCII fallback.
$script:GlyphTable = [ordered]@{
    TL = @('╭', '╭', '+'); TR = @('╮', '╮', '+'); BL = @('╰', '╰', '+'); BR = @('╯', '╯', '+')
    H = @('─', '─', '-'); V = @('│', '│', '|'); Block = @('█', '█', '#'); Shade = @('░', '░', '.')
    Ok = @('✓', '✓', 'v'); Bad = @('✗', '✗', 'x'); Warn = @('≈', '≈', '~'); Dot = @('●', '●', '*')
    Pending = @('○', '○', 'o'); Left = @('◀', '◀', '<'); Right = @('▶', '▶', '>')
    Up = @('↑', '↑', '^'); Down = @('↓', '↓', 'v'); LeftArrow = @('←', '←', '<'); RightArrow = @('→', '→', '>')
    Bullet = @('•', '•', '-'); Tick = @('┃', '┃', '|'); Bar = @('━', '━', '='); Sep = @('·', '·', '|')
    Ellipsis = @('…', '…', '~')
    CapL = @((U 0xE0B6), '', ''); CapR = @((U 0xE0B4), '', '')
    # Icons (Nerd Font Awesome range, single cell). Fallbacks stay short and recognizable.
    Flask = @((U 0xF0C3), '◆', '*'); Video = @((U 0xF008), '▶', 'V'); Audio = @((U 0xF028), '♪', 'A')
    Box = @((U 0xF1B2), '■', 'C'); Clock = @((U 0xF017), '◷', 'T'); Wand = @((U 0xF0D0), '✦', '+')
    Notes = @((U 0xF15C), '≡', 'N'); Folder = @((U 0xF07C), '▤', 'F'); Gear = @((U 0xF013), '⚙', '@')
    Search = @((U 0xF002), '⌕', '?'); Bolt = @((U 0xF0E7), '↯', '!'); Info = @((U 0xF05A), 'ℹ', 'i')
    Alert = @((U 0xF071), '▲', '!'); Play = @((U 0xF04B), '▶', '>'); Save = @((U 0xF0C7), '▣', 'S')
    Shield = @((U 0xF132), '◈', '#'); Chart = @((U 0xF080), '▥', '#'); List = @((U 0xF03A), '≣', '=')
    Terminal = @((U 0xF120), '›', '>'); Cube = @((U 0xF1B2), '■', '#'); Check = @((U 0xF00C), '✓', 'v')
}
$script:EmojiTable = @{ Film = '🎬'; Ready = '✅'; Receipt = '🧾'; Mismatch = '🔶'; Failed = '⛔'; Stop = '🛑'; Lab = '🧪'; Spark = '✨'; Rocket = '🚀' }
$script:Spinners = @{ Fancy = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'); Ascii = @('|', '/', '-', '\') }

function Initialize-TuiGlyphs {
    [CmdletBinding()]
    param([ValidateSet('Auto', 'Nerd', 'Unicode', 'Ascii')][string]$Mode = 'Auto')
    if ($Mode -eq 'Auto') {
        $requested = [Environment]::GetEnvironmentVariable('CLAUDE_TUI_GLYPHS')
        $asciiFlag = [Environment]::GetEnvironmentVariable('POWERSHELL_TUI_ASCII')
        if ($requested -in 'nerd', 'unicode', 'ascii') { $Mode = (Get-Culture).TextInfo.ToTitleCase($requested) }
        elseif ($asciiFlag -and $asciiFlag -notin '0', 'false', 'off', 'no') { $Mode = 'Ascii' }
        elseif ($env:WT_SESSION) { $Mode = 'Nerd' }
        else { $Mode = 'Unicode' }
    }
    $index = switch ($Mode) { 'Nerd' { 0 } 'Unicode' { 1 } default { 2 } }
    $TuiGlyph.Clear()
    foreach ($name in $script:GlyphTable.Keys) { $TuiGlyph[$name] = $script:GlyphTable[$name][$index] }
    $TuiGlyph['Spin'] = if ($index -eq 2) { $script:Spinners.Ascii } else { $script:Spinners.Fancy }
    $TuiEmoji.Clear()
    foreach ($name in $script:EmojiTable.Keys) { $TuiEmoji[$name] = if ($index -eq 0) { $script:EmojiTable[$name] } else { '' } }
    $script:TuiGlyphMode = $Mode
}

function Get-TuiGlyphMode { $script:TuiGlyphMode }

function Set-TuiTheme([hashtable]$Colors) { foreach ($k in $Colors.Keys) { $TuiTheme[$k] = $Colors[$k] } ; $script:ColorCache.Clear() }

function Get-TuiRgb([string]$Hex) {
    $h = $Hex.TrimStart('#')
    , @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
}

# Resolves a theme name or '#RRGGBB' to an SGR sequence.
function TuiFg([string]$Color) {
    $key = "f$Color"
    if (-not $script:ColorCache.ContainsKey($key)) {
        $hex = if ($TuiTheme.ContainsKey($Color)) { $TuiTheme[$Color] } else { $Color }
        $c = Get-TuiRgb $hex
        $script:ColorCache[$key] = "$E[38;2;$($c[0]);$($c[1]);$($c[2])m"
    }
    $script:ColorCache[$key]
}
function TuiBg([string]$Color) {
    $key = "b$Color"
    if (-not $script:ColorCache.ContainsKey($key)) {
        $hex = if ($TuiTheme.ContainsKey($Color)) { $TuiTheme[$Color] } else { $Color }
        $c = Get-TuiRgb $hex
        $script:ColorCache[$key] = "$E[48;2;$($c[0]);$($c[1]);$($c[2])m"
    }
    $script:ColorCache[$key]
}
function TuiPaint([string]$Color, [string]$Text) { "$(TuiFg $Color)$Text$script:Reset" }
function TuiBold([string]$Color, [string]$Text) { "$E[1m$(TuiFg $Color)$Text$script:Reset" }

#endregion
#region Text: safe text, display cells, fit, wrap ---------------------------------------

# Characters that may occupy 0 or 2 cells. Everything else (ASCII, Latin/Greek, box
# drawing, Nerd Font private-use glyphs) is one cell, keeping the common path cheap.
$script:SpecialWidth = [regex]::new('[̀-ͯᄀ-ᅟ​-‏ -‮⁠-⁯⌚⌛⏩-⏳◽◾☔☕⚡⚪-⛽✅✨❌❎❓-❗➕-➗⬛-⭕⺀-꓏가-힣\uD800-\uDFFF豈-﫿︀-️︰-﹏﻿＀-｠]', 'Compiled')
$script:AnsiToken = [regex]::new("$E\[[0-9;?]*[A-Za-z]|$E\][^\a]*\a", 'Compiled')
$script:AnsiSplit = [regex]::new("($E\[[0-9;?]*[A-Za-z])|([^$E]+)", 'Compiled')
$script:UnsafeText = [regex]::new('[\x00-\x08\x0B-\x1F\x7F-\x9F​-‏ -‮⁠-⁩﻿]', 'Compiled')
$script:WideSingles = [System.Collections.Generic.HashSet[int]]::new([int[]]@(
        0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3, 0x25FD, 0x25FE, 0x2614, 0x2615, 0x26A1,
        0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26D4, 0x26EA, 0x26F2, 0x26F3, 0x26F5, 0x26FA,
        0x26FD, 0x2705, 0x2728, 0x274C, 0x274E, 0x2753, 0x2754, 0x2755, 0x2757, 0x2795, 0x2796, 0x2797, 0x2B1B,
        0x2B1C, 0x2B50, 0x2B55))

# External text (file names, helper errors, metadata) can carry tabs, CR/LF, bidi marks
# or other invisible format characters that break width math. Normalize it once.
function ConvertTo-TuiSafeText([AllowNull()][string]$Text, [switch]$SingleLine) {
    if ($null -eq $Text) { return '' }
    $t = $Text.Replace("`t", '    ')
    if ($SingleLine) { $t = $t -replace '\r?\n', ' ' } else { $t = $t -replace '\r\n?', "`n" }
    # The pattern excludes LF (0x0A), so paragraph breaks survive in multi-line mode.
    $script:UnsafeText.Replace($t, '')
}

function Get-TuiRuneWidth([int]$Cp) {
    if ($Cp -lt 0x0300) { return 1 }
    if ($Cp -eq 0x200D -or ($Cp -ge 0xFE00 -and $Cp -le 0xFE0F) -or ($Cp -ge 0x0300 -and $Cp -le 0x036F) -or
        ($Cp -ge 0x200B -and $Cp -le 0x200F) -or ($Cp -ge 0x2028 -and $Cp -le 0x202E) -or ($Cp -ge 0x2060 -and $Cp -le 0x206F) -or $Cp -eq 0xFEFF) { return 0 }
    if (($Cp -ge 0x1F300 -and $Cp -le 0x1F64F) -or ($Cp -ge 0x1F680 -and $Cp -le 0x1F6FF) -or ($Cp -ge 0x1F7E0 -and $Cp -le 0x1F7EB) -or
        ($Cp -ge 0x1F900 -and $Cp -le 0x1FAFF) -or ($Cp -ge 0x1100 -and $Cp -le 0x115F) -or ($Cp -ge 0x2E80 -and $Cp -le 0xA4CF) -or
        ($Cp -ge 0xAC00 -and $Cp -le 0xD7A3) -or ($Cp -ge 0xF900 -and $Cp -le 0xFAFF) -or ($Cp -ge 0xFE30 -and $Cp -le 0xFE4F) -or
        ($Cp -ge 0xFF00 -and $Cp -le 0xFF60) -or $script:WideSingles.Contains($Cp)) { return 2 }
    1
}

# Display cells of a string; SGR/OSC sequences count as zero.
function TuiWidth([AllowNull()][string]$Text) {
    if (-not $Text) { return 0 }
    if ($Text.IndexOf($E) -ge 0) { $Text = $script:AnsiToken.Replace($Text, '') }
    if (-not $script:SpecialWidth.IsMatch($Text)) { return $Text.Length }
    $width = 0
    foreach ($rune in $Text.EnumerateRunes()) { $width += Get-TuiRuneWidth $rune.Value }
    $width
}

# Pads or truncates (with an ellipsis) to exactly $Width cells. Keeps SGR sequences, never
# splits a wide character, and always ends with a reset.
function TuiFit([AllowNull()][string]$Text, [int]$Width) {
    if ($Width -le 0) { return '' }
    if ($null -eq $Text) { $Text = '' }
    $visible = TuiWidth $Text
    if ($visible -le $Width) { return $Text + $script:Reset + (' ' * ($Width - $visible)) }
    $limit = $Width - 1
    $sb = [System.Text.StringBuilder]::new()
    $used = 0
    $full = $false
    foreach ($m in $script:AnsiSplit.Matches($Text)) {
        if ($m.Groups[1].Success) { [void]$sb.Append($m.Value); continue }
        foreach ($rune in $m.Value.EnumerateRunes()) {
            $w = Get-TuiRuneWidth $rune.Value
            if ($used + $w -gt $limit) { $full = $true; break }
            [void]$sb.Append($rune.ToString())
            $used += $w
        }
        if ($full) { break }
    }
    [void]$sb.Append($TuiGlyph['Ellipsis']).Append($script:Reset)
    $used += TuiWidth $TuiGlyph['Ellipsis']
    $sb.ToString() + (' ' * [Math]::Max(0, $Width - $used))
}

# Word-wraps plain text to $Width cells (paragraphs kept, long words split).
function TuiWrap([AllowNull()][string]$Text, [int]$Width) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $Width = [Math]::Max(1, $Width)
    foreach ($paragraph in ((ConvertTo-TuiSafeText $Text) -split "`n")) {
        $line = ''
        foreach ($word in ($paragraph -split ' ')) {
            if ($word -eq '') { continue }
            $candidate = if ($line) { "$line $word" } else { $word }
            if ((TuiWidth $candidate) -le $Width) { $line = $candidate; continue }
            if ($line) { $lines.Add($line) }
            while ((TuiWidth $word) -gt $Width) {
                $take = ''; $used = 0
                foreach ($rune in $word.EnumerateRunes()) { $w = Get-TuiRuneWidth $rune.Value; if ($used + $w -gt $Width) { break }; $take += $rune.ToString(); $used += $w }
                $lines.Add($take); $word = $word.Substring($take.Length)
            }
            $line = $word
        }
        $lines.Add($line)
    }
    , $lines.ToArray()
}

function TuiElapsed([TimeSpan]$Span) {
    if ($Span.TotalHours -ge 1) { return $Span.ToString('h\:mm\:ss', $script:Invariant) }
    $Span.ToString('m\:ss', $script:Invariant)
}

#endregion
#region Components ----------------------------------------------------------------------

function TuiKV([string]$Label, [string]$Value, [int]$LabelWidth = 11) { "$(TuiPaint Muted $Label.PadRight($LabelWidth))$Value" }

# Rounded card: accent icon + title in the top border, muted frame, fitted body rows.
function TuiCard([string]$Title, [string]$Icon, [string]$Accent, [string[]]$Body, [int]$Width) {
    $Width = [Math]::Max(6, $Width)
    $inner = $Width - 4
    $b = TuiFg Border
    $label = if ($Icon) { " $Icon $Title " } else { " $Title " }
    $labelWidth = TuiWidth $label
    if ($labelWidth -gt $Width - 3) { $label = TuiFit $label ($Width - 3); $labelWidth = $Width - 3 }
    $fill = [Math]::Max(0, $Width - 3 - $labelWidth)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("$b$($TuiGlyph.TL)$($TuiGlyph.H)$script:Reset$E[1m$(TuiFg $Accent)$label$script:Reset$b$($TuiGlyph.H * $fill)$($TuiGlyph.TR)$script:Reset")
    foreach ($row in $Body) { $lines.Add("$b$($TuiGlyph.V)$script:Reset $(TuiFit $row $inner) $b$($TuiGlyph.V)$script:Reset") }
    $lines.Add("$b$($TuiGlyph.BL)$($TuiGlyph.H * ($Width - 2))$($TuiGlyph.BR)$script:Reset")
    , $lines.ToArray()
}

function TuiColumns([string[]]$Left, [int]$LeftWidth, [string[]]$Right, [int]$RightWidth, [int]$Gap = 2) {
    $rows = [Math]::Max($Left.Count, $Right.Count)
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $rows; $i++) {
        $l = if ($i -lt $Left.Count) { $Left[$i] } else { '' }
        $r = if ($i -lt $Right.Count) { $Right[$i] } else { '' }
        $out.Add((TuiFit $l $LeftWidth) + (' ' * $Gap) + (TuiFit $r $RightWidth))
    }
    , $out.ToArray()
}

# Full-width bar with a per-cell truecolor gradient background and bold white text.
function TuiGradient([string]$Text, [int]$Width, [string]$From = 'GradFrom', [string]$To = 'GradTo') {
    $a = Get-TuiRgb $(if ($TuiTheme.ContainsKey($From)) { $TuiTheme[$From] } else { $From })
    $z = Get-TuiRgb $(if ($TuiTheme.ContainsKey($To)) { $TuiTheme[$To] } else { $To })
    $cells = [System.Collections.Generic.List[string]]::new()
    foreach ($rune in (TuiFit $Text $Width).Replace($script:Reset, '').EnumerateRunes()) {
        $cells.Add($rune.ToString())
        if ((Get-TuiRuneWidth $rune.Value) -eq 2) { $cells.Add('') }
    }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("$E[1m$(TuiFg '#FFFFFF')")
    for ($i = 0; $i -lt [Math]::Min($Width, $cells.Count); $i++) {
        if ($i % 2 -eq 0) {
            $t = if ($Width -gt 1) { $i / ($Width - 1) } else { 0 }
            $r = [int]($a[0] + ($z[0] - $a[0]) * $t); $g = [int]($a[1] + ($z[1] - $a[1]) * $t); $bl = [int]($a[2] + ($z[2] - $a[2]) * $t)
            [void]$sb.Append("$E[48;2;$r;$g;${bl}m")
        }
        [void]$sb.Append($cells[$i])
    }
    [void]$sb.Append($script:Reset)
    $sb.ToString()
}

# Full-width status banner; the background spans the padding too.
function TuiBanner([string]$Accent, [string]$Text, [int]$Width) {
    $fitted = (TuiFit $Text $Width).Replace($script:Reset, '')
    "$(TuiBg $Accent)$E[1m$(TuiFg Ink)$fitted$script:Reset"
}

# Powerline-capped key chip followed by its label.
function TuiChip([string]$Key, [string]$Label, [string]$Accent = 'Violet', [switch]$Disabled) {
    $tone = if ($Disabled) { 'Slate' } else { $Accent }
    $labelTone = if ($Disabled) { 'Dim' } else { 'Text' }
    if (-not $TuiGlyph.CapL) { return "$(TuiFg $tone)[$Key]$script:Reset $(TuiPaint $labelTone $Label)" }
    "$(TuiFg $tone)$($TuiGlyph.CapL)$(TuiBg $tone)$E[1m$(TuiFg Ink)$Key$script:Reset$(TuiFg $tone)$($TuiGlyph.CapR)$script:Reset $(TuiPaint $labelTone $Label)"
}

$script:TuiTick = 0
function TuiSpinner { $TuiGlyph.Spin[$script:TuiTick % $TuiGlyph.Spin.Count] }
function Get-TuiTick { $script:TuiTick }

function New-TuiSteps([string[]]$Labels) { , @($Labels | ForEach-Object { @{ Label = $_; State = 'pending'; Started = $null; Ended = $null } }) }

# Marks steps before $Index done and $Index active. States: pending, active, done, failed.
function Set-TuiStep($Steps, [int]$Index) {
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        $step = $Steps[$i]
        if ($i -lt $Index -and $step.State -ne 'done') { $step.State = 'done'; if (-not $step.Started) { $step.Started = [datetime]::Now }; $step.Ended = [datetime]::Now }
        elseif ($i -eq $Index -and $step.State -eq 'pending') { $step.State = 'active'; $step.Started = [datetime]::Now }
    }
}

function Complete-TuiSteps($Steps, [ValidateSet('done', 'failed')][string]$State = 'done') {
    foreach ($step in $Steps) {
        if ($step.State -eq 'active') { $step.State = $State; $step.Ended = [datetime]::Now }
        elseif ($step.State -eq 'pending' -and $State -eq 'done') { $step.State = 'done' }
    }
}

function TuiSteps($Steps) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($step in $Steps) {
        $time = ''
        if ($step.Started) {
            $end = if ($step.Ended) { $step.Ended } else { [datetime]::Now }
            $time = TuiPaint Dim ('  ' + (TuiElapsed ($end - $step.Started)))
        }
        $line = switch ($step.State) {
            'done' { "$(TuiPaint Green $TuiGlyph.Ok)  $(TuiPaint Text $step.Label)$time" }
            'active' { "$(TuiPaint Violet (TuiSpinner))  $(TuiBold Text $step.Label)$time" }
            'failed' { "$(TuiPaint Red $TuiGlyph.Bad)  $(TuiPaint Red $step.Label)$time" }
            default { "$(TuiPaint Dim $TuiGlyph.Pending)  $(TuiPaint Dim $step.Label)" }
        }
        $lines.Add($line)
    }
    , $lines.ToArray()
}

# Proportional stacked bar + legend. Segments: @(@{ Label; Count; Color }, ...).
function TuiStackBar($Segments, [int]$Width) {
    $total = 0
    foreach ($s in $Segments) { $total += [int]$s.Count }
    if ($total -le 0) { return , @((TuiPaint Dim 'no data'), '') }
    $bar = ''; $legend = ''; $used = 0
    $visible = @($Segments | Where-Object { [int]$_.Count -gt 0 })
    for ($i = 0; $i -lt $visible.Count; $i++) {
        $s = $visible[$i]
        $cells = if ($i -eq $visible.Count - 1) { $Width - $used } else { [Math]::Max(1, [int][Math]::Round($Width * [int]$s.Count / $total)) }
        $cells = [Math]::Max(0, [Math]::Min($cells, $Width - $used))
        $glyph = if ($TuiGlyph.Block -eq '#') { ([string]$s.Label).Substring(0, 1) } else { $TuiGlyph.Block }
        $bar += TuiPaint $s.Color ($glyph * $cells)
        $used += $cells
        $pct = (100.0 * [int]$s.Count / $total).ToString('0', $script:Invariant)
        $legend += "$(TuiPaint $s.Color $TuiGlyph.Dot) $(TuiPaint Text ([string]$s.Label)) $(TuiPaint Muted "$($s.Count) ($pct%)")   "
    }
    , @($bar, $legend.TrimEnd())
}

# Simple responsive table. Columns: @(@{ Title; Width = <cells> or 0 for flexible }, ...).
# Rows: arrays of already-colored cell strings. Flexible columns share the remaining width.
function TuiTable($Columns, $Rows, [int]$Width, [int]$Gap = 2) {
    $fixed = 0; $flex = 0
    foreach ($c in $Columns) { if ([int]$c.Width -gt 0) { $fixed += [int]$c.Width } else { $flex++ } }
    $spare = [Math]::Max(0, $Width - $fixed - $Gap * ($Columns.Count - 1))
    $widths = @($Columns | ForEach-Object { if ([int]$_.Width -gt 0) { [int]$_.Width } else { [Math]::Max(4, [int][Math]::Floor($spare / [Math]::Max(1, $flex))) } })
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add((@(for ($i = 0; $i -lt $Columns.Count; $i++) { TuiFit (TuiPaint Dim ([string]$Columns[$i].Title)) $widths[$i] }) -join (' ' * $Gap)))
    foreach ($row in $Rows) { $out.Add((@(for ($i = 0; $i -lt $Columns.Count; $i++) { TuiFit $(if ($i -lt $row.Count) { [string]$row[$i] } else { '' }) $widths[$i] }) -join (' ' * $Gap))) }
    , $out.ToArray()
}

#endregion
#region Frame composition ---------------------------------------------------------------

function New-TuiScroll { @{ Offset = 0; Max = 0; Count = 0; Visible = 0 } }

# Handles Up/Down/PageUp/PageDown/Home/End. Returns $true when the key was a scroll key.
function Invoke-TuiScrollKey([System.ConsoleKeyInfo]$Key, $Scroll) {
    $page = [Math]::Max(1, $Scroll.Visible - 2)
    switch ($Key.Key) {
        'UpArrow' { $Scroll.Offset-- } 'DownArrow' { $Scroll.Offset++ }
        'PageUp' { $Scroll.Offset -= $page } 'PageDown' { $Scroll.Offset += $page }
        'Home' { $Scroll.Offset = 0 } 'End' { $Scroll.Offset = $Scroll.Max }
        default { return $false }
    }
    $Scroll.Offset = [Math]::Min([Math]::Max(0, $Scroll.Offset), $Scroll.Max)
    $true
}

# Composes exactly $Height lines of exactly $Width cells: header, scrollable body (with a
# left margin), rule with scroll position, status line and wrapped key chips.
function New-TuiFrame {
    param(
        [int]$Width, [int]$Height,
        [string[]]$Header = @(), [string[]]$Body = @(), [string[]]$Chips = @(),
        [string]$Status = '', $Scroll = $null, [int]$Margin = 2,
        [int]$MinWidth = 60, [int]$MinHeight = 16
    )
    if ($Width -lt $MinWidth -or $Height -lt $MinHeight) {
        $msg = "Window too small ($Width×$Height). Needs at least $MinWidth×$MinHeight."
        $lines = @(for ($i = 0; $i -lt $Height; $i++) { ' ' * [Math]::Max(0, $Width) })
        if ($Height -gt 0) { $lines[[int][Math]::Floor($Height / 2)] = TuiFit ((' ' * [Math]::Max(0, [int](($Width - (TuiWidth $msg)) / 2))) + (TuiPaint Amber $msg)) $Width }
        return , $lines
    }
    if ($null -eq $Scroll) { $Scroll = New-TuiScroll }
    $Scroll.Count = $Body.Count

    $footerFor = {
        param([bool]$Scrolling)
        $all = @($Chips)
        if ($Scrolling) { $all += TuiChip "$($TuiGlyph.Up)$($TuiGlyph.Down)" 'Scroll' 'Slate' }
        $rows = [System.Collections.Generic.List[string]]::new()
        $line = ''
        foreach ($chip in $all) {
            $candidate = if ($line) { "$line   $chip" } else { " $chip" }
            if ($line -and (TuiWidth $candidate) -gt $Width) { $rows.Add($line); $line = " $chip" } else { $line = $candidate }
        }
        $rows.Add($line)
        , $rows.ToArray()
    }
    $chipRows = & $footerFor $false
    $visible = $Height - $Header.Count - 2 - $chipRows.Count
    if ($Body.Count -gt $visible) {
        $chipRows = & $footerFor $true
        $visible = $Height - $Header.Count - 2 - $chipRows.Count
    }
    $visible = [Math]::Max(0, $visible)
    $Scroll.Visible = $visible
    $Scroll.Max = [Math]::Max(0, $Body.Count - $visible)
    $Scroll.Offset = [Math]::Min([Math]::Max(0, $Scroll.Offset), $Scroll.Max)

    $frame = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $Header) { $frame.Add((TuiFit $l $Width)) }
    $pad = ' ' * $Margin
    for ($i = 0; $i -lt $visible; $i++) {
        $index = $Scroll.Offset + $i
        $frame.Add((TuiFit $(if ($index -lt $Body.Count) { $pad + $Body[$index] } else { '' }) $Width))
    }
    $rule = TuiPaint Border ($TuiGlyph.H * $Width)
    if ($Scroll.Max -gt 0) {
        $where = " $($Scroll.Offset + 1)–$([Math]::Min($Body.Count, $Scroll.Offset + $visible)) of $($Body.Count) "
        $rule = (TuiPaint Border ($TuiGlyph.H * [Math]::Max(0, $Width - (TuiWidth $where) - 2))) + (TuiPaint Muted $where) + (TuiPaint Border ($TuiGlyph.H * 2))
    }
    $frame.Add((TuiFit $rule $Width))
    $frame.Add((TuiFit $(if ($Status) { " $Status" } else { '' }) $Width))
    foreach ($l in $chipRows) { $frame.Add((TuiFit $l $Width)) }
    # Never more rows than the window (a frame row past the viewport would scroll it).
    , @($frame | Select-Object -First $Height)
}

#endregion
#region Engine --------------------------------------------------------------------------

$script:Session = $null

function Get-TuiWindowSize {
    try { return , @([Console]::WindowWidth, [Console]::WindowHeight) } catch { return , @(120, 40) }
}

function Start-TuiSession([string]$Title = '') {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw 'This TUI needs an interactive console (Windows Terminal).' }
    if (-not $script:TuiGlyphMode) { Initialize-TuiGlyphs }
    $script:Session = @{ Encoding = [Console]::OutputEncoding; CtrlC = [Console]::TreatControlCAsInput }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::TreatControlCAsInput = $true
    $titleSeq = if ($Title) { "$E]0;$(ConvertTo-TuiSafeText $Title -SingleLine)$([char]7)" } else { '' }
    # Alternate screen, hidden cursor, auto-wrap off; the only clear of the session.
    [Console]::Out.Write("$titleSeq$E[?1049h$E[?25l$E[?7l$E[2J$E[1;1H")
    [Console]::Out.Flush()
}

function Stop-TuiSession {
    if ($null -eq $script:Session) { return }
    try { [Console]::Out.Write("$script:Reset$E[?2026l$E[?7h$E[?25h$E[?1049l"); [Console]::Out.Flush() } catch { }
    try { [Console]::TreatControlCAsInput = $script:Session.CtrlC } catch { }
    try { [Console]::OutputEncoding = $script:Session.Encoding } catch { }
    $script:Session = $null
}

# Returns the exact escape stream for one frame (exposed for tests).
function Get-TuiFrameText([string[]]$Lines, [int]$Width, [int]$Height) {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("$E[?2026h$E[?25l")
    $blank = ' ' * [Math]::Max(0, $Width)
    for ($i = 0; $i -lt $Height; $i++) {
        $line = if ($i -lt $Lines.Count) { $Lines[$i] } else { $blank }
        [void]$sb.Append("$E[$($i + 1);1H").Append($line)
    }
    [void]$sb.Append("$E[1;1H$E[?2026l")
    $sb.ToString()
}

function Write-TuiFrame([string[]]$Lines, [int]$Width, [int]$Height) {
    [Console]::Out.Write((Get-TuiFrameText $Lines $Width $Height))
    [Console]::Out.Flush()
}

function Test-TuiQuitKey([System.ConsoleKeyInfo]$Key) {
    $Key.Key -eq 'Escape' -or [char]::ToUpperInvariant($Key.KeyChar) -eq 'Q' -or
    ($Key.Key -eq 'C' -and ($Key.Modifiers -band [ConsoleModifiers]::Control))
}

<#
    Runs the event loop until -OnKey returns $false.
      -Render  { param($Width, $Height) ... return lines (use New-TuiFrame) }
      -OnKey   { param([ConsoleKeyInfo]$Key) ... return $false to leave }
      -OnPoll  { ... return $true when background state changed }      (optional)
      -Animate { ... return $true while a spinner/clock must keep moving } (optional)
    Callbacks run in the caller's scope, so they can update the caller's state.
#>
function Invoke-TuiLoop {
    param(
        [Parameter(Mandatory)][scriptblock]$Render,
        [Parameter(Mandatory)][scriptblock]$OnKey,
        [scriptblock]$OnPoll,
        [scriptblock]$Animate,
        [int]$TickMilliseconds = 100,
        [int]$SettleMilliseconds = 30,
        [int]$IdleMilliseconds = 15
    )
    $lastSize = ''
    $resizedAt = [datetime]::MinValue
    $lastTick = [datetime]::MinValue
    $dirty = $true
    while ($true) {
        if ($OnPoll -and [bool](& $OnPoll)) { $dirty = $true }
        $size = Get-TuiWindowSize
        $w = $size[0]; $h = $size[1]
        $now = [datetime]::Now
        $key = "$w x $h"
        if ($key -ne $lastSize) { $lastSize = $key; $resizedAt = $now; $dirty = $true }
        if ($Animate -and ($now - $lastTick).TotalMilliseconds -ge $TickMilliseconds -and [bool](& $Animate)) {
            $script:TuiTick++; $lastTick = $now; $dirty = $true
        }
        # During a resize drag keep the last frame (it clips, never wraps) and redraw once
        # the size has been stable briefly; drop frames built for a size that changed.
        if ($dirty -and ($now - $resizedAt).TotalMilliseconds -ge $SettleMilliseconds) {
            $frame = [string[]](& $Render $w $h)
            $after = Get-TuiWindowSize
            if ($after[0] -eq $w -and $after[1] -eq $h) { Write-TuiFrame $frame $w $h; $dirty = $false }
            continue
        }
        if ([Console]::KeyAvailable) {
            $result = & $OnKey ([Console]::ReadKey($true))
            if ($result -is [bool] -and -not $result) { break }
            $dirty = $true
        } else {
            Start-Sleep -Milliseconds $IdleMilliseconds
        }
    }
}

#endregion
#region Background process (JSON-lines or plain stdout) ---------------------------------

function Start-TuiProcess([string]$FilePath, [string[]]$ArgumentList, [hashtable]$Environment = @{}) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($a in $ArgumentList) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($k in $Environment.Keys) { $psi.Environment[$k] = [string]$Environment[$k] }
    $proc = [System.Diagnostics.Process]::Start($psi)
    @{ Proc = $proc; ReadTask = $proc.StandardOutput.ReadLineAsync(); ErrTask = $proc.StandardError.ReadToEndAsync(); Done = $false; ExitCode = $null; StdErr = '' }
}

# Returns the stdout lines available now, without blocking. Sets Done/ExitCode/StdErr at EOF.
function Receive-TuiProcessLines($Job) {
    $lines = [System.Collections.Generic.List[string]]::new()
    while (-not $Job.Done -and $Job.ReadTask.IsCompleted) {
        $line = $Job.ReadTask.Result
        if ($null -eq $line) {
            $Job.Proc.WaitForExit()
            $Job.Done = $true; $Job.ExitCode = $Job.Proc.ExitCode; $Job.StdErr = $Job.ErrTask.Result
            break
        }
        $lines.Add($line)
        $Job.ReadTask = $Job.Proc.StandardOutput.ReadLineAsync()
    }
    , $lines.ToArray()
}

function Send-TuiProcessLine($Job, [string]$Line) {
    if ($null -eq $Job -or $Job.Done) { return }
    try { $Job.Proc.StandardInput.WriteLine($Line); $Job.Proc.StandardInput.Flush() } catch { }
}

# Asks politely (optional line), then kills the whole tree after the grace period.
function Stop-TuiProcess($Job, [string]$CancelLine = '', [int]$GraceMilliseconds = 5000) {
    if ($null -eq $Job -or $Job.Proc.HasExited) { return }
    if ($CancelLine) { Send-TuiProcessLine $Job $CancelLine }
    if (-not $Job.Proc.WaitForExit($GraceMilliseconds)) { try { $Job.Proc.Kill($true) } catch { } }
}

#endregion
#region Preview (virtual rendering for review, not Windows Terminal proof) --------------

function ConvertTo-TuiHtml([System.Collections.IDictionary]$Frames, [string]$Font = 'CaskaydiaCove Nerd Font') {
    $sgr = [regex]::new("$E\[([0-9;?]*)([A-Za-z])|$E\][^\a]*\a")
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("<!doctype html><meta charset=`"utf-8`"><title>ClaudeTui preview</title><style>body{background:#0c0c0c;color:#ccc;margin:8px;font-family:'$Font',Consolas,monospace}pre{font-family:inherit;font-size:13px;line-height:1.2;margin:0 0 22px}.l{color:#777;font:12px sans-serif;margin:0 0 4px}</style>")
    foreach ($name in $Frames.Keys) {
        [void]$sb.Append("<div class=`"l`">$([System.Net.WebUtility]::HtmlEncode([string]$name))</div><pre>")
        $fg = $null; $bg = $null; $bold = $false
        foreach ($line in $Frames[$name]) {
            $pos = 0
            foreach ($m in $sgr.Matches($line)) {
                $chunk = $line.Substring($pos, $m.Index - $pos)
                if ($chunk) {
                    $style = @(); if ($fg) { $style += "color:$fg" }; if ($bg) { $style += "background:$bg" }; if ($bold) { $style += 'font-weight:bold' }
                    [void]$sb.Append("<span style=`"$($style -join ';')`">$([System.Net.WebUtility]::HtmlEncode($chunk))</span>")
                }
                $pos = $m.Index + $m.Length
                if ($m.Groups[2].Value -ne 'm') { continue }
                $codes = @(($m.Groups[1].Value -split ';') | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                if ($codes.Count -eq 0) { $codes = @(0) }
                for ($i = 0; $i -lt $codes.Count; $i++) {
                    switch ($codes[$i]) {
                        0 { $fg = $null; $bg = $null; $bold = $false }
                        1 { $bold = $true }
                        38 { if ($codes[$i + 1] -eq 2) { $fg = '#{0:x2}{1:x2}{2:x2}' -f $codes[$i + 2], $codes[$i + 3], $codes[$i + 4]; $i += 4 } }
                        48 { if ($codes[$i + 1] -eq 2) { $bg = '#{0:x2}{1:x2}{2:x2}' -f $codes[$i + 2], $codes[$i + 3], $codes[$i + 4]; $i += 4 } }
                    }
                }
            }
            $rest = $line.Substring($pos)
            if ($rest) {
                $style = @(); if ($fg) { $style += "color:$fg" }; if ($bg) { $style += "background:$bg" }; if ($bold) { $style += 'font-weight:bold' }
                [void]$sb.Append("<span style=`"$($style -join ';')`">$([System.Net.WebUtility]::HtmlEncode($rest))</span>")
            }
            [void]$sb.Append("`n")
        }
        [void]$sb.Append('</pre>')
    }
    $sb.ToString()
}

function Export-TuiPreview([System.Collections.IDictionary]$Frames, [string]$Path) {
    Set-Content -LiteralPath $Path -Value (ConvertTo-TuiHtml $Frames) -Encoding utf8NoBOM
    $Path
}

#endregion

Initialize-TuiGlyphs
Export-ModuleMember -Variable TuiTheme, TuiGlyph, TuiEmoji -Function @(
    'Initialize-TuiGlyphs', 'Get-TuiGlyphMode', 'Set-TuiTheme', 'Get-TuiRgb', 'TuiFg', 'TuiBg', 'TuiPaint', 'TuiBold',
    'ConvertTo-TuiSafeText', 'Get-TuiRuneWidth', 'TuiWidth', 'TuiFit', 'TuiWrap', 'TuiElapsed',
    'TuiKV', 'TuiCard', 'TuiColumns', 'TuiGradient', 'TuiBanner', 'TuiChip', 'TuiSpinner', 'Get-TuiTick',
    'New-TuiSteps', 'Set-TuiStep', 'Complete-TuiSteps', 'TuiSteps', 'TuiStackBar', 'TuiTable',
    'New-TuiScroll', 'Invoke-TuiScrollKey', 'New-TuiFrame',
    'Get-TuiWindowSize', 'Start-TuiSession', 'Stop-TuiSession', 'Get-TuiFrameText', 'Write-TuiFrame', 'Test-TuiQuitKey', 'Invoke-TuiLoop',
    'Start-TuiProcess', 'Receive-TuiProcessLines', 'Send-TuiProcessLine', 'Stop-TuiProcess',
    'ConvertTo-TuiHtml', 'Export-TuiPreview'
)
