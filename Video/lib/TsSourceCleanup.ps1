function Assert-SourceCleanupRequest {
    param(
        [Parameter()]
        [switch]$KeepSource,

        [Parameter()]
        [switch]$DeleteSource,

        [Parameter()]
        [switch]$NoVerify
    )

    if ($KeepSource -and $DeleteSource) {
        throw '-KeepSource and -DeleteSource cannot be used together.'
    }

    if ($DeleteSource -and $NoVerify) {
        throw '-DeleteSource requires output verification. Remove -NoVerify or keep the source.'
    }
}

function Remove-SourceTsAfterSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter()]
        [switch]$KeepSource,

        [Parameter()]
        [switch]$DeleteSource,

        [Parameter(Mandatory = $true)]
        [bool]$VerificationPassed,

        [Parameter(Mandatory = $true)]
        [bool]$TimestampStatsClean
    )

    if ($KeepSource) {
        Write-Warn 'Source file kept because -KeepSource was used.'
        return $false
    }

    if (-not $DeleteSource) {
        Write-Warn 'Source file kept by default. Use -DeleteSource only when deletion is intentional.'
        return $false
    }

    if (-not $VerificationPassed) {
        throw 'Source was preserved because output verification did not complete cleanly.'
    }

    if (-not $TimestampStatsClean) {
        throw 'Source was preserved because timestamp warnings remain in the output.'
    }

    if ([IO.Path]::GetExtension($InputPath) -ne '.ts') {
        throw "Source was preserved because it is not a .ts file: $InputPath"
    }

    $resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
    $resolvedOutput = (Resolve-Path -LiteralPath $OutputPath).Path
    if ([string]::Equals($resolvedInput, $resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to delete source because input and output resolved to the same path.'
    }

    $outputItem = Get-Item -LiteralPath $resolvedOutput
    if ($outputItem.Length -le 0) {
        throw "Refusing to delete source because output is empty: $resolvedOutput"
    }

    Remove-Item -LiteralPath $resolvedInput -Force
    Write-Host ('🗑️  Deleted source TS after explicit request and clean verification: {0}' -f $resolvedInput) -ForegroundColor DarkGray
    return $true
}
