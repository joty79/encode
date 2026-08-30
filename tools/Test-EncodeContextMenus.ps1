[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$CatalogPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\ContextMenu-Catalog.json'),
    [string]$OutputDirectory,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
    throw "Repository root was not found: $resolvedRepoRoot"
}

function ConvertFrom-RegString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    return $Value.Replace('\"', '"').Replace('\\', '\')
}

function Get-HiveInfo {
    param([Parameter(Mandatory)][string]$RegistryKey)

    $prefixes = [ordered]@{
        'HKEY_LOCAL_MACHINE\Software\Classes\' = 'HKLM'
        'HKEY_CURRENT_USER\Software\Classes\'  = 'HKCU'
        'HKEY_CLASSES_ROOT\'                    = 'HKCR'
    }
    foreach ($prefix in $prefixes.Keys) {
        if ($RegistryKey.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Hive = $prefixes[$prefix]
                RelativePath = $RegistryKey.Substring($prefix.Length)
            }
        }
    }
    return $null
}

function Get-ContextRootInfo {
    param([Parameter(Mandatory)][string]$RegistryKey)

    $hiveInfo = Get-HiveInfo -RegistryKey $RegistryKey
    if ($null -eq $hiveInfo) {
        return $null
    }

    $marker = '\shell\'
    $shellIndex = $hiveInfo.RelativePath.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
    if ($shellIndex -lt 1) {
        return $null
    }

    $targetPath = $hiveInfo.RelativePath.Substring(0, $shellIndex)
    $afterShell = $hiveInfo.RelativePath.Substring($shellIndex + $marker.Length)
    $verb = ($afterShell -split '\\', 2)[0]
    if ([string]::IsNullOrWhiteSpace($verb)) {
        return $null
    }

    $targetType = 'Class'
    $target = $targetPath
    if ($targetPath.StartsWith('SystemFileAssociations\', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetType = 'Extension'
        $target = $targetPath.Substring('SystemFileAssociations\'.Length)
    }
    elseif ($targetPath.Equals('Directory', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetType = 'Folder'
        $target = 'Directory'
    }
    elseif ($targetPath.Equals('Directory\Background', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetType = 'FolderBackground'
        $target = 'Directory background'
    }
    elseif ($targetPath.Equals('*', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetType = 'AllFiles'
        $target = '*'
    }
    elseif ($targetPath.Equals('AllFilesystemObjects', [System.StringComparison]::OrdinalIgnoreCase)) {
        $targetType = 'AllFilesystemObjects'
        $target = 'AllFilesystemObjects'
    }

    return [pscustomobject]@{
        Hive = $hiveInfo.Hive
        RelativeRoot = "$targetPath\shell\$verb"
        TargetType = $targetType
        Target = $target
        Verb = $verb
    }
}

function Get-NativeRegistryQuery {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Arguments = @()
    )

    $output = & reg.exe query $Path @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Test-NativeRegistryKey {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-NativeRegistryQuery -Path $Path).ExitCode -eq 0
}

function Get-ReferencedRepoPaths {
    param([string[]]$Values)

    $escapedRoot = [regex]::Escape($resolvedRepoRoot)
    $pattern = '(?i)(?<path>{0}\\[^"\r\n]+?\.(?:ps1|psm1|vbs|exe|ico|bat|cmd))' -f $escapedRoot
    $paths = foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }
        foreach ($match in [regex]::Matches($value, $pattern)) {
            $match.Groups['path'].Value
        }
    }
    return @($paths | Sort-Object -Unique)
}

function Get-LiveLabel {
    param([Parameter(Mandatory)][string]$Path)

    $query = Get-NativeRegistryQuery -Path $Path
    if ($query.ExitCode -ne 0) {
        return $null
    }
    $defaultValue = $null
    foreach ($line in $query.Output) {
        if ($line -match '^\s+MUIVerb\s+REG_\w+\s+(?<value>.*)$') {
            return $Matches.value.Trim()
        }
        if ($line -match '^\s+\(Default\)\s+REG_\w+\s+(?<value>.*)$') {
            $defaultValue = $Matches.value.Trim()
        }
    }
    return $defaultValue
}

function ConvertTo-ComparableRegistryData {
    param(
        [Parameter(Mandatory)][string]$Type,
        [AllowEmptyString()][string]$Data
    )

    if ($Type -eq 'REG_DWORD') {
        if ($Data -match '^0x(?<hex>[0-9a-fA-F]+)$') {
            return [Convert]::ToUInt32($Matches.hex, 16).ToString()
        }
        if ($Data -match '^[0-9a-fA-F]{8}$') {
            return [Convert]::ToUInt32($Data, 16).ToString()
        }
    }
    return $Data
}

function Get-FullHivePrefix {
    param([Parameter(Mandatory)][ValidateSet('HKLM', 'HKCU')][string]$Hive)

    if ($Hive -eq 'HKLM') {
        return 'HKEY_LOCAL_MACHINE\Software\Classes\'
    }
    return 'HKEY_CURRENT_USER\Software\Classes\'
}

function Get-LiveRegistryTree {
    param([Parameter(Mandatory)][string]$Path)

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $values = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $query = Get-NativeRegistryQuery -Path $Path -Arguments @('/s')
    if ($query.ExitCode -ne 0) {
        return [pscustomobject]@{ Exists = $false; Keys = $keys; Values = $values }
    }
    $currentKey = $null
    foreach ($line in $query.Output) {
        if ($line -match '^HKEY_') {
            $currentKey = $line.Trim()
            $null = $keys.Add($currentKey)
            continue
        }
        if ($null -eq $currentKey) {
            continue
        }
        if ($line -match '^\s+(?<name>.*?)\s{2,}(?<type>REG_[A-Z0-9_]+)(?:\s{2,}(?<data>.*))?$') {
            $name = $Matches.name.Trim()
            $type = $Matches.type
            $data = if ($Matches.ContainsKey('data')) { $Matches.data } else { '' }
            $identity = "$currentKey$([char]31)$name"
            $values[$identity] = [pscustomobject]@{
                Key = $currentKey
                Name = $name
                Type = $type
                Data = ConvertTo-ComparableRegistryData -Type $type -Data $data
            }
        }
    }
    return [pscustomobject]@{ Exists = $true; Keys = $keys; Values = $values }
}

function ConvertTo-MarkdownCell {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", '<br>')
}

function ConvertTo-NormalizedRepoPath {
    param([Parameter(Mandatory)][string]$Path)

    return $Path.Replace('/', '\').TrimStart('\')
}

$regFiles = @(Get-ChildItem -LiteralPath $resolvedRepoRoot -Recurse -Filter '*.reg' -File | Sort-Object FullName)
$sections = [System.Collections.Generic.List[object]]::new()

foreach ($regFile in $regFiles) {
    $currentSection = $null
    foreach ($line in Get-Content -LiteralPath $regFile.FullName) {
        if ($line -match '^\[(?<delete>-?)(?<key>HKEY_[^\]]+)\]$') {
            $currentSection = $null
            if ($Matches.delete -eq '-') {
                continue
            }
            $context = Get-ContextRootInfo -RegistryKey $Matches.key
            if ($null -eq $context) {
                continue
            }
            $currentSection = [pscustomobject]@{
                File = $regFile.FullName
                Key = $Matches.key
                Context = $context
                Values = [ordered]@{}
            }
            $sections.Add($currentSection)
            continue
        }
        if ($null -eq $currentSection) {
            continue
        }
        if ($line -match '^@="(?<value>(?:\\.|[^"])*)"$') {
            $currentSection.Values['(Default)'] = [pscustomobject]@{
                Type = 'REG_SZ'
                Data = ConvertFrom-RegString -Value $Matches.value
            }
            continue
        }
        if ($line -match '^"(?<name>[^"]+)"="(?<value>(?:\\.|[^"])*)"$') {
            $currentSection.Values[$Matches.name] = [pscustomobject]@{
                Type = 'REG_SZ'
                Data = ConvertFrom-RegString -Value $Matches.value
            }
            continue
        }
        if ($line -match '^"(?<name>[^"]+)"=dword:(?<value>[0-9a-fA-F]{8})$') {
            $currentSection.Values[$Matches.name] = [pscustomobject]@{
                Type = 'REG_DWORD'
                Data = ConvertTo-ComparableRegistryData -Type 'REG_DWORD' -Data $Matches.value
            }
        }
    }
}

$sourceGroups = @($sections | Group-Object { '{0}|{1}' -f $_.File, $_.Context.RelativeRoot.ToLowerInvariant() })
$sourceDefinitions = foreach ($group in $sourceGroups) {
    $first = $group.Group[0]
    $rootSection = $group.Group | Where-Object { $_.Key.EndsWith($first.Context.RelativeRoot, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    $allValues = @($group.Group | ForEach-Object { $_.Values.Values | ForEach-Object Data })
    $commands = @(
        $group.Group |
            Where-Object { $_.Key.EndsWith('\command', [System.StringComparison]::OrdinalIgnoreCase) -and $_.Values.Contains('(Default)') } |
            ForEach-Object { $_.Values['(Default)'].Data }
    )
    $repoPaths = @(Get-ReferencedRepoPaths -Values $allValues)
    $missingPaths = @($repoPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    $label = $first.Context.Verb
    if ($null -ne $rootSection) {
        if ($rootSection.Values.Contains('MUIVerb')) {
            $label = $rootSection.Values['MUIVerb'].Data
        }
        elseif ($rootSection.Values.Contains('(Default)')) {
            $label = $rootSection.Values['(Default)'].Data
        }
    }

    $hklmPath = "HKLM\Software\Classes\$($first.Context.RelativeRoot)"
    $hkcuPath = "HKCU\Software\Classes\$($first.Context.RelativeRoot)"
    $liveHklm = Test-NativeRegistryKey -Path $hklmPath
    $liveHkcu = Test-NativeRegistryKey -Path $hkcuPath
    $expectedHivePresent = switch ($first.Context.Hive) {
        'HKLM' { $liveHklm }
        'HKCU' { $liveHkcu }
        'HKCR' { $liveHklm -or $liveHkcu }
    }
    $liveLocation = if ($liveHklm -and $liveHkcu) {
        'HKLM + HKCU'
    } elseif ($liveHklm) {
        'HKLM'
    } elseif ($liveHkcu) {
        'HKCU'
    } else {
        'Missing'
    }

    $comparisonHive = switch ($first.Context.Hive) {
        'HKLM' { 'HKLM' }
        'HKCU' { 'HKCU' }
        'HKCR' { if ($liveHklm) { 'HKLM' } elseif ($liveHkcu) { 'HKCU' } else { 'HKLM' } }
    }
    $comparisonRoot = "$comparisonHive\Software\Classes\$($first.Context.RelativeRoot)"
    $liveTree = Get-LiveRegistryTree -Path $comparisonRoot
    $expectedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $expectedValues = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $fullHivePrefix = Get-FullHivePrefix -Hive $comparisonHive
    foreach ($section in $group.Group) {
        $sectionHive = Get-HiveInfo -RegistryKey $section.Key
        $expectedKey = "$fullHivePrefix$($sectionHive.RelativePath)"
        $null = $expectedKeys.Add($expectedKey)
        $expectedRootKey = "$fullHivePrefix$($first.Context.RelativeRoot)"
        $ancestorKey = $expectedKey
        while (-not $ancestorKey.Equals($expectedRootKey, [System.StringComparison]::OrdinalIgnoreCase)) {
            $separatorIndex = $ancestorKey.LastIndexOf('\')
            if ($separatorIndex -lt $expectedRootKey.Length) {
                break
            }
            $ancestorKey = $ancestorKey.Substring(0, $separatorIndex)
            $null = $expectedKeys.Add($ancestorKey)
        }
        foreach ($valueEntry in $section.Values.GetEnumerator()) {
            $identity = "$expectedKey$([char]31)$($valueEntry.Key)"
            $expectedValues[$identity] = [pscustomobject]@{
                Key = $expectedKey
                Name = $valueEntry.Key
                Type = $valueEntry.Value.Type
                Data = $valueEntry.Value.Data
            }
        }
    }
    $missingSections = @($expectedKeys | Where-Object { -not $liveTree.Keys.Contains($_) } | Sort-Object)
    $extraSections = @($liveTree.Keys | Where-Object { -not $expectedKeys.Contains($_) } | Sort-Object)
    $valueMismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($expectedValue in $expectedValues.GetEnumerator()) {
        if (-not $liveTree.Values.ContainsKey($expectedValue.Key)) {
            $valueMismatches.Add("missing: $($expectedValue.Value.Key) :: $($expectedValue.Value.Name)")
            continue
        }
        $actualValue = $liveTree.Values[$expectedValue.Key]
        if ($actualValue.Type -ne $expectedValue.Value.Type -or $actualValue.Data -cne $expectedValue.Value.Data) {
            $valueMismatches.Add("different: $($expectedValue.Value.Key) :: $($expectedValue.Value.Name)")
        }
    }
    $extraValues = @($liveTree.Values.Keys | Where-Object { -not $expectedValues.ContainsKey($_) } | ForEach-Object { $liveTree.Values[$_] } | Sort-Object Key, Name)

    [pscustomobject]@{
        SourceFile = $first.File.Substring($resolvedRepoRoot.Length + 1)
        SourceHive = $first.Context.Hive
        RelativeRoot = $first.Context.RelativeRoot
        TargetType = $first.Context.TargetType
        Target = $first.Context.Target
        Verb = $first.Context.Verb
        Label = $label
        CommandCount = $commands.Count
        Commands = $commands
        ReferencedPaths = $repoPaths
        MissingReferencedPaths = $missingPaths
        LiveHKLM = $liveHklm
        LiveHKCU = $liveHkcu
        LiveLocation = $liveLocation
        ExpectedHivePresent = $expectedHivePresent
        AmbiguousSourceHive = $first.Context.Hive -eq 'HKCR'
        ComparisonHive = $comparisonHive
        ExpectedSectionCount = $expectedKeys.Count
        LiveSectionCount = $liveTree.Keys.Count
        MissingSections = $missingSections
        ExtraSections = $extraSections
        ValueMismatches = @($valueMismatches)
        ExtraValues = $extraValues
        ExactTreeMatch = $missingSections.Count -eq 0 -and $extraSections.Count -eq 0 -and $valueMismatches.Count -eq 0 -and $extraValues.Count -eq 0
    }
}

$sourceDefinitions = @($sourceDefinitions | Sort-Object SourceFile, RelativeRoot)
$resolvedCatalogPath = [System.IO.Path]::GetFullPath($CatalogPath)
if (-not (Test-Path -LiteralPath $resolvedCatalogPath -PathType Leaf)) {
    throw "Context-menu catalog was not found: $resolvedCatalogPath"
}
$catalog = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json
if ($catalog.schemaVersion -ne 1 -or $null -eq $catalog.artifacts) {
    throw "Unsupported or invalid context-menu catalog: $resolvedCatalogPath"
}
$catalogGroups = @($catalog.artifacts | Group-Object { (ConvertTo-NormalizedRepoPath $_.sourceFile).ToLowerInvariant() })
$duplicateCatalogSourceFiles = @($catalogGroups | Where-Object Count -gt 1 | ForEach-Object Name)
$catalogByFile = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($artifact in $catalog.artifacts) {
    $normalizedSourceFile = ConvertTo-NormalizedRepoPath $artifact.sourceFile
    if (-not $catalogByFile.ContainsKey($normalizedSourceFile)) {
        $catalogByFile[$normalizedSourceFile] = $artifact
    }
}
foreach ($definition in $sourceDefinitions) {
    $artifact = if ($catalogByFile.ContainsKey($definition.SourceFile)) { $catalogByFile[$definition.SourceFile] } else { $null }
    $definition | Add-Member -NotePropertyName Cataloged -NotePropertyValue ($null -ne $artifact)
    $definition | Add-Member -NotePropertyName CatalogKind -NotePropertyValue $(if ($null -ne $artifact) { $artifact.kind } else { $null })
    $definition | Add-Member -NotePropertyName Lifecycle -NotePropertyValue $(if ($null -ne $artifact) { $artifact.lifecycle } else { $null })
    $definition | Add-Member -NotePropertyName PlannedDisposition -NotePropertyValue $(if ($null -ne $artifact) { $artifact.plannedDisposition } else { $null })
    $definition | Add-Member -NotePropertyName CatalogHivePolicy -NotePropertyValue $(if ($null -ne $artifact) { $artifact.hivePolicy } else { $null })
}

$allRegRelativePaths = @($regFiles | ForEach-Object { $_.FullName.Substring($resolvedRepoRoot.Length + 1) })
$uncatalogedRegFiles = @($allRegRelativePaths | Where-Object { -not $catalogByFile.ContainsKey($_) } | Sort-Object)
$catalogEntriesMissingFiles = @($catalog.artifacts | ForEach-Object { ConvertTo-NormalizedRepoPath $_.sourceFile } | Where-Object { -not (Test-Path -LiteralPath (Join-Path $resolvedRepoRoot $_) -PathType Leaf) } | Sort-Object -Unique)
$catalogDefinitionCountMismatches = [System.Collections.Generic.List[object]]::new()
$catalogHivePolicyMismatches = [System.Collections.Generic.List[object]]::new()
foreach ($artifact in $catalog.artifacts) {
    $normalizedSourceFile = ConvertTo-NormalizedRepoPath $artifact.sourceFile
    $definitionsForFile = @($sourceDefinitions | Where-Object SourceFile -EQ $normalizedSourceFile)
    if ($definitionsForFile.Count -ne [int]$artifact.expectedDefinitionCount) {
        $catalogDefinitionCountMismatches.Add([pscustomobject]@{
            SourceFile = $normalizedSourceFile
            Expected = [int]$artifact.expectedDefinitionCount
            Actual = $definitionsForFile.Count
        })
    }
    $observedHives = @($definitionsForFile | ForEach-Object SourceHive | Sort-Object -Unique)
    $hivePolicyMatches = switch ([string]$artifact.hivePolicy) {
        'ambiguous-hkcr' { $definitionsForFile.Count -gt 0 -and @($definitionsForFile | Where-Object SourceHive -NE 'HKCR').Count -eq 0 }
        'explicit-hklm' { $definitionsForFile.Count -gt 0 -and @($definitionsForFile | Where-Object SourceHive -NE 'HKLM').Count -eq 0 }
        'explicit-hkcu' { $definitionsForFile.Count -gt 0 -and @($definitionsForFile | Where-Object SourceHive -NE 'HKCU').Count -eq 0 }
        'explicit-mixed' { $definitionsForFile.Count -gt 0 -and -not ($observedHives -contains 'HKCR') }
        default { $false }
    }
    if ($artifact.kind -in @('registry-tweak', 'removal-artifact') -and $definitionsForFile.Count -eq 0) {
        $hivePolicyMatches = $true
    }
    if (-not $hivePolicyMatches) {
        $catalogHivePolicyMismatches.Add([pscustomobject]@{
            SourceFile = $normalizedSourceFile
            DeclaredPolicy = $artifact.hivePolicy
            ObservedHives = $observedHives
        })
    }
}

$sourceLogicalRoots = @($sourceDefinitions.RelativeRoot | ForEach-Object ToLowerInvariant | Sort-Object -Unique)
$duplicateSourceRoots = @(
    $sourceDefinitions |
        Group-Object { $_.RelativeRoot.ToLowerInvariant() } |
        Where-Object Count -gt 1 |
        ForEach-Object {
            [pscustomobject]@{
                RelativeRoot = $_.Group[0].RelativeRoot
                SourceFiles = @($_.Group.SourceFile | Sort-Object -Unique)
                DefinitionCount = $_.Count
            }
        }
)

$liveMatches = [System.Collections.Generic.List[object]]::new()
foreach ($liveHive in @(
    [pscustomobject]@{ Name = 'HKLM'; SearchRoot = 'HKLM\Software\Classes' },
    [pscustomobject]@{ Name = 'HKCU'; SearchRoot = 'HKCU\Software\Classes' }
)) {
    $query = Get-NativeRegistryQuery -Path $liveHive.SearchRoot -Arguments @('/s', '/f', $resolvedRepoRoot, '/d')
    if ($query.ExitCode -ne 0) {
        continue
    }
    $currentKey = $null
    foreach ($line in $query.Output) {
        if ($line -match '^HKEY_') {
            $currentKey = $line.Trim()
            continue
        }
        if ($null -eq $currentKey -or -not $line.Contains($resolvedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $context = Get-ContextRootInfo -RegistryKey $currentKey
        if ($null -eq $context) {
            continue
        }
        $data = $line.Trim()
        if ($data -match '^(?:\(Default\)|[^\s]+)\s+REG_\w+\s+(?<value>.*)$') {
            $data = $Matches.value
        }
        $liveMatches.Add([pscustomobject]@{
            Hive = $liveHive.Name
            RegistryKey = $currentKey
            RelativeRoot = $context.RelativeRoot
            TargetType = $context.TargetType
            Target = $context.Target
            Verb = $context.Verb
            Data = $data
        })
    }
}

$liveDefinitions = foreach ($group in ($liveMatches | Group-Object { '{0}|{1}' -f $_.Hive, $_.RelativeRoot.ToLowerInvariant() })) {
    $first = $group.Group[0]
    $rootPath = "$($first.Hive)\Software\Classes\$($first.RelativeRoot)"
    $referencedPaths = @(Get-ReferencedRepoPaths -Values @($group.Group.Data))
    [pscustomobject]@{
        Hive = $first.Hive
        RelativeRoot = $first.RelativeRoot
        TargetType = $first.TargetType
        Target = $first.Target
        Verb = $first.Verb
        Label = Get-LiveLabel -Path $rootPath
        MatchingValueCount = $group.Count
        ReferencedPaths = $referencedPaths
        MissingReferencedPaths = @($referencedPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
        TrackedByRegSource = $sourceLogicalRoots -contains $first.RelativeRoot.ToLowerInvariant()
    }
}
$liveDefinitions = @($liveDefinitions | Sort-Object TargetType, Target, Hive, Verb)

$missingSourceDefinitions = @($sourceDefinitions | Where-Object { -not $_.ExpectedHivePresent })
$ambiguousSourceDefinitions = @($sourceDefinitions | Where-Object AmbiguousSourceHive)
$brokenSourceDefinitions = @($sourceDefinitions | Where-Object { $_.MissingReferencedPaths.Count -gt 0 })
$treeMismatchDefinitions = @($sourceDefinitions | Where-Object { -not $_.ExactTreeMatch })
$unexpectedLiveDefinitions = @($liveDefinitions | Where-Object { -not $_.TrackedByRegSource })
$brokenLiveDefinitions = @($liveDefinitions | Where-Object { $_.MissingReferencedPaths.Count -gt 0 })

$summary = [ordered]@{
    GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
    RepoRoot = $resolvedRepoRoot
    RegFilesScanned = $regFiles.Count
    SourceDefinitions = $sourceDefinitions.Count
    UniqueSourceLogicalRoots = $sourceLogicalRoots.Count
    LiveEncodeOwnedRoots = $liveDefinitions.Count
    MissingSourceDefinitions = $missingSourceDefinitions.Count
    UnexpectedLiveRoots = $unexpectedLiveDefinitions.Count
    AmbiguousHKCRSourceDefinitions = $ambiguousSourceDefinitions.Count
    DuplicateSourceLogicalRoots = $duplicateSourceRoots.Count
    BrokenSourceTargetDefinitions = $brokenSourceDefinitions.Count
    BrokenLiveTargetDefinitions = $brokenLiveDefinitions.Count
    ExactTreeMismatchDefinitions = $treeMismatchDefinitions.Count
    CatalogArtifacts = @($catalog.artifacts).Count
    UncatalogedRegFiles = $uncatalogedRegFiles.Count
    CatalogEntriesMissingFiles = $catalogEntriesMissingFiles.Count
    CatalogDefinitionCountMismatches = $catalogDefinitionCountMismatches.Count
    CatalogHivePolicyMismatches = $catalogHivePolicyMismatches.Count
    DuplicateCatalogSourceFiles = $duplicateCatalogSourceFiles.Count
}

$audit = [ordered]@{
    Summary = $summary
    SourceDefinitions = $sourceDefinitions
    LiveDefinitions = $liveDefinitions
    MissingSourceDefinitions = $missingSourceDefinitions
    UnexpectedLiveDefinitions = $unexpectedLiveDefinitions
    AmbiguousSourceDefinitions = $ambiguousSourceDefinitions
    DuplicateSourceRoots = $duplicateSourceRoots
    BrokenSourceDefinitions = $brokenSourceDefinitions
    BrokenLiveDefinitions = $brokenLiveDefinitions
    TreeMismatchDefinitions = $treeMismatchDefinitions
    Catalog = $catalog
    UncatalogedRegFiles = $uncatalogedRegFiles
    CatalogEntriesMissingFiles = $catalogEntriesMissingFiles
    CatalogDefinitionCountMismatches = @($catalogDefinitionCountMismatches)
    CatalogHivePolicyMismatches = @($catalogHivePolicyMismatches)
    DuplicateCatalogSourceFiles = $duplicateCatalogSourceFiles
}

if (-not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
    [System.IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
    $jsonPath = Join-Path $resolvedOutputDirectory 'Context-Menu-Inventory.json'
    $markdownPath = Join-Path $resolvedOutputDirectory 'Context-Menu-Inventory.md'
    [System.IO.File]::WriteAllText($jsonPath, (($audit | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))

    $markdown = [System.Collections.Generic.List[string]]::new()
    $markdown.Add('# Encode Context-Menu Inventory')
    $markdown.Add('')
    $markdown.Add('Generated by `tools/Test-EncodeContextMenus.ps1`. Registry access is read-only.')
    $markdown.Add('')
    $markdown.Add('## Summary')
    $markdown.Add('')
    $markdown.Add('| Metric | Count |')
    $markdown.Add('|---|---:|')
    foreach ($entry in $summary.GetEnumerator()) {
        if ($entry.Key -in @('GeneratedAt', 'RepoRoot')) { continue }
        $markdown.Add("| $(ConvertTo-MarkdownCell $entry.Key) | $(ConvertTo-MarkdownCell $entry.Value) |")
    }
    $markdown.Add('')
    $markdown.Add('This is an evidence inventory, not yet the final production manifest. `HKCR` source definitions are intentionally flagged because they do not state whether HKLM or HKCU owns the installed key.')

    $markdown.Add('')
    $markdown.Add('## Source files')
    $markdown.Add('')
    $markdown.Add('| `.reg` file | Lifecycle | Disposition | Definitions | HKCR ambiguous | Missing expected live | Tree mismatches | Broken targets |')
    $markdown.Add('|---|---|---|---:|---:|---:|---:|---:|')
    foreach ($fileGroup in ($sourceDefinitions | Group-Object SourceFile | Sort-Object Name)) {
        $rows = @($fileGroup.Group)
        $markdown.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f (ConvertTo-MarkdownCell $fileGroup.Name), (ConvertTo-MarkdownCell $rows[0].Lifecycle), (ConvertTo-MarkdownCell $rows[0].PlannedDisposition), $rows.Count, @($rows | Where-Object AmbiguousSourceHive).Count, @($rows | Where-Object { -not $_.ExpectedHivePresent }).Count, @($rows | Where-Object { -not $_.ExactTreeMatch }).Count, @($rows | Where-Object { $_.MissingReferencedPaths.Count -gt 0 }).Count))
    }

    $markdown.Add('')
    $markdown.Add('## Classification coverage')
    $markdown.Add('')
    $markdown.Add('| Lifecycle | Artifact count |')
    $markdown.Add('|---|---:|')
    foreach ($lifecycleGroup in ($catalog.artifacts | Group-Object lifecycle | Sort-Object Name)) {
        $markdown.Add(('| {0} | {1} |' -f (ConvertTo-MarkdownCell $lifecycleGroup.Name), $lifecycleGroup.Count))
    }
    $markdown.Add('')
    $markdown.Add(('- Uncataloged `.reg` files: {0}' -f $uncatalogedRegFiles.Count))
    $markdown.Add(('- Catalog entries with missing files: {0}' -f $catalogEntriesMissingFiles.Count))
    $markdown.Add(('- Definition-count mismatches: {0}' -f $catalogDefinitionCountMismatches.Count))
    $markdown.Add(('- Hive-policy mismatches: {0}' -f $catalogHivePolicyMismatches.Count))
    $markdown.Add(('- Duplicate catalog source paths: {0}' -f $duplicateCatalogSourceFiles.Count))

    $markdown.Add('')
    $markdown.Add('## Installed Encode-owned top-level verbs')
    $markdown.Add('')
    $markdown.Add('| Target | Hive | Verb | Label | Source definition | Values referencing Encode |')
    $markdown.Add('|---|---|---|---|---|---:|')
    foreach ($item in $liveDefinitions) {
        $tracked = if ($item.TrackedByRegSource) { 'yes' } else { '**no**' }
        $markdown.Add(('| `{0}` | {1} | `{2}` | {3} | {4} | {5} |' -f (ConvertTo-MarkdownCell $item.Target), $item.Hive, (ConvertTo-MarkdownCell $item.Verb), (ConvertTo-MarkdownCell $item.Label), $tracked, $item.MatchingValueCount))
    }

    $markdown.Add('')
    $markdown.Add('## Missing source definitions')
    $markdown.Add('')
    if ($missingSourceDefinitions.Count -eq 0) {
        $markdown.Add('None.')
    }
    else {
        $markdown.Add('| Source | Expected hive | Target | Verb | Observed live location |')
        $markdown.Add('|---|---|---|---|---|')
        foreach ($item in $missingSourceDefinitions) {
            $markdown.Add(('| `{0}` | {1} | `{2}` | `{3}` | {4} |' -f (ConvertTo-MarkdownCell $item.SourceFile), $item.SourceHive, (ConvertTo-MarkdownCell $item.Target), (ConvertTo-MarkdownCell $item.Verb), $item.LiveLocation))
        }
    }

    $markdown.Add('')
    $markdown.Add('## Live roots without a repository `.reg` owner')
    $markdown.Add('')
    if ($unexpectedLiveDefinitions.Count -eq 0) {
        $markdown.Add('None.')
    }
    else {
        $markdown.Add('| Hive | Target | Verb | Label |')
        $markdown.Add('|---|---|---|---|')
        foreach ($item in $unexpectedLiveDefinitions) {
            $markdown.Add(('| {0} | `{1}` | `{2}` | {3} |' -f $item.Hive, (ConvertTo-MarkdownCell $item.Target), (ConvertTo-MarkdownCell $item.Verb), (ConvertTo-MarkdownCell $item.Label)))
        }
    }

    $markdown.Add('')
    $markdown.Add('## Duplicate repository owners')
    $markdown.Add('')
    if ($duplicateSourceRoots.Count -eq 0) {
        $markdown.Add('None.')
    }
    else {
        $markdown.Add('| Logical root | Definitions | Source files |')
        $markdown.Add('|---|---:|---|')
        foreach ($item in $duplicateSourceRoots) {
            $files = ($item.SourceFiles | ForEach-Object { '`{0}`' -f $_ }) -join '<br>'
            $markdown.Add(('| `{0}` | {1} | {2} |' -f (ConvertTo-MarkdownCell $item.RelativeRoot), $item.DefinitionCount, $files))
        }
    }

    $markdown.Add('')
    $markdown.Add('## Broken referenced targets')
    $markdown.Add('')
    if ($brokenSourceDefinitions.Count -eq 0 -and $brokenLiveDefinitions.Count -eq 0) {
        $markdown.Add('None detected.')
    }
    else {
        foreach ($item in $brokenSourceDefinitions) {
            $markdown.Add(('- Source `{0}` / `{1}`: {2}' -f (ConvertTo-MarkdownCell $item.SourceFile), (ConvertTo-MarkdownCell $item.RelativeRoot), ($item.MissingReferencedPaths -join ', ')))
        }
        foreach ($item in $brokenLiveDefinitions) {
            $markdown.Add(('- Live {0} / `{1}`: {2}' -f $item.Hive, (ConvertTo-MarkdownCell $item.RelativeRoot), ($item.MissingReferencedPaths -join ', ')))
        }
    }

    $markdown.Add('')
    $markdown.Add('## Exact tree/value mismatches')
    $markdown.Add('')
    if ($treeMismatchDefinitions.Count -eq 0) {
        $markdown.Add('None detected for the selected live hive of each source definition.')
    }
    else {
        foreach ($item in $treeMismatchDefinitions) {
            $markdown.Add(('- `{0}` / `{1}`: missing keys {2}; extra keys {3}; value mismatches {4}; extra values {5}' -f (ConvertTo-MarkdownCell $item.SourceFile), (ConvertTo-MarkdownCell $item.RelativeRoot), $item.MissingSections.Count, $item.ExtraSections.Count, $item.ValueMismatches.Count, $item.ExtraValues.Count))
        }
    }
    $markdown.Add('')
    $markdown.Add('## Interpretation boundary')
    $markdown.Add('')
    $markdown.Add('- Registry readback proves key/value presence, not visible Explorer rendering.')
    $markdown.Add('- A later canonical manifest must classify each definition as production, preview, test, legacy, or deprecated before installation/removal is automated.')
    $markdown.Add('- The complete machine-readable evidence is in `Context-Menu-Inventory.json`.')
    [System.IO.File]::WriteAllLines($markdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))
}

[pscustomobject]$summary | Format-List

$issueCount = $missingSourceDefinitions.Count + $unexpectedLiveDefinitions.Count + $ambiguousSourceDefinitions.Count + $duplicateSourceRoots.Count + $brokenSourceDefinitions.Count + $brokenLiveDefinitions.Count + $treeMismatchDefinitions.Count + $uncatalogedRegFiles.Count + $catalogEntriesMissingFiles.Count + $catalogDefinitionCountMismatches.Count + $catalogHivePolicyMismatches.Count + $duplicateCatalogSourceFiles.Count
if ($Strict -and $issueCount -gt 0) {
    exit 2
}
