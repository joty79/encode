[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$verifyScript = Join-Path $repoRoot 'Video\Verify-VideoIntegrity.ps1'
$detectScript = Join-Path $repoRoot 'Video\Detect-BadCuts.ps1'
$inspectScript = Join-Path $repoRoot 'Video\inspector\inspect.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("encode-video-exit-tests-{0}" -f [guid]::NewGuid())
$assertionCount = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }

    $script:assertionCount++
}

function Invoke-VideoScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [hashtable]$Environment = @{},

        [string]$HostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $HostPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $processArguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ArgumentList
    $startInfo.Arguments = ($processArguments | ForEach-Object {
        '"' + $_.Replace('"', '\"') + '"'
    }) -join ' '

    $startInfo.EnvironmentVariables['PATH'] = "$tempRoot;$env:PATH"
    foreach ($name in $Environment.Keys) {
        $startInfo.EnvironmentVariables[$name] = [string]$Environment[$name]
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    [PSCustomObject]@{
        ExitCode = $process.ExitCode
        Stdout   = $stdoutTask.GetAwaiter().GetResult()
        Stderr   = $stderrTask.GetAwaiter().GetResult()
        Combined = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    }
}

New-Item -ItemType Directory -Path $tempRoot -ErrorAction Stop | Out-Null

