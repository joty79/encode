Set-StrictMode -Version Latest

function Resolve-SubtitleTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$KnownPaths = @()
    )

    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }

    foreach ($candidate in $KnownPaths) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Required command '$Name' was not found on PATH or at a known installation path."
}

function ConvertTo-SubtitleNativeArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
        }
        else {
            if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)) }
            [void]$builder.Append($character)
        }
        $backslashes = 0
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-SubtitleNative {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Exe
    $startInfo.Arguments = (($Arguments | ForEach-Object {
        ConvertTo-SubtitleNativeArgument -Value $_
    }) -join ' ')
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
        Stdout   = $stdout.GetAwaiter().GetResult()
        Stderr   = $stderr.GetAwaiter().GetResult()
    }
}

function Get-SubtitleNativeFailureText {
    param([Parameter(Mandatory = $true)][object]$Result)

    return (($Result.Stdout, $Result.Stderr | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }) -join [Environment]::NewLine).Trim()
}
