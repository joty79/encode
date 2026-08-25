[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Video\Merge-MP4-SRT.ps1'
$mkvmerge = 'C:\Program Files\MKVToolNix\mkvmerge.exe'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("encode-merge-srt-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertionCount++
}

function Invoke-MergeScript {
    param([Parameter(Mandatory = $true)][string]$VideoPath)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $startInfo.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -VideoFile "{1}"' -f $scriptPath, $VideoPath)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Combined = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    }
}

function New-VideoFixture {
    param([Parameter(Mandatory = $true)][string]$Path)

    & $script:ffmpeg -hide_banner -loglevel error -y -f lavfi `
        -i 'testsrc2=size=160x90:rate=25' -t 0.5 -c:v libx264 -pix_fmt yuv420p $Path
    if ($LASTEXITCODE -ne 0) { throw "Failed to create fixture: $Path" }
}

if (-not (Test-Path -LiteralPath $mkvmerge -PathType Leaf)) {
    throw "mkvmerge test dependency is missing: $mkvmerge"
}

$script:ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
New-Item -ItemType Directory -Path $tempRoot -ErrorAction Stop | Out-Null

try {
    $video = Join-Path $tempRoot 'sample.mp4'
    $subtitle = Join-Path $tempRoot 'sample.srt'
    $output = Join-Path $tempRoot 'sample.mkv'
    New-VideoFixture -Path $video
    [System.IO.File]::WriteAllText(
        $subtitle,
        "1`r`n00:00:00,000 --> 00:00:00,400`r`nSubtitle fixture`r`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    $success = Invoke-MergeScript -VideoPath $video
    Assert-Condition ($success.ExitCode -eq 0) 'MP4 plus matching SRT merge must succeed.'
    Assert-Condition (Test-Path -LiteralPath $video -PathType Leaf) 'Successful merge must preserve the source MP4.'
    Assert-Condition (Test-Path -LiteralPath $subtitle -PathType Leaf) 'Successful merge must preserve the source SRT.'
    Assert-Condition (Test-Path -LiteralPath $output -PathType Leaf) 'Successful merge must create the MKV output.'

    $outputJson = & $mkvmerge -J $output
    Assert-Condition ($LASTEXITCODE -eq 0) 'Created MKV must be readable by mkvmerge.'
    $trackTypes = @(($outputJson -join [Environment]::NewLine | ConvertFrom-Json).tracks | ForEach-Object { $_.type })
    Assert-Condition ($trackTypes -contains 'video') 'Created MKV must contain a video track.'
    Assert-Condition ($trackTypes -contains 'subtitles') 'Created MKV must contain a subtitle track.'

    $outputHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    $existing = Invoke-MergeScript -VideoPath $video
    $outputHashAfter = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    Assert-Condition ($existing.ExitCode -ne 0) 'Existing MKV output must make the merge fail safely.'
    Assert-Condition ($existing.Combined -match 'Output file already exists') 'Existing-output failure must be explicit.'
    Assert-Condition ($outputHashAfter -ceq $outputHash) 'Existing MKV output must remain byte-identical.'

    $noSubtitleVideo = Join-Path $tempRoot 'no-subtitle.mp4'
    New-VideoFixture -Path $noSubtitleVideo
    $noSubtitle = Invoke-MergeScript -VideoPath $noSubtitleVideo
    Assert-Condition ($noSubtitle.ExitCode -ne 0) 'Missing matching SRT must return nonzero.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'no-subtitle.mkv'))) 'Missing SRT must not create output.'

    $invalidVideo = Join-Path $tempRoot 'invalid.mp4'
    $invalidSubtitle = Join-Path $tempRoot 'invalid.srt'
    [System.IO.File]::WriteAllText($invalidVideo, 'not media')
    [System.IO.File]::WriteAllText($invalidSubtitle, "1`r`n00:00:00,000 --> 00:00:00,400`r`nInvalid fixture`r`n")
    $invalid = Invoke-MergeScript -VideoPath $invalidVideo
    Assert-Condition ($invalid.ExitCode -ne 0) 'Invalid video input must return nonzero.'
    Assert-Condition (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'invalid.mkv'))) 'Invalid video must not leave a partial MKV.'

    $missing = Invoke-MergeScript -VideoPath (Join-Path $tempRoot 'missing.mp4')
    Assert-Condition ($missing.ExitCode -ne 0) 'Missing video input must return nonzero.'

    Write-Host "PASS: $assertionCount assertions validated safe MP4-plus-SRT merge behavior."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
