[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..\no_audio\Move-NoAudio.ps1'
$testRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath "MoveNoAudioSafety-$([guid]::NewGuid().ToString('N'))"
$originalPath = $env:PATH
$originalMode = $env:FFPROBE_TEST_MODE

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-SafetyCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [bool]$ExpectMove,

        [string]$ExpectedErrorText,

        [switch]$CreateCollision
    )

    $caseDirectory = Join-Path -Path $testRoot -ChildPath $Name
    $sourcePath = Join-Path -Path $caseDirectory -ChildPath 'sample.mp4'
    $destinationDirectory = Join-Path -Path $caseDirectory -ChildPath 'no_audio'
    $destinationPath = Join-Path -Path $destinationDirectory -ChildPath 'sample.mp4'

    New-Item -ItemType Directory -Path $caseDirectory | Out-Null
    Set-Content -LiteralPath $sourcePath -Value 'source-content' -Encoding Ascii

    if ($CreateCollision) {
        New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
        Set-Content -LiteralPath $destinationPath -Value 'existing-content' -Encoding Ascii
    }

    $env:FFPROBE_TEST_MODE = $Mode
    if ($Mode -eq 'launch-failure') {
        $env:PATH = $emptyPathDirectory
    }
    else {
        $env:PATH = $shimDirectory
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $scriptPath -TargetDirectory $caseDirectory 2>&1)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($ExpectMove) {
        Assert-Condition -Condition (-not (Test-Path -LiteralPath $sourcePath)) -Message "$Name`: το source δεν μετακινήθηκε."
        Assert-Condition -Condition (Test-Path -LiteralPath $destinationPath -PathType Leaf) -Message "$Name`: δεν δημιουργήθηκε destination."
        Assert-Condition -Condition ((Get-Content -LiteralPath $destinationPath -Raw).Trim() -eq 'source-content') -Message "$Name`: το moved περιεχόμενο άλλαξε."
    }
    else {
        Assert-Condition -Condition (Test-Path -LiteralPath $sourcePath -PathType Leaf) -Message "$Name`: το source μετακινήθηκε απρόσμενα."

        if ($CreateCollision) {
            Assert-Condition -Condition ((Get-Content -LiteralPath $destinationPath -Raw).Trim() -eq 'existing-content') -Message "$Name`: ο υπάρχων προορισμός αντικαταστάθηκε."
        }
        else {
            Assert-Condition -Condition (-not (Test-Path -LiteralPath $destinationPath)) -Message "$Name`: δημιουργήθηκε destination απρόσμενα."
        }
    }

    if (-not [string]::IsNullOrEmpty($ExpectedErrorText)) {
        $combinedOutput = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        Assert-Condition -Condition ($combinedOutput.Contains($ExpectedErrorText)) -Message "$Name`: δεν βρέθηκε το αναμενόμενο error '$ExpectedErrorText'."
    }

    Write-Output "PASS: $Name"
}

try {
    $shimDirectory = Join-Path -Path $testRoot -ChildPath 'shim'
    $emptyPathDirectory = Join-Path -Path $testRoot -ChildPath 'empty-path'
    New-Item -ItemType Directory -Path $shimDirectory, $emptyPathDirectory -Force | Out-Null

    $ffprobeShim = @'
@echo off
if "%FFPROBE_TEST_MODE%"=="nonzero" (
  echo synthetic probe failure 1>&2
  exit /b 23
)
if "%FFPROBE_TEST_MODE%"=="invalid-output" (
  echo video
  exit /b 0
)
if "%FFPROBE_TEST_MODE%"=="audio" (
  echo audio
  exit /b 0
)
if "%FFPROBE_TEST_MODE%"=="no-audio" exit /b 0
echo unknown test mode 1>&2
exit /b 99
'@
    Set-Content -LiteralPath (Join-Path -Path $shimDirectory -ChildPath 'ffprobe.cmd') -Value $ffprobeShim -Encoding Ascii

    Invoke-SafetyCase -Name '01-launch-failure' -Mode 'launch-failure' -ExpectMove $false -ExpectedErrorText 'Αποτυχία εκκίνησης ffprobe'
    Invoke-SafetyCase -Name '02-nonzero-exit' -Mode 'nonzero' -ExpectMove $false -ExpectedErrorText 'exit code 23'
    Invoke-SafetyCase -Name '03-invalid-output' -Mode 'invalid-output' -ExpectMove $false -ExpectedErrorText 'μη αναμενόμενο αποτέλεσμα'
    Invoke-SafetyCase -Name '04-valid-audio' -Mode 'audio' -ExpectMove $false
    Invoke-SafetyCase -Name '05-valid-no-audio' -Mode 'no-audio' -ExpectMove $true
    Invoke-SafetyCase -Name '06-existing-destination' -Mode 'no-audio' -ExpectMove $false -ExpectedErrorText 'δεν θα αντικατασταθεί' -CreateCollision

    Write-Output 'PASS: Move-NoAudio failure and collision safety contract'
}
finally {
    $env:PATH = $originalPath
    $env:FFPROBE_TEST_MODE = $originalMode

    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
