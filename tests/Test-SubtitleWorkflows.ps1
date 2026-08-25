[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$convertScript = Join-Path $repoRoot 'subtitle\Convert-ToSrt.ps1'
$extractScript = Join-Path $repoRoot 'subtitle\Extract-MKV-Subtitle.ps1'
$seconv = 'C:\Program Files\Subtitle Edit CLI\seconv.exe'
$mkvmerge = 'C:\Program Files\MKVToolNix\mkvmerge.exe'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("encode-subtitle-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-SubtitleScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $allArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments
    $startInfo.Arguments = (($allArguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
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
        Combined = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    }
}

function Write-Utf8Text {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}

function New-Mkv {
    param([string]$OutputPath, [string[]]$Inputs)
    & $script:mkvmerge -q -o $OutputPath @Inputs
    if ($LASTEXITCODE -ne 0) { throw "MKV fixture creation failed: $OutputPath" }
}

[void][IO.Directory]::CreateDirectory($tempRoot)
try {
    Assert-Condition (Test-Path -LiteralPath $seconv -PathType Leaf) 'Official SeConv installation must exist.'
    Assert-Condition (Test-Path -LiteralPath $mkvmerge -PathType Leaf) 'MKVToolNix installation must exist.'

    $vtt = Join-Path $tempRoot 'sample.vtt'
    Write-Utf8Text -Path $vtt -Text "WEBVTT`r`n`r`n00:00:00.000 --> 00:00:01.200`r`nHello from VTT`r`n"
    $vttHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $vtt).Hash
    $vttResult = Invoke-SubtitleScript -ScriptPath $convertScript -Arguments @('-Path', $vtt)
    $vttOutput = [IO.Path]::ChangeExtension($vtt, '.srt')
    Assert-Condition ($vttResult.ExitCode -eq 0) 'Valid VTT-to-SRT conversion must succeed.'
    Assert-Condition (Test-Path -LiteralPath $vttOutput -PathType Leaf) 'VTT conversion must create SRT output.'
    Assert-Condition ((Get-Content -LiteralPath $vttOutput -Raw) -match 'Hello from VTT') 'Converted SRT must retain subtitle text.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $vtt).Hash -eq $vttHash) 'VTT conversion must preserve source bytes.'

    $vttOutputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $vttOutput).Hash
    $vttCollision = Invoke-SubtitleScript -ScriptPath $convertScript -Arguments @('-Path', $vtt)
    Assert-Condition ($vttCollision.ExitCode -ne 0) 'Existing SRT output must be refused.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $vttOutput).Hash -eq $vttOutputHash) 'Existing SRT output must remain byte-identical.'

    $alreadySrt = Invoke-SubtitleScript -ScriptPath $convertScript -Arguments @('-Path', $vttOutput)
    Assert-Condition ($alreadySrt.ExitCode -ne 0) 'SRT source must be rejected to avoid self-conversion.'
    $missingConvert = Invoke-SubtitleScript -ScriptPath $convertScript -Arguments @('-Path', (Join-Path $tempRoot 'missing.vtt'))
    Assert-Condition ($missingConvert.ExitCode -ne 0) 'Missing subtitle input must return nonzero.'

    $subtitleSource = Join-Path $tempRoot 'single-source.srt'
    Write-Utf8Text -Path $subtitleSource -Text "1`r`n00:00:00,000 --> 00:00:01,000`r`nHello from MKV`r`n"
    $singleMkv = Join-Path $tempRoot 'single.mkv'
    New-Mkv -OutputPath $singleMkv -Inputs @($subtitleSource)
    $singleHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $singleMkv).Hash
    $extractResult = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $singleMkv)
    $singleOutput = [IO.Path]::ChangeExtension($singleMkv, '.srt')
    Assert-Condition ($extractResult.ExitCode -eq 0) 'Single text-track MKV extraction must succeed.'
    Assert-Condition (Test-Path -LiteralPath $singleOutput -PathType Leaf) 'MKV extraction must create SRT output.'
    Assert-Condition ((Get-Content -LiteralPath $singleOutput -Raw) -match 'Hello from MKV') 'Extracted SRT must retain subtitle text.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $singleMkv).Hash -eq $singleHash) 'MKV extraction must preserve source bytes.'

    $singleOutputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $singleOutput).Hash
    $extractCollision = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $singleMkv)
    Assert-Condition ($extractCollision.ExitCode -ne 0) 'Existing extracted SRT must be refused.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $singleOutput).Hash -eq $singleOutputHash) 'Existing extracted SRT must remain byte-identical.'

    $assSource = Join-Path $tempRoot 'styled-source.ass'
    Write-Utf8Text -Path $assSource -Text ("[Script Info]`r`nScriptType: v4.00+`r`n`r`n" +
        "[V4+ Styles]`r`nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding`r`n" +
        "Style: Default,Arial,20,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1`r`n`r`n" +
        "[Events]`r`nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text`r`n" +
        "Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,Styled MKV subtitle`r`n")
    $assMkv = Join-Path $tempRoot 'styled.mkv'
    New-Mkv -OutputPath $assMkv -Inputs @($assSource)
    $assHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $assMkv).Hash
    $assResult = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $assMkv)
    $assOutput = [IO.Path]::ChangeExtension($assMkv, '.srt')
    Assert-Condition ($assResult.ExitCode -eq 0) 'ASS-in-MKV must be converted rather than renamed.'
    Assert-Condition ((Get-Content -LiteralPath $assOutput -Raw) -match 'Styled MKV subtitle') 'ASS conversion must retain dialogue text.'
    Assert-Condition ((Get-Content -LiteralPath $assOutput -Raw) -notmatch '\[Script Info\]') 'ASS extraction output must be real SRT, not ASS bytes with an SRT extension.'
    Assert-Condition ((Get-FileHash -Algorithm SHA256 -LiteralPath $assMkv).Hash -eq $assHash) 'ASS-in-MKV conversion must preserve source bytes.'

    $secondSubtitle = Join-Path $tempRoot 'second-source.srt'
    Write-Utf8Text -Path $secondSubtitle -Text "1`r`n00:00:00,000 --> 00:00:01,000`r`nSecond track`r`n"
    $multipleMkv = Join-Path $tempRoot 'multiple.mkv'
    New-Mkv -OutputPath $multipleMkv -Inputs @($subtitleSource, $secondSubtitle)
    $multipleResult = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $multipleMkv)
    Assert-Condition ($multipleResult.ExitCode -ne 0) 'Multiple subtitle tracks must be rejected.'
    Assert-Condition (-not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($multipleMkv, '.srt')))) 'Multiple-track rejection must leave no output.'

    $audio = Join-Path $tempRoot 'audio.wav'
    & $ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=500:sample_rate=8000' -t 0.25 $audio
    if ($LASTEXITCODE -ne 0) { throw 'Audio-only fixture creation failed.' }
    $noSubtitleMkv = Join-Path $tempRoot 'no-subtitle.mkv'
    New-Mkv -OutputPath $noSubtitleMkv -Inputs @($audio)
    $noSubtitleResult = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $noSubtitleMkv)
    Assert-Condition ($noSubtitleResult.ExitCode -ne 0) 'MKV without subtitles must return nonzero.'
    Assert-Condition (-not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($noSubtitleMkv, '.srt')))) 'No-subtitle rejection must leave no output.'

    $invalidMkv = Join-Path $tempRoot 'invalid.mkv'
    Write-Utf8Text -Path $invalidMkv -Text 'not a media container'
    $invalidResult = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $invalidMkv)
    Assert-Condition ($invalidResult.ExitCode -ne 0) 'Invalid MKV must return nonzero.'
    Assert-Condition (Test-Path -LiteralPath $invalidMkv -PathType Leaf) 'Invalid MKV must be preserved.'

    $wrongExtension = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', $subtitleSource)
    Assert-Condition ($wrongExtension.ExitCode -ne 0) 'Non-MKV input must be rejected.'
    $missingExtract = Invoke-SubtitleScript -ScriptPath $extractScript -Arguments @('-MkvFile', (Join-Path $tempRoot 'missing.mkv'))
    Assert-Condition ($missingExtract.ExitCode -ne 0) 'Missing MKV input must return nonzero.'

    Write-Host "PASS: $assertionCount assertions validated subtitle conversion and extraction safety."
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
