# Presentation and activity helpers. No media repair decisions live here.
function Format-RepairElapsed {
    param([double]$Seconds)
    $span = [TimeSpan]::FromSeconds([Math]::Max(0, $Seconds))
    return '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds
}

function Get-RepairStageName {
    param([string]$Label)
    $names = @{
        'source-probe' = 'Inspecting the MP4 container and streams'
        'source-packets' = 'Checking encoded packets (no re-encoding)'
        'source-video-index' = 'Reading the video packet index'
        'source-decode' = 'Decoding the original video and audio to check for errors'
        'source-audio-decode' = 'Checking the original audio decoder'
        'render-aac' = 'Rebuilding AAC audio; copying the original video'
        'realigned-detection' = 'Locating the remaining damaged interval'
        'render-packets' = 'Repairing packet ranges and verifying the joined video'
        'output-probe' = 'Checking the repaired container and streams'
        'output-decode' = 'Decoding the repaired video and audio to verify the result'
        'source-video-hash' = 'Fingerprinting the original compressed video'
        'output-video-hash' = 'Comparing the repaired compressed video'
    }
    if ($names.ContainsKey($Label)) { return $names[$Label] }
    return $Label
}

function Start-RepairActivity {
    param([string]$Title)
    $script:RepairActivityNumber++
    Write-Host ''
    Write-Host ('[{0:00}] {1}' -f $script:RepairActivityNumber, $Title) -ForegroundColor Cyan
    return [pscustomobject]@{ Title = $Title; Clock = [Diagnostics.Stopwatch]::StartNew(); LastPrint = -10.0; LastDetail = ''; Updates = 0 }
}