try {
    $fakeToolSource = @'
using System;
using System.IO;

public static class FakeVideoTool
{
    private static int ReadExitCode(string name)
    {
        int exitCode;
        return Int32.TryParse(Environment.GetEnvironmentVariable(name), out exitCode) ? exitCode : 0;
    }

    public static int Main(string[] args)
    {
        string toolName = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
        string arguments = String.Join(" ", args);

        if (String.Equals(toolName, "ffprobe", StringComparison.OrdinalIgnoreCase))
        {
            string outputName = arguments.Contains("frame=pts_time")
                ? "FAKE_FFPROBE_KEYFRAMES"
                : arguments.Contains("stream=nb_frames")
                    ? "FAKE_FFPROBE_NB_FRAMES"
                    : "FAKE_FFPROBE_DURATION";

            Console.Out.Write(Environment.GetEnvironmentVariable(outputName));
            Console.Error.Write(Environment.GetEnvironmentVariable("FAKE_FFPROBE_STDERR"));
            return ReadExitCode("FAKE_FFPROBE_EXIT");
        }

        Console.Error.Write(Environment.GetEnvironmentVariable("FAKE_FFMPEG_STDERR"));
        return ReadExitCode("FAKE_FFMPEG_EXIT");
    }
}
'@

    $compiledTool = Join-Path $tempRoot 'fake-video-tool.exe'
    $fakeToolSourcePath = Join-Path $tempRoot 'fake-video-tool.cs'
    [System.IO.File]::WriteAllText($fakeToolSourcePath, $fakeToolSource)

    $compilerPath = @(
        "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

    if (-not $compilerPath) {
        throw 'The Windows C# compiler required by this focused test was not found.'
    }

    $compilerOutput = & $compilerPath /nologo /target:exe "/out:$compiledTool" $fakeToolSourcePath 2>&1
    $compilerExitCode = $LASTEXITCODE
    if ($compilerExitCode -ne 0) {
        throw "Fake video tool compilation failed with exit code $compilerExitCode.`n$($compilerOutput -join [Environment]::NewLine)"
    }

    Copy-Item -LiteralPath $compiledTool -Destination (Join-Path $tempRoot 'ffmpeg.exe')
    Copy-Item -LiteralPath $compiledTool -Destination (Join-Path $tempRoot 'ffprobe.exe')

    $inputPath = Join-Path $tempRoot 'input.mp4'
    [System.IO.File]::WriteAllBytes($inputPath, [byte[]](0x00))

    $verifyFailure = Invoke-VideoScript -ScriptPath $verifyScript -ArgumentList @('-Path', $inputPath) -Environment @{
        FAKE_FFMPEG_EXIT   = '7'
        FAKE_FFMPEG_STDERR = 'simulated ffmpeg input failure'
    }
    Assert-Condition ($verifyFailure.ExitCode -ne 0) 'Verify-VideoIntegrity must fail when ffmpeg exits nonzero.'
    Assert-Condition ($verifyFailure.Combined -match 'simulated ffmpeg input failure') 'Verify-VideoIntegrity must preserve ffmpeg stderr.'
    Assert-Condition ($verifyFailure.Combined -notmatch 'file structure is healthy') 'Verify-VideoIntegrity must not report healthy after ffmpeg failure.'

    $cutProbeFailure = Invoke-VideoScript -ScriptPath $detectScript -ArgumentList @('-Path', $inputPath, '-Cuts', '00:05') -Environment @{
        FAKE_FFPROBE_EXIT   = '8'
        FAKE_FFPROBE_STDERR = 'simulated ffprobe cut input failure'
    }
    Assert-Condition ($cutProbeFailure.ExitCode -ne 0) 'Cut mode must fail when ffprobe exits nonzero.'
    Assert-Condition ($cutProbeFailure.Combined -match 'simulated ffprobe cut input failure') 'Cut mode must preserve ffprobe stderr.'
    Assert-Condition ($cutProbeFailure.Combined -notmatch 'All specified cuts are properly aligned') 'Cut mode must not report success after ffprobe failure.'

    $metadataFailure = Invoke-VideoScript -ScriptPath $detectScript -ArgumentList @('-Path', $inputPath) -Environment @{
        FAKE_FFPROBE_EXIT   = '9'
        FAKE_FFPROBE_STDERR = 'simulated metadata probe failure'
    }
    Assert-Condition ($metadataFailure.ExitCode -ne 0) 'Full scan must fail when metadata ffprobe exits nonzero.'
    Assert-Condition ($metadataFailure.Combined -match 'simulated metadata probe failure') 'Full scan must preserve metadata ffprobe stderr.'
    Assert-Condition ($metadataFailure.Combined -notmatch 'No decoding errors or visual bad cuts found') 'Full scan must not report success after metadata failure.'

    $scanFailure = Invoke-VideoScript -ScriptPath $detectScript -ArgumentList @('-Path', $inputPath) -Environment @{
        FAKE_FFPROBE_EXIT     = '0'
        FAKE_FFPROBE_NB_FRAMES = '100'
        FAKE_FFPROBE_DURATION  = '10'
        FAKE_FFMPEG_EXIT       = '10'
        FAKE_FFMPEG_STDERR     = 'simulated demuxer failure detail'
    }
    Assert-Condition ($scanFailure.ExitCode -ne 0) 'Full scan must fail when ffmpeg exits nonzero.'
    Assert-Condition ($scanFailure.Combined -match 'simulated demuxer failure detail') 'Full scan must preserve unclassified ffmpeg stderr.'
    Assert-Condition ($scanFailure.Combined -notmatch 'No decoding errors or visual bad cuts found') 'Full scan must not report success after ffmpeg failure.'

    $warningSuccess = Invoke-VideoScript -ScriptPath $detectScript -ArgumentList @('-Path', $inputPath) -Environment @{
        FAKE_FFPROBE_EXIT      = '0'
        FAKE_FFPROBE_NB_FRAMES = '100'
        FAKE_FFPROBE_DURATION  = '10'
        FAKE_FFMPEG_EXIT       = '0'
        FAKE_FFMPEG_STDERR     = 'corrupt simulated packet warning'
    }
    Assert-Condition ($warningSuccess.ExitCode -eq 0) 'A completed scan with a detected warning must retain the existing successful process exit behavior.'
    Assert-Condition ($warningSuccess.Combined -match 'Decoding Warning/Error') 'A completed scan must still report detected decode warnings.'
    Assert-Condition ($warningSuccess.Combined -notmatch 'Cannot bind parameter.*ForegroundColor') 'Warning output must use a valid ConsoleColor.'

    $verifySuccess = Invoke-VideoScript -ScriptPath $verifyScript -ArgumentList @('-Path', $inputPath) -Environment @{
        FAKE_FFMPEG_EXIT = '0'
    }
    Assert-Condition ($verifySuccess.ExitCode -eq 0) 'Verify-VideoIntegrity clean path must still succeed.'
    Assert-Condition ($verifySuccess.Combined -match 'file structure is healthy') 'Verify-VideoIntegrity clean path must still report healthy.'

    $cutSuccess = Invoke-VideoScript -ScriptPath $detectScript -ArgumentList @('-Path', $inputPath, '-Cuts', '00:05') -Environment @{
        FAKE_FFPROBE_EXIT      = '0'
        FAKE_FFPROBE_KEYFRAMES = "0`n5`n"
    }
    Assert-Condition ($cutSuccess.ExitCode -eq 0) 'Aligned cut path must still succeed.'
    Assert-Condition ($cutSuccess.Combined -match 'All specified cuts are properly aligned') 'Aligned cut path must retain its success result.'

    $pwshPath = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $inspectorFailure = Invoke-VideoScript -HostPath $pwshPath -ScriptPath $inspectScript -ArgumentList @($inputPath) -Environment @{
        FAKE_FFPROBE_EXIT   = '11'
        FAKE_FFPROBE_STDERR = 'simulated inspector probe failure'
    }
    Assert-Condition ($inspectorFailure.ExitCode -ne 0) 'Inspector must fail when ffprobe exits nonzero.'
    Assert-Condition ($inspectorFailure.Combined -match 'simulated inspector probe failure') 'Inspector must preserve ffprobe diagnostics.'
    Assert-Condition ($inspectorFailure.Combined -notmatch '(?m)^File:') 'Inspector must not render successful media details after ffprobe failure.'

    $validInspectorJson = '{"streams":[{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"r_frame_rate":"30/1","avg_frame_rate":"30/1","field_order":"progressive","bit_rate":"5000000","sample_aspect_ratio":"1:1","display_aspect_ratio":"16:9"},{"codec_type":"audio","sample_rate":"48000"}],"format":{"duration":"10","bit_rate":"5000000"}}'
    $inspectorSuccess = Invoke-VideoScript -HostPath $pwshPath -ScriptPath $inspectScript -ArgumentList @($inputPath) -Environment @{
        FAKE_FFPROBE_EXIT     = '0'
        FAKE_FFPROBE_DURATION = $validInspectorJson
    }
    Assert-Condition ($inspectorSuccess.ExitCode -eq 0) 'Inspector must retain successful metadata rendering.'
    Assert-Condition ($inspectorSuccess.Combined -match '(?m)^File:') 'Inspector success must render the file row.'
    Assert-Condition ($inspectorSuccess.Combined -match 'Progressive') 'Inspector success must render scan metadata.'

    $missingInput = Join-Path $tempRoot 'missing.mp4'
    $missingVerifyResult = Invoke-VideoScript -ScriptPath $verifyScript -ArgumentList @('-Path', $missingInput)
    Assert-Condition ($missingVerifyResult.ExitCode -ne 0) 'Verify-VideoIntegrity must fail for a missing input path.'
    Assert-Condition ($missingVerifyResult.Combined -notmatch 'file structure is healthy') 'Missing input must not report a healthy integrity result.'

    $missingInputResult = Invoke-VideoScript -ScriptPath $detectScript -ArgumentList @('-Path', $missingInput)
    Assert-Condition ($missingInputResult.ExitCode -ne 0) 'Detect-BadCuts must fail for a missing input path.'
    Assert-Condition ($missingInputResult.Combined -notmatch 'No decoding errors or visual bad cuts found') 'Missing input must not report a healthy full scan.'

    Write-Host "PASS: $assertionCount assertions validated video tool/input failure handling and retained success behavior."
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
