[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Warn {
    param([string]$Message)
    Write-Verbose $Message
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $true)]
        [string]$MessagePattern
    )

    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notlike $MessagePattern) {
            throw "ASSERTION FAILED: Expected error '$MessagePattern', got '$($_.Exception.Message)'."
        }
        return
    }

    throw "ASSERTION FAILED: Expected error '$MessagePattern', but no error was thrown."
}

. (Join-Path -Path $PSScriptRoot -ChildPath '..\Video\lib\TsSourceCleanup.ps1')

$systemTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = Join-Path -Path $systemTempRoot -ChildPath ('encode-ts-safety-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    Assert-Throws -Action {
        Assert-SourceCleanupRequest -KeepSource -DeleteSource
    } -MessagePattern '*cannot be used together*'

    Assert-Throws -Action {
        Assert-SourceCleanupRequest -DeleteSource -NoVerify
    } -MessagePattern '*requires output verification*'

    $defaultInput = Join-Path -Path $testRoot -ChildPath 'default.ts'
    $defaultOutput = Join-Path -Path $testRoot -ChildPath 'default.mp4'
    Set-Content -LiteralPath $defaultInput -Value 'source'
    Set-Content -LiteralPath $defaultOutput -Value 'output'
    $deletedByDefault = Remove-SourceTsAfterSuccess -InputPath $defaultInput -OutputPath $defaultOutput -VerificationPassed $true -TimestampStatsClean $true
    Assert-True -Condition (-not $deletedByDefault) -Message 'Default cleanup must not report deletion.'
    Assert-True -Condition (Test-Path -LiteralPath $defaultInput) -Message 'Default cleanup must preserve the source.'

    $unverifiedInput = Join-Path -Path $testRoot -ChildPath 'unverified.ts'
    $unverifiedOutput = Join-Path -Path $testRoot -ChildPath 'unverified.mp4'
    Set-Content -LiteralPath $unverifiedInput -Value 'source'
    Set-Content -LiteralPath $unverifiedOutput -Value 'output'
    Assert-Throws -Action {
        Remove-SourceTsAfterSuccess -InputPath $unverifiedInput -OutputPath $unverifiedOutput -DeleteSource -VerificationPassed $false -TimestampStatsClean $true
    } -MessagePattern '*verification did not complete cleanly*'
    Assert-True -Condition (Test-Path -LiteralPath $unverifiedInput) -Message 'Failed verification must preserve the source.'

    $warningInput = Join-Path -Path $testRoot -ChildPath 'warnings.ts'
    $warningOutput = Join-Path -Path $testRoot -ChildPath 'warnings.mp4'
    Set-Content -LiteralPath $warningInput -Value 'source'
    Set-Content -LiteralPath $warningOutput -Value 'output'
    Assert-Throws -Action {
        Remove-SourceTsAfterSuccess -InputPath $warningInput -OutputPath $warningOutput -DeleteSource -VerificationPassed $true -TimestampStatsClean $false
    } -MessagePattern '*timestamp warnings remain*'
    Assert-True -Condition (Test-Path -LiteralPath $warningInput) -Message 'Timestamp warnings must preserve the source.'

    $verifiedInput = Join-Path -Path $testRoot -ChildPath 'verified.ts'
    $verifiedOutput = Join-Path -Path $testRoot -ChildPath 'verified.mp4'
    Set-Content -LiteralPath $verifiedInput -Value 'source'
    Set-Content -LiteralPath $verifiedOutput -Value 'output'
    $deletedAfterVerification = Remove-SourceTsAfterSuccess -InputPath $verifiedInput -OutputPath $verifiedOutput -DeleteSource -VerificationPassed $true -TimestampStatsClean $true
    Assert-True -Condition $deletedAfterVerification -Message 'Explicit clean cleanup must report deletion.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $verifiedInput)) -Message 'Explicit clean cleanup must delete the source.'
    Assert-True -Condition (Test-Path -LiteralPath $verifiedOutput) -Message 'Source cleanup must preserve the output.'

    Write-Host 'PASS: TS source cleanup safety contract.' -ForegroundColor Green
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $expectedPrefix = Join-Path -Path $systemTempRoot -ChildPath 'encode-ts-safety-tests-'
    if ((Test-Path -LiteralPath $resolvedTestRoot) -and $resolvedTestRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