function Get-RepairProgressSnapshot {
    param([string]$ProgressPath, [double]$DurationSeconds, [double]$ElapsedSeconds)
    $seconds = $null; $speed = ''; $fps = ''; $frame = ''; $ended = $false
    if ($ProgressPath -and [IO.File]::Exists($ProgressPath)) {
        # Bounded tail read; FFmpeg can keep the file open throughout encoding.
        $stream = [IO.File]::Open($ProgressPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $start = [Math]::Max(0, $stream.Length - 16384)
            [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
            $reader = [IO.StreamReader]::new($stream)
            try { $tail = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
        # Only consume complete progress blocks; the last write may be partial.
        $blocks = [regex]::Matches($tail, '(?ms)(?:^|\n)frame=.*?^progress=(?:continue|end)\r?\n|(?:^|\n)bitrate=.*?^progress=(?:continue|end)\r?\n')
        if ($blocks.Count -gt 0) {
            $values = @{}
            foreach ($line in ($blocks[$blocks.Count - 1].Value -split '\r?\n')) {
                $pair = $line.Split('=', 2)
                if ($pair.Count -eq 2) { $values[$pair[0].Trim()] = $pair[1].Trim() }
            }
            $microseconds = 0.0
            if ($values.ContainsKey('out_time_us') -and [double]::TryParse($values['out_time_us'], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$microseconds)) {
                $seconds = [Math]::Max(0, $microseconds / 1000000.0)
            }
            if ($values.ContainsKey('speed')) { $speed = $values['speed'] }
            if ($values.ContainsKey('fps')) { $fps = $values['fps'] }
            if ($values.ContainsKey('frame')) { $frame = $values['frame'] }
            $ended = $values['progress'] -eq 'end'
        }
    }
    $percent = -1
    $eta = -1
    $detail = 'Working; waiting for FFmpeg progress'
    if ($null -ne $seconds) {
        $detail = 'Media ' + (Format-RepairElapsed $seconds)
        if ($DurationSeconds -gt 0) {
            $percent = [Math]::Min(99, [Math]::Max(0, [int][Math]::Floor(100 * $seconds / $DurationSeconds)))
            $detail += ' / ' + (Format-RepairElapsed $DurationSeconds) + " | $percent%"
            $rate = 0.0
            if ($speed -match '^([0-9.]+)x$' -and [double]::TryParse($Matches[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$rate) -and $rate -gt 0 -and $seconds -lt $DurationSeconds) {
                $eta = [int][Math]::Min([int]::MaxValue, ($DurationSeconds - $seconds) / $rate)
                $detail += ' | ETA ~' + (Format-RepairElapsed $eta)
            }
        }
        if ($speed -and $speed -ne 'N/A') { $detail += " | $speed" }
        if ($fps -and $fps -ne '0.00') { $detail += " | $fps fps" }
        if ($frame) { $detail += " | frame $frame" }
        if ($ended) { $detail += ' | Finalizing' }
    }
    return [pscustomobject]@{ Detail = $detail; Percent = $percent; Eta = $eta; MediaSeconds = $seconds; Speed = $speed }
}

function Update-RepairActivity {
    param([object]$Activity, [string]$Detail = 'Working (this stage has no percentage)', [int]$Percent = -1, [int]$Eta = -1)
    $status = $Detail + ' | elapsed ' + (Format-RepairElapsed $Activity.Clock.Elapsed.TotalSeconds)
    if (-not $script:RepairPlainOutput) {
        $progressArgs = @{ Id = 71; Activity = $Activity.Title; Status = $status; PercentComplete = $Percent }
        if ($Eta -ge 0) { $progressArgs.SecondsRemaining = $Eta }
        Write-Progress @progressArgs
    }
    # Plain/redirected logs get readable, throttled heartbeats as well.
    if ($Activity.Clock.Elapsed.TotalSeconds - $Activity.LastPrint -ge 5) {
        Write-Host ('  ' + $status) -ForegroundColor DarkGray
        $Activity.LastPrint = $Activity.Clock.Elapsed.TotalSeconds
        $Activity.Updates++
    }
    $Activity.LastDetail = $Detail
}

function Stop-RepairActivity {
    param([object]$Activity, [bool]$Succeeded)
    if (-not $script:RepairPlainOutput) { Write-Progress -Id 71 -Activity $Activity.Title -Completed }
    $state = if ($Succeeded) { 'DONE' } else { 'STOPPED' }
    $color = if ($Succeeded) { 'Green' } else { 'Yellow' }
    Write-Host ('  {0}  {1}' -f $state, (Format-RepairElapsed $Activity.Clock.Elapsed.TotalSeconds)) -ForegroundColor $color
}

function Invoke-RepairBackground {
    param([string]$Title, [string]$Code, [object[]]$Arguments = @())
    $activity = Start-RepairActivity $Title
    $worker = [PowerShell]::Create()
    $ok = $false
    try {
        [void]$worker.AddScript("`$ErrorActionPreference = 'Stop'; & { " + $Code + ' } @args')
        foreach ($argument in $Arguments) { [void]$worker.AddArgument($argument) }
        $pending = $worker.BeginInvoke()
        while (-not $pending.IsCompleted) {
            Update-RepairActivity $activity
            Start-Sleep -Milliseconds 250
        }
        $value = $worker.EndInvoke($pending)
        if ($worker.HadErrors) { throw ($worker.Streams.Error | Out-String) }
        $ok = $true
        return $value
    } finally {
        if ($worker.InvocationStateInfo.State -eq 'Running') { $worker.Stop() }
        $worker.Dispose()
        Stop-RepairActivity $activity $ok
    }
}

function Get-RepairFileHash {
    param([string]$FilePath)
    return Invoke-RepairBackground -Title 'Checking file fingerprint (reading disk)' -Code 'param($p) (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash' -Arguments @($FilePath)
}

function Get-RepairTimeline {
    param([string]$FilePath)
    return Invoke-RepairBackground -Title 'Checking frame timing and audio gaps' -Code 'param($module,$probe,$p) . $module; Get-MediaTimelineReport -Ffprobe $probe -InputPath $p' -Arguments @((Join-Path $PSScriptRoot 'MediaTimeline.ps1'), $script:Ffprobe, $FilePath)
}

function New-RepairChoiceFrame {
    param([int]$Width, [int]$Height, [int]$Selected, [string]$Route, [string]$FileName)
    $frame = New-UiFrame
    $e = [char]27
    $limit = [Math]::Max(1, $Width - 2)
    $panelWidth = [Math]::Min(76, $limit)
    $indent = ' ' * [Math]::Max(0, [int][Math]::Floor(($limit - $panelWidth) / 2))
    $rows = [Collections.Generic.List[object]]::new()
    $muted = "$e[38;5;246m"
    $accent = "$e[38;5;80m"
    $bright = "$e[1;97m"
    $rule = "$e[38;5;238m"
    $compact = $Height -lt 23 -or $Width -lt 54
    # Store semantic rows; the canonical renderer owns cursor/resize mechanics.
    if (-not $compact) { $rows.Add(@('', '')) }
    $rows.Add(@('MP4 DIAGNOSE / REPAIR', $accent))
    $rows.Add(@('Choose how to continue', $bright))
    if (-not $compact) {
        $rows.Add(@('01 Inspect    /    02 Choose repair    /    03 Verify', $muted))
        $rows.Add(@(('-' * $panelWidth), $rule))
    }
    $rows.Add(@(('FILE  ' + $FileName), $bright))
    $rows.Add(@('', ''))
    if (-not $compact) { $rows.Add(@('PROPOSED REPAIR', $accent)) }
    foreach ($part in @(Split-UiWrappedText -Text $Route -Width $panelWidth)) {
        $rows.Add(@($part, "$e[37m"))
        if ($compact) { break }
    }
    $rows.Add(@('', ''))
    $titles = @('Repair to a new file', 'Keep report only')
    $descriptions = @('Create a repaired copy, then verify it.', 'Save the diagnosis without creating a video.')
    foreach ($index in 0..1) {
        $selectedCard = $Selected -eq $index
        $card = if ($selectedCard) { "$e[48;5;24m$e[1;97m" } else { "$e[48;5;234m$e[37m" }
        $marker = if ($selectedCard) { '>' } else { ' ' }
        $rows.Add(@((" $marker  [$($index + 1)] " + $titles[$index]), $card))
        if (-not $compact) {
            $descriptionColor = if ($selectedCard) { "$e[48;5;24m$e[38;5;195m" } else { "$e[48;5;234m$muted" }
            $rows.Add(@(('        ' + $descriptions[$index]), $descriptionColor))
        }
        $rows.Add(@('', ''))
    }
    if (-not $compact) { $rows.Add(@('Your original file stays unchanged.', $muted)) }
    # Keep the keyboard help anchored near the bottom, including compact windows.
    $budget = [Math]::Max(0, $Height - 3)
    if ($Height -lt 14) {
        $rows.Clear()
        $rows.Add(@('MP4 DIAGNOSE / REPAIR', $accent))
        foreach ($index in 0..1) {
            $color = if ($Selected -eq $index) { "$e[48;5;24m$e[1;97m" } else { $muted }
            $rows.Add(@(("[$($index + 1)] " + $titles[$index]), $color))
        }
    }
    for ($row = 0; $row -lt $budget; $row++) {
        $text = ''; $color = ''
        if ($row -lt $rows.Count) { $text = [string]$rows[$row][0]; $color = [string]$rows[$row][1] }
        $safe = ConvertTo-UiSafeSingleLineText $text
        # Conservative two-cell budget for non-Latin glyphs in external filenames.
        $cellLimit = if ($safe -match '[\u1100-\uFFFF]') { [Math]::Max(1, [int][Math]::Floor($panelWidth / 2)) } else { $panelWidth }
        if ($safe.Length -gt $cellLimit) {
            $safe = if ($cellLimit -gt 3) { $safe.Substring(0, $cellLimit - 3) + '...' } else { $safe.Substring(0, $cellLimit) }
        }
        $padding = if ($color -match '48;5;') { ' ' * [Math]::Max(0, $panelWidth - $safe.Length) } else { '' }
        Add-UiFrameLine -Frame $frame -Text "$indent$color$safe$padding$e[0m$e[K"
    }
    if ($Height -ge 3) {
        $footer = if ($panelWidth -ge 52) { 'Up/Down  move    Enter  select    1/2  shortcuts' } else { 'Up/Down  Enter  1/2' }
        if ($footer.Length -gt $panelWidth) { $footer = $footer.Substring(0, $panelWidth) }
        $footer = $footer.Replace('Up/Down', "$e[37mUp/Down$muted").Replace('Enter', "$e[32mEnter$muted")
        Add-UiFrameLine -Frame $frame -Text "$indent$muted$footer$e[0m$e[K"
        $escape = 'Esc  keep report and return'
        if ($escape.Length -gt $panelWidth) { $escape = $escape.Substring(0, $panelWidth) }
        $escape = $escape.Replace('Esc', "$e[31mEsc$muted")
        Add-UiFrameLine -Frame $frame -Text "$indent$muted$escape$e[0m$e[K"
    }
    return $frame
}

function Show-RepairChoice {
    param([string]$Route, [string]$FileName)
    if ($script:RepairPlainOutput -or [Console]::IsInputRedirected) {
        Write-Host '1. Repair to a new file'
        Write-Host '2. Keep report only'
        do { $choice = Read-Host 'Choose 1 or 2 (2 cancels repair)' } while ($choice -notin @('1','2'))
        return $choice -eq '1'
    }
    $blueprint = Join-Path $env:USERPROFILE '.agent-shared\templates\PS_UI_Blueprint.psm1'
    if (-not (Test-Path -LiteralPath $blueprint)) { throw "Interactive renderer missing: $blueprint. Use -NoUI for plain mode." }
    Import-Module $blueprint -Force -DisableNameChecking
    $selected = 1
    Initialize-TuiHost
    try {
        while ($true) {
            Lock-ViewportToWindow
            $size = $Host.UI.RawUI.WindowSize
            $frame = New-RepairChoiceFrame -Width $size.Width -Height $size.Height -Selected $selected -Route $Route -FileName $FileName
            Write-UiFrame $frame
            $key = Read-ConsoleKey
            switch ($key.Key) {
                'UpArrow' { $selected = 0 }
                'DownArrow' { $selected = 1 }
                'Enter' { return $selected -eq 0 }
                'Escape' { return $false }
                default {
                    if ($key.KeyChar -eq '1') { return $true }
                    if ($key.KeyChar -eq '2') { return $false }
                }
            }
        }
    } finally { Restore-TuiHost }
}
