[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$router = Join-Path $repo 'Video\Repair-Video.ps1'
$ffmpeg = (Get-Command ffmpeg -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ffprobe = (Get-Command ffprobe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$shellExe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$root = Join-Path ([IO.Path]::GetTempPath()) ('encode-router-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$assertions = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:assertions++
}
function Invoke-RouterTest {
    param([string]$InputPath, [string]$OutputPath, [string[]]$Options = @())
    $before = @(Get-ChildItem -LiteralPath $root -Directory | ForEach-Object { $_.FullName })
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $script:shellExe
    $arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script:router, '-Path', $InputPath, '-OutputPath', $OutputPath) + $Options
    $processInfo.Arguments = (($arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($processInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $code = $process.ExitCode
    $lines = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    $process.Dispose()
    $new = @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.FullName -notin $before })
    $report = $null
    if ($new.Count -eq 1) { $report = Get-Content -LiteralPath (Join-Path $new[0].FullName 'report.json') -Raw | ConvertFrom-Json }
    return [pscustomobject]@{ ExitCode = $code; Text = $lines; Report = $report }
}

# Fixture mutation is deliberately separate from the production detector.
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Collections.Generic; using System.Text;
public static class RouterFixtures {
    static int U(byte[] b,int p) {return (b[p]<<24)|(b[p+1]<<16)|(b[p+2]<<8)|b[p+3];}
    static void Put(byte[] b,int p,int n) {b[p]=(byte)(n>>24);b[p+1]=(byte)(n>>16);b[p+2]=(byte)(n>>8);b[p+3]=(byte)n;}
    static bool Find(byte[] b,int start,int end,List<int> parents,out int sample) {
        sample=-1;
        for(int p=start;p+8<=end;) {
            int size=U(b,p);if(size<8 || p+size>end)throw new Exception("Unexpected fixture atom");
            string type=Encoding.ASCII.GetString(b,p+4,4);
            if(type=="stsd" && p+24<=end && Encoding.ASCII.GetString(b,p+20,4)=="mp4a") {parents.Add(p);sample=p+16;return true;}
            if(type=="moov" || type=="trak" || type=="mdia" || type=="minf" || type=="stbl") {
                parents.Add(p);if(Find(b,p+8,p+size,parents,out sample))return true;parents.RemoveAt(parents.Count-1);
            }
            p+=size;
        }
        return false;
    }
    public static void BreakAacHeader(string src,string dst) {
        byte[] b=File.ReadAllBytes(src);var parents=new List<int>();int sample;
        if(!Find(b,0,b.Length,parents,out sample))throw new Exception("No AAC sample entry");
        int size=U(b,sample),remove=size-36;
        if(remove<=0)throw new Exception("Fixture lacks removable AAC configuration");
        foreach(int p in parents)Put(b,p,U(b,p)-remove);
        Put(b,sample,36);b[sample+16]=0;b[sample+17]=1;
        byte[] result=new byte[b.Length-remove];
        Buffer.BlockCopy(b,0,result,0,sample+36);
        Buffer.BlockCopy(b,sample+size,result,sample+36,b.Length-sample-size);
        File.WriteAllBytes(dst,result);
    }
    public static void Displace(string src,string dst,int start,int count) {
        byte[] b=File.ReadAllBytes(src),result=new byte[b.Length];
        Buffer.BlockCopy(b,0,result,0,start);
        Buffer.BlockCopy(b,start+count,result,start,b.Length-start-count);
        Buffer.BlockCopy(b,b.Length-count,result,b.Length-count,count);
        File.WriteAllBytes(dst,result);
    }
}
'@

try {
    $healthy = Join-Path $root 'healthy.mp4'
    & $ffmpeg -v error -n -f lavfi -i 'testsrc2=size=320x180:rate=25:duration=12' `
        -f lavfi -i 'sine=frequency=700:sample_rate=44100:duration=12' `
        -c:v libx264 -bf 0 -g 25 -keyint_min 25 -sc_threshold 0 -video_track_timescale 90000 -c:a aac $healthy
    if ($LASTEXITCODE -ne 0) { throw 'Fixture encoding failed.' }
    $healthyHash = (Get-FileHash -LiteralPath $healthy).Hash
    $clean = Invoke-RouterTest $healthy (Join-Path $root 'healthy-output.mp4') @('-AnalyzeOnly')
    Assert-That ($clean.ExitCode -eq 0 -and $clean.Report.Status -eq 'NoDetectedProblem') "Healthy input: $($clean.Text)"
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $root 'healthy-output.mp4'))) 'Healthy analysis must not manufacture a repair.'

    $existingDefault = Join-Path $root 'healthy_repaired.mp4'
    [IO.File]::WriteAllText($existingDefault, 'Existing result must be preserved.')
    $defaultPlan = Invoke-RouterTest $healthy '' @('-AnalyzeOnly')
    Assert-That ($defaultPlan.ExitCode -eq 0 -and $defaultPlan.Report.Output -eq (Join-Path $root 'healthy_repaired_2.mp4')) 'Context-menu invocation must select a free default output instead of blocking diagnosis.'
    Assert-That ([IO.File]::ReadAllText($existingDefault) -eq 'Existing result must be preserved.') 'Default name selection must preserve an existing result.'

    $header = Join-Path $root 'bad header.mp4'
    [RouterFixtures]::BreakAacHeader($healthy, $header)
    $headerHash = (Get-FileHash -LiteralPath $header).Hash
    $headerOutput = Join-Path $root 'header-output.mp4'
    $headerPlan = Invoke-RouterTest $header $headerOutput @('-AnalyzeOnly')
    Assert-That ($headerPlan.ExitCode -eq 2 -and $headerPlan.Report.Route -eq 'RebuildAacHeader') "Header diagnosis: $($headerPlan.Text)"
    Assert-That (-not (Test-Path -LiteralPath $headerOutput)) 'AnalyzeOnly must not render header repair.'
    $integrityScript = Join-Path $repo 'Video\Verify-VideoIntegrity.ps1'
    $integrity = & $shellExe -NoProfile -ExecutionPolicy Bypass -File $integrityScript -Path $header 2>&1 | Out-String
    $integrityCode = $LASTEXITCODE
    Assert-That ($integrityCode -eq 2 -and $integrity -match 'overread') 'Fast integrity must detect the malformed stsd warning even when FFmpeg exits zero.'
    $headerRepair = Invoke-RouterTest $header $headerOutput @('-Repair')
    Assert-That ($headerRepair.ExitCode -eq 0 -and $headerRepair.Report.Status -eq 'VerifiedRepair') "Header repair: $($headerRepair.Text)"
    Assert-That ($headerRepair.Report.SourceUnchanged -and (Get-FileHash -LiteralPath $header).Hash -eq $headerHash) 'Header repair must preserve source.'
    $savedHash = (Get-FileHash -LiteralPath $headerOutput).Hash
    $collision = Invoke-RouterTest $header $headerOutput @('-Repair')
    Assert-That ($collision.ExitCode -ne 0 -and (Get-FileHash -LiteralPath $headerOutput).Hash -eq $savedHash) 'Existing output must be protected.'

    $packetJson = & $ffprobe -v error -select_streams v:0 -show_entries packet=pts_time,pos,size -of json $healthy | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Fixture index probe failed.' }
    $packets = @(($packetJson | ConvertFrom-Json).packets)
    $start = [int]($packets | Where-Object { [double]$_.pts_time -ge 3.0 } | Select-Object -First 1).pos
    $end = [int]($packets | Where-Object { [double]$_.pts_time -ge 5.0 } | Select-Object -First 1).pos
    $shifted = Join-Path $root 'displaced.mp4'
    [RouterFixtures]::Displace($healthy, $shifted, $start, ($end - $start))
    $shiftedHash = (Get-FileHash -LiteralPath $shifted).Hash
    $shiftOutput = Join-Path $root 'shift-output.mp4'
    $shiftPlan = Invoke-RouterTest $shifted $shiftOutput @('-AnalyzeOnly')
    Assert-That ($shiftPlan.ExitCode -eq 2 -and $shiftPlan.Report.Route -eq 'RealignAndRemoveDamage') "Shift diagnosis: $($shiftPlan.Text)"
    Assert-That ($shiftPlan.Report.Alignment.Shift -eq ($end - $start)) 'Detector must derive the fixture-specific displacement, without a hardcoded real-file value.'
    $noConsent = Invoke-RouterTest $shifted $shiftOutput @('-Repair')
    Assert-That ($noConsent.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $shiftOutput)) 'Automation must explicitly opt into range removal.'
    $bounded = Invoke-RouterTest $shifted $shiftOutput @('-Repair', '-AllowRangeRemoval', '-MaxRemovedSeconds', '0.1')
    Assert-That ($bounded.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $shiftOutput)) 'Removal limit must stop the render.'
    $shiftRepair = Invoke-RouterTest $shifted $shiftOutput @('-Repair', '-AllowRangeRemoval')
    Assert-That ($shiftRepair.ExitCode -eq 0 -and $shiftRepair.Report.Status -eq 'VerifiedRepair') "Shift repair: $($shiftRepair.Text)"
    Assert-That ($shiftRepair.Report.SourceUnchanged -and (Get-FileHash -LiteralPath $shifted).Hash -eq $shiftedHash) 'Shift repair must preserve source.'
    Assert-That ($shiftRepair.Report.PlannedRemovedSeconds -gt 0 -and $shiftRepair.Report.PlannedRemovedSeconds -lt 4) 'Bounded damaged interval should be removed; later content retained.'

    $unknown = Join-Path $root 'unknown-corruption.mp4'
    $bytes = [IO.File]::ReadAllBytes($healthy)
    $bytes[$start] = 127; $bytes[$start + 1] = 255; $bytes[$start + 2] = 255; $bytes[$start + 3] = 255
    [IO.File]::WriteAllBytes($unknown, $bytes)
    $unknownOutput = Join-Path $root 'unknown-output.mp4'
    $unknownRun = Invoke-RouterTest $unknown $unknownOutput @('-Repair', '-AllowRangeRemoval')
    Assert-That ($unknownRun.ExitCode -eq 3 -and $unknownRun.Report.Status -eq 'ManualReview') "Unknown corruption must not guess a displacement: $($unknownRun.Text)"
    Assert-That (-not (Test-Path -LiteralPath $unknownOutput)) 'Unknown failure must not publish output.'
    Assert-That ((Get-FileHash -LiteralPath $healthy).Hash -eq $healthyHash) 'All tests must preserve original healthy fixture.'
    Write-Host "PASS: $assertions router assertions. Evidence: $root"
} catch {
    Write-Host "FAILED test evidence retained: $root"
    throw
}
