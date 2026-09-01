[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$videoEncoderPath = Join-Path $repoRoot 'Video\video_encode.ps1'
$queueRunnerPath = Join-Path $repoRoot 'Video\run_queue.ps1'

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Get-ParsedScript {
    param([Parameter(Mandatory)][string]$Path)

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$parseErrors
    )

    Assert-Contract -Condition ($parseErrors.Count -eq 0) -Message "$Path must parse without errors."

    return [pscustomobject]@{
        Ast    = $ast
        Source = Get-Content -LiteralPath $Path -Raw
    }
}

function Get-FunctionDefinition {
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory)][string]$Name
    )

    $foundFunctions = @($Ast.FindAll({
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $Name
            }, $true))

    Assert-Contract -Condition ($foundFunctions.Count -eq 1) -Message "Expected exactly one $Name function."
    return $foundFunctions[0]
}

$videoScript = Get-ParsedScript -Path $videoEncoderPath
$queueScript = Get-ParsedScript -Path $queueRunnerPath

$invokeExpressionCommands = @($videoScript.Ast.FindAll({
            param($node)

            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-Expression'
        }, $true))
Assert-Contract -Condition ($invokeExpressionCommands.Count -eq 0) -Message 'video_encode.ps1 must not use Invoke-Expression.'

$encoderResolverFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Resolve-VideoEncoder'
$encoderResolverHarness = [scriptblock]::Create($encoderResolverFunction.Extent.Text + @'

[pscustomobject]@{
    AutoWithNvenc       = Resolve-VideoEncoder -Preference auto -NvencAvailable $true
    AutoWithoutNvenc    = Resolve-VideoEncoder -Preference auto -NvencAvailable $false
    ExplicitX264        = Resolve-VideoEncoder -Preference x264 -NvencAvailable $true
    UnavailableExplicit = Resolve-VideoEncoder -Preference nvenc -NvencAvailable $false
}
'@)
$encoderResolution = & $encoderResolverHarness
Assert-Contract -Condition ($encoderResolution.AutoWithNvenc -ceq 'nvenc') -Message 'Auto must prefer a working NVENC encoder.'
Assert-Contract -Condition ($encoderResolution.AutoWithoutNvenc -ceq 'x264') -Message 'Auto must fall back to x264 when NVENC is unavailable.'
Assert-Contract -Condition ($encoderResolution.ExplicitX264 -ceq 'x264') -Message 'Explicit x264 selection must override available NVENC.'
Assert-Contract -Condition ($encoderResolution.UnavailableExplicit -ceq 'x264') -Message 'Unavailable explicit NVENC must fail safe to x264.'

$encoderArgumentsFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Get-VideoEncoderArguments'
$encoderArgumentsHarness = [scriptblock]::Create($encoderArgumentsFunction.Extent.Text + @'

[pscustomobject]@{
    Nvenc = @(Get-VideoEncoderArguments -Encoder nvenc -NvencQP 22 -X264CRF 19 -MaxMbps 12 -GopFrames 25)
    X264  = @(Get-VideoEncoderArguments -Encoder x264 -NvencQP 22 -X264CRF 19 -MaxMbps 12 -GopFrames 25)
}
'@)
$encoderArguments = & $encoderArgumentsHarness
$nvencArgumentLine = $encoderArguments.Nvenc -join ' '
$x264ArgumentLine = $encoderArguments.X264 -join ' '
Assert-Contract -Condition ($nvencArgumentLine -match '-c:v h264_nvenc.*-rc constqp.*-qp 22.*-preset p5.*-g 25.*-bf 0') -Message 'NVENC must retain the established QP 22 / P5 / B0 baseline.'
Assert-Contract -Condition ($x264ArgumentLine -match '-c:v libx264.*-crf 19.*-preset fast.*-profile:v high.*-g 25.*-bf 3') -Message 'x264 must use the benchmarked CRF 19 / fast / high / B3 profile.'
Assert-Contract -Condition ($x264ArgumentLine -notmatch 'nvenc|maxrate|bufsize') -Message 'The x264 path must not inherit NVENC-only rate-control options.'

$nvencProbeFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Test-H264NvencAvailable'
$nvencProbeHarnessText = @'
param([int]$SimulatedExitCode)

function ffmpeg {
    $global:P1CapturedNvencProbeArguments = @($MyInvocation.UnboundArguments)
    $global:LASTEXITCODE = $SimulatedExitCode
}
'@ + [Environment]::NewLine + $nvencProbeFunction.Extent.Text + @'

[pscustomobject]@{
    Available = Test-H264NvencAvailable
    Captured  = @($global:P1CapturedNvencProbeArguments)
}
'@
$nvencProbeHarness = [scriptblock]::Create($nvencProbeHarnessText)
$successfulNvencProbe = & $nvencProbeHarness 0
$failedNvencProbe = & $nvencProbeHarness 31
Assert-Contract -Condition $successfulNvencProbe.Available -Message 'A successful real NVENC probe must mark NVENC available.'
Assert-Contract -Condition (-not $failedNvencProbe.Available) -Message 'A failed real NVENC probe must force the x264 fallback.'
Assert-Contract -Condition (($successfulNvencProbe.Captured -join ' ') -match '-c:v h264_nvenc') -Message 'NVENC detection must attempt an actual h264_nvenc frame encode.'
Assert-Contract -Condition (($successfulNvencProbe.Captured -join ' ') -match 's=256x256') -Message 'The NVENC probe frame must stay above the encoder minimum dimensions.'

Assert-Contract -Condition (
    $videoScript.Source -match '\$batchSettingsFile\s*=\s*Join-Path\s+\$PSScriptRoot\s+"queue\\batch_settings\.json"'
) -Message 'Batch encoder settings must be portable with the script instead of tied to one machine path.'

$audioFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Get-AudioSyncAnalysis'
$unsafeInputPath = 'C:\media\clip & whoami $(not-run).mp4'
$audioHarnessText = @'
param([string]$InputPath)

$global:P1CapturedProbeArguments = @()
function ffprobe {
    $global:P1CapturedProbeArguments = @($MyInvocation.UnboundArguments)
    $global:LASTEXITCODE = 0
    '{"streams":[{"codec_type":"video","start_time":"0","duration":"10"},{"codec_type":"audio","codec_name":"aac","sample_rate":"48000","start_time":"0","duration":"10"}],"format":{"duration":"10"}}'
}
'@ + [Environment]::NewLine + $audioFunction.Extent.Text + @'

$analysisResult = Get-AudioSyncAnalysis -InputPath $InputPath
[pscustomobject]@{
    Analysis = $analysisResult
    Captured = @($global:P1CapturedProbeArguments)
}
'@
$audioHarness = [scriptblock]::Create($audioHarnessText)
$audioResult = & $audioHarness $unsafeInputPath

Assert-Contract -Condition ($audioResult.Captured.Count -eq 9) -Message 'ffprobe must receive the expected native argument count.'
Assert-Contract -Condition ($audioResult.Captured[-1] -ceq $unsafeInputPath) -Message 'The complete input path must remain one literal ffprobe argument.'
Assert-Contract -Condition ($audioResult.Analysis.Text -like 'Audio: AAC*') -Message 'Native ffprobe JSON output must still be parsed.'

$progressFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Invoke-FFmpegWithProgress'
$ffmpegHarnessText = @'
$global:P1ExpectedFFmpegExitCode = 23
function ffmpeg {
    'out_time_ms=1000000'
    'speed=1.0x'
    'progress=end'
    $global:LASTEXITCODE = $global:P1ExpectedFFmpegExitCode
}
'@ + [Environment]::NewLine + $progressFunction.Extent.Text + @'

Invoke-FFmpegWithProgress -FFmpegArgs @('-version') -TotalSec 1
'@
$ffmpegHarness = [scriptblock]::Create($ffmpegHarnessText)
$reportedFFmpegExitCode = & $ffmpegHarness
Assert-Contract -Condition ($reportedFFmpegExitCode -eq 23) -Message 'Invoke-FFmpegWithProgress must return the FFmpeg exit code.'

$interlaceFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Get-InterlaceInfo'
$interlaceHarnessText = @'
param([string]$InputPath)

function ffmpeg {
    'simulated idet failure'
    $global:LASTEXITCODE = 17
}
'@ + [Environment]::NewLine + $interlaceFunction.Extent.Text + @'

Get-InterlaceInfo -InputPath $InputPath
'@
$interlaceHarness = [scriptblock]::Create($interlaceHarnessText)
$interlaceResult = & $interlaceHarness 'C:\media\idet-test.mpg'
Assert-Contract -Condition (-not $interlaceResult.Succeeded) -Message 'A failed FFmpeg idet run must not be treated as successful analysis.'
Assert-Contract -Condition ($interlaceResult.ExitCode -eq 17) -Message 'Get-InterlaceInfo must preserve the FFmpeg exit code.'

$videoInfoFunction = Get-FunctionDefinition -Ast $videoScript.Ast -Name 'Get-VideoInfo'
$failedVideoInfoHarnessText = @'
param([string]$InputPath)

function ffprobe {
    $global:LASTEXITCODE = 19
}
'@ + [Environment]::NewLine + $videoInfoFunction.Extent.Text + @'

Get-VideoInfo -InputPath $InputPath
'@
$failedVideoInfoHarness = [scriptblock]::Create($failedVideoInfoHarnessText)
$failedVideoInfo = & $failedVideoInfoHarness 'C:\media\invalid.mpg'
Assert-Contract -Condition (-not $failedVideoInfo.Succeeded) -Message 'A failed video metadata probe must not be parsed as valid metadata.'
Assert-Contract -Condition ($failedVideoInfo.ExitCode -eq 19) -Message 'Get-VideoInfo must preserve the ffprobe exit code.'

$malformedVideoInfoHarnessText = @'
param([string]$InputPath)

function ffprobe {
    'width=720'
    'height=480'
    'r_frame_rate=N/A'
    $global:LASTEXITCODE = 0
}
'@ + [Environment]::NewLine + $videoInfoFunction.Extent.Text + @'

Get-VideoInfo -InputPath $InputPath
'@
$malformedVideoInfoHarness = [scriptblock]::Create($malformedVideoInfoHarnessText)
$malformedVideoInfo = & $malformedVideoInfoHarness 'C:\media\malformed.mpg'
Assert-Contract -Condition (-not $malformedVideoInfo.Succeeded) -Message 'Incomplete or malformed video metadata must fail cleanly.'
Assert-Contract -Condition ($malformedVideoInfo.Error -like 'ffprobe returned incomplete*') -Message 'Malformed metadata must report a focused error.'

Assert-Contract -Condition (
    $videoScript.Source -match '(?s)Remove an older output.*Invoke-FFmpegWithProgress.*if \(\$ffmpegExitCode -ne 0\).*Remove-Item -LiteralPath \$output.*continue'
) -Message 'A failed FFmpeg run must remove its partial output and skip success reporting.'
Assert-Contract -Condition (
    $videoScript.Source -match '(?s)\$outputProbeExitCode = \$LASTEXITCODE.*if \(\$outputProbeExitCode -ne 0 -or -not \$outRes\).*continue.*Write-Host "DONE"'
) -Message 'DONE must only be reachable after output validation succeeds.'

$childExitCaptures = [regex]::Matches(
    $queueScript.Source,
    '(?m)^\s*& pwsh .*\r?\n\s*\$(?:firstEncoderExitCode|encoderExitCode) = \$LASTEXITCODE\s*$'
)
Assert-Contract -Condition ($childExitCaptures.Count -eq 2) -Message 'Both child encoder invocations must immediately capture LASTEXITCODE.'

$queueStateFunction = Get-FunctionDefinition -Ast $queueScript.Ast -Name 'Set-QueueAfterEncoding'
$queueHarnessText = @'
param(
    [string]$QueueFilePath,
    [string[]]$FailedItems
)
'@ + [Environment]::NewLine + $queueStateFunction.Extent.Text + @'

Set-QueueAfterEncoding -QueueFilePath $QueueFilePath -FailedItems $FailedItems
'@
$queueHarness = [scriptblock]::Create($queueHarnessText)
$queueFixturePath = [System.IO.Path]::GetTempFileName()

try {
    @('first', 'second', 'third') | Set-Content -LiteralPath $queueFixturePath -Encoding UTF8
    $failedResult = & $queueHarness $queueFixturePath @('first', 'third')
    $retainedItems = @(Get-Content -LiteralPath $queueFixturePath)

    Assert-Contract -Condition ($failedResult -eq $false) -Message 'A queue with failures must report an unsuccessful queue result.'
    Assert-Contract -Condition ($retainedItems.Count -eq 2) -Message 'Only failed queue entries must remain.'
    Assert-Contract -Condition ($retainedItems[0] -ceq 'first' -and $retainedItems[1] -ceq 'third') -Message 'Failed queue entry order must be preserved.'

    $successResult = & $queueHarness $queueFixturePath @()
    Assert-Contract -Condition ($successResult -eq $true) -Message 'A queue without failures must report success.'
    Assert-Contract -Condition (-not (Test-Path -LiteralPath $queueFixturePath)) -Message 'The queue file must only be cleared after all entries succeed.'
}
finally {
    if (Test-Path -LiteralPath $queueFixturePath) {
        Remove-Item -LiteralPath $queueFixturePath -Force
    }
}

Write-Host 'PASS: P1 video encode and queue safety contract.' -ForegroundColor Green
