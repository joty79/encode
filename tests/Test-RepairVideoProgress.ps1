[CmdletBinding()]
param([switch]$LiveUi)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'Video\lib\RepairUi.ps1')
$script:RepairPlainOutput = -not $LiveUi
$script:RepairActivityNumber = 0
$script:RepairDuration = 3.0
$script:ReportDirectory = Join-Path ([IO.Path]::GetTempPath()) ('encode-progress-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:ReportDirectory)
$script:Report = @{ Steps = @() }
$script:Ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$script:Ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Video\Repair-Video.ps1'), [ref]$null, [ref]$null)
foreach ($name in @('ConvertTo-RepairArgument','Invoke-RepairProcess')) {
    $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert-Progress {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

# Real-time fixture makes the pipe/file update behavior observable while alive.
$run = Invoke-RepairProcess -Exe $script:Ffmpeg -Label 'source-decode' -CommandArgs @(
    '-v','error','-re','-f','lavfi','-i','testsrc2=size=160x90:rate=25:duration=3',
    '-f','streamhash','-hash','sha256','-'
)
Assert-Progress ($run.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($run.Stderr)) 'Progress instrumentation must not create decode diagnostics.'
Assert-Progress ($run.Stdout -match '^0,v,SHA256=[0-9a-fA-F]+\s*$') 'Structured stdout must remain hash-only; progress must not contaminate it.'
Assert-Progress ($script:Report.Steps[0].LiveProgressUpdates -gt 1) 'Must consume several FFmpeg progress updates before the process exits.'
Assert-Progress ($script:Report.Steps[0].LastMediaSeconds -gt 0 -and $script:Report.Steps[0].ElapsedSeconds -ge 2) 'Report must retain measured duration and observed media position.'
$snapshot = Get-RepairProgressSnapshot -ProgressPath (Join-Path $script:ReportDirectory 'source-decode.progress.log') -DurationSeconds 3 -ElapsedSeconds 3
Assert-Progress ($snapshot.MediaSeconds -ge 2.9 -and $snapshot.Percent -eq 99 -and $snapshot.Detail -match 'Finalizing') 'A finished telemetry block is not proof of process/verification success; cap progress before completion.'
$missing = Get-RepairProgressSnapshot -ProgressPath '' -DurationSeconds 0 -ElapsedSeconds 1
Assert-Progress ($missing.Percent -eq -1 -and $missing.Eta -eq -1) 'Unknown progress must not invent percent or ETA.'
$failure = Invoke-RepairProcess -Exe $script:Ffmpeg -Label 'failure' -CommandArgs @('-v','error','-f','lavfi','-i','color=duration=1','-c:v','invalid-progress-test-encoder','-f','null','-')
Assert-Progress ($failure.ExitCode -ne 0 -and $failure.Stderr -match 'Unknown encoder') 'Nonzero process status and original error must be retained.'
$value = Invoke-RepairBackground -Title 'Background result check' -Code 'param($x) Start-Sleep -Milliseconds 300; $x + 1' -Arguments @(41)
Assert-Progress ($value -eq 42) 'Background activity must preserve return values.'
$caught = $false
try { Invoke-RepairBackground -Title 'Background error check' -Code "throw 'expected-progress-test-error'" } catch { $caught = $_ -match 'expected-progress-test-error' }
Assert-Progress $caught 'Background errors must remain failures.'

Import-Module (Join-Path $env:USERPROFILE '.agent-shared\templates\PS_UI_Blueprint.psm1') -Force -DisableNameChecking
$frames = @()
foreach ($width in @(120,101,100,99,98,80,60,120,50,40,80)) {
    $height = if ($width -eq 50) { 18 } elseif ($width -eq 40) { 10 } else { 24 }
    $fileName = if ($width % 2) { 'short.mp4' } else { 'long-file-' * 25 }
    $frame = New-RepairChoiceFrame -Width $width -Height $height -Selected ($width % 2) -Route 'Rebuild AAC audio; copy video unchanged.' -FileName $fileName
    $plain = [regex]::Replace($frame.ToString(), '\x1b\[[0-9;?]*[a-zA-Z]', '')
    $lines = @($plain -split '\r?\n')
    Assert-Progress ($lines.Count -le $height) 'Menu must fit viewport height.'
    foreach ($line in $lines) { Assert-Progress ($line.Length -le ($width - 2)) 'Menu must fit viewport width, including long file names.' }
    $frames += @{ width = $width; height = $height; text = $frame.ToString() }
}
$frames | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:ReportDirectory 'menu-frames.json') -Encoding UTF8
Write-Host "PASS: live FFmpeg telemetry, stdout isolation, failures, background results, menu width sequence. Evidence: $script:ReportDirectory"
