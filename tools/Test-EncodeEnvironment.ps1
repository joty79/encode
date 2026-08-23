[CmdletBinding()]
param(
    [string]$AviSynthRoot = 'E:\Compilers\AviSynth+',
    [switch]$Json
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$checks = New-Object System.Collections.Generic.List[object]

function Add-EnvironmentCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Required,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Details
    )

    $checks.Add([pscustomobject]@{
        Name     = $Name
        Required = $Required
        Passed   = $Passed
        Details  = $Details
    })
}

function Find-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Test-CommandAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Required
    )

    $commandPath = Find-CommandPath -Name $Name
    Add-EnvironmentCheck -Name "Command: $Name" -Required $Required -Passed ($null -ne $commandPath) `
        -Details $(if ($commandPath) { $commandPath } else { 'Not found on PATH' })
    return $commandPath
}

[void](Test-CommandAvailable -Name 'pwsh' -Required $true)
$ffmpegPath = Test-CommandAvailable -Name 'ffmpeg' -Required $true
[void](Test-CommandAvailable -Name 'ffprobe' -Required $true)
[void](Test-CommandAvailable -Name 'wt' -Required $false)
[void](Test-CommandAvailable -Name 'mkvmerge' -Required $false)
[void](Test-CommandAvailable -Name 'mkvextract' -Required $false)
[void](Test-CommandAvailable -Name 'magick' -Required $false)
[void](Test-CommandAvailable -Name 'seconv' -Required $false)

if ($ffmpegPath) {
    $ffmpegVersionText = (& $ffmpegPath -hide_banner -version 2>&1 | Out-String)
    $ffmpegExitCode = $LASTEXITCODE
    $firstVersionLine = ($ffmpegVersionText -split "`r?`n" | Select-Object -First 1).Trim()
    Add-EnvironmentCheck -Name 'FFmpeg executable responds' -Required $true -Passed ($ffmpegExitCode -eq 0) `
        -Details $(if ($firstVersionLine) { $firstVersionLine } else { "Exit code $ffmpegExitCode" })
    Add-EnvironmentCheck -Name 'FFmpeg AviSynth support' -Required $true `
        -Passed ($ffmpegExitCode -eq 0 -and $ffmpegVersionText -match '--enable-avisynth') `
        -Details $(if ($ffmpegVersionText -match '--enable-avisynth') { 'Build includes --enable-avisynth' } else { 'Build does not report --enable-avisynth' })
}

$rootExists = Test-Path -LiteralPath $AviSynthRoot -PathType Container
Add-EnvironmentCheck -Name 'AviSynth preserved root' -Required $true -Passed $rootExists -Details $AviSynthRoot

$systemDlls = @(
    'C:\Windows\System32\AviSynth.dll',
    'C:\Windows\SysWOW64\AviSynth.dll'
)

foreach ($systemDll in $systemDlls) {
    $is64BitRuntime = $systemDll -like '*\System32\*'
    Add-EnvironmentCheck -Name "AviSynth runtime: $systemDll" -Required $is64BitRuntime `
        -Passed (Test-Path -LiteralPath $systemDll -PathType Leaf) -Details $systemDll
}

$registryPaths = @(
    'Registry::HKEY_LOCAL_MACHINE\Software\AviSynth',
    'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\AviSynth'
)

for ($index = 0; $index -lt $registryPaths.Count; $index++) {
    $registryPath = $registryPaths[$index]
    Add-EnvironmentCheck -Name "AviSynth registration: $registryPath" -Required ($index -eq 0) `
        -Passed (Test-Path -LiteralPath $registryPath) -Details $registryPath
}

$requiredPluginNames = @(
    'ffms2.dll',
    'masktools2.dll',
    'mvtools2.dll',
    'nnedi3.dll',
    'RgTools.dll',
    'QTGMC.avsi',
    'Zs_RF_Shared.avsi'
)

$pluginRoot = Join-Path -Path $AviSynthRoot -ChildPath 'plugins64+'
foreach ($pluginName in $requiredPluginNames) {
    $pluginPath = Join-Path -Path $pluginRoot -ChildPath $pluginName
    Add-EnvironmentCheck -Name "QTGMC dependency: $pluginName" -Required $true `
        -Passed (Test-Path -LiteralPath $pluginPath -PathType Leaf) -Details $pluginPath
}

$requiredFailures = @($checks | Where-Object { $_.Required -and -not $_.Passed })

if ($Json) {
    [pscustomobject]@{
        Ready            = ($requiredFailures.Count -eq 0)
        RequiredFailures = $requiredFailures.Count
        Checks           = $checks
    } | ConvertTo-Json -Depth 5
}
else {
    $checks | Select-Object Name, Required, Passed, Details | Format-Table -AutoSize -Wrap
    Write-Host ''
    if ($requiredFailures.Count -eq 0) {
        Write-Host 'Environment preflight: READY' -ForegroundColor Green
    }
    else {
        Write-Host "Environment preflight: NOT READY ($($requiredFailures.Count) required checks failed)" -ForegroundColor Yellow
        Write-Host 'This is a detection result; the script did not install or modify anything.' -ForegroundColor DarkGray
    }
}

if ($requiredFailures.Count -gt 0) {
    exit 1
}

exit 0
