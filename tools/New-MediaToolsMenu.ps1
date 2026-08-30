[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'config\MediaTools-Menu.json'),
    [string]$InventoryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\Context-Menu-Inventory.json'),
    [string]$OutputRegPath,
    [string]$RemovalRegPath,
    [string]$ReportPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\Media-Tools-Menu-Coverage.json'),
    [ValidateSet('All', 'HKLM', 'HKCU')]
    [string]$OutputHive = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-RegString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function ConvertTo-KeyToken {
    param([Parameter(Mandatory)][string]$Value)

    return ($Value -replace '[^A-Za-z0-9_]+', '_').Trim('_')
}

function Get-OptionalPropertyValue {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }
    return $property.Value
}

function Resolve-IconValue {
    param(
        [AllowNull()][AllowEmptyString()][string]$Reference,
        [Parameter(Mandatory)][hashtable]$IconTable
    )

    if ([string]::IsNullOrWhiteSpace($Reference)) {
        return $null
    }
    if ($IconTable.ContainsKey($Reference)) {
        return [string]$IconTable[$Reference]
    }
    return $Reference
}

function Get-TargetShellPath {
    param(
        [Parameter(Mandatory)][string]$Hive,
        [Parameter(Mandatory)][string]$TargetType,
        [Parameter(Mandatory)][string]$Target
    )

    $hivePath = switch ($Hive) {
        'HKLM' { 'HKEY_LOCAL_MACHINE\Software\Classes' }
        'HKCU' { 'HKEY_CURRENT_USER\Software\Classes' }
        default { throw "Unsupported hive '$Hive'." }
    }

    switch ($TargetType) {
        'Extension' { return "$hivePath\SystemFileAssociations\$Target\shell" }
        'Folder' { return "$hivePath\$Target\shell" }
        'FolderBackground' { return "$hivePath\$Target\shell" }
        'Class' { return "$hivePath\$Target\Shell" }
        default { throw "Unsupported target type '$TargetType'." }
    }
}

function Get-CoverageTarget {
    param(
        [Parameter(Mandatory)][string]$TargetType,
        [Parameter(Mandatory)][string]$Target
    )

    if ($TargetType -eq 'FolderBackground' -and $Target -eq 'Directory\Background') {
        return 'Directory background'
    }
    return $Target
}

function Get-CoverageKey {
    param(
        [Parameter(Mandatory)][string]$TargetType,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Verb
    )

    return ('{0}|{1}|{2}' -f $TargetType, $Target, $Verb).ToLowerInvariant()
}

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Menu manifest was not found: $resolvedManifestPath"
}

$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $null -eq $manifest.actions -or $null -eq $manifest.profiles -or $null -eq $manifest.bindings) {
    throw "Unsupported or invalid menu manifest: $resolvedManifestPath"
}

if ([string]::IsNullOrWhiteSpace($OutputRegPath)) {
    $OutputRegPath = Join-Path $resolvedRepoRoot ([string]$manifest.sourceRegFile)
}
if ([string]::IsNullOrWhiteSpace($RemovalRegPath)) {
    $RemovalRegPath = Join-Path $resolvedRepoRoot ([string]$manifest.removalRegFile)
}
$resolvedOutputRegPath = [System.IO.Path]::GetFullPath($OutputRegPath)
$resolvedRemovalRegPath = [System.IO.Path]::GetFullPath($RemovalRegPath)
$resolvedReportPath = [System.IO.Path]::GetFullPath($ReportPath)

$actionTable = @{}
foreach ($property in $manifest.actions.PSObject.Properties) {
    $actionTable[$property.Name] = $property.Value
}
$iconTable = @{}
$iconsNode = Get-OptionalPropertyValue -InputObject $manifest -Name 'icons'
if ($null -ne $iconsNode) {
    foreach ($property in $iconsNode.PSObject.Properties) {
        $iconTable[$property.Name] = [string]$property.Value
    }
}
$profileTable = @{}
foreach ($property in $manifest.profiles.PSObject.Properties) {
    $profileTable[$property.Name] = @($property.Value)
}

$errors = [System.Collections.Generic.List[string]]::new()
$targetRecords = [System.Collections.Generic.List[object]]::new()
$coverageKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$coverageCommands = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$ownedRoots = [System.Collections.Generic.List[string]]::new()
$seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$maxChildren = [int]$manifest.maxVisibleChildrenPerLevel
$maxObservedChildren = 0

foreach ($iconEntry in $iconTable.GetEnumerator()) {
    if ($iconEntry.Value -match '^(?<path>[A-Za-z]:\\[^,]+)') {
        if (-not (Test-Path -LiteralPath $Matches.path -PathType Leaf)) {
            $errors.Add("Icon '$($iconEntry.Key)' references missing path '$($Matches.path)'.")
        }
    }
}

foreach ($binding in $manifest.bindings) {
    if (-not $profileTable.ContainsKey([string]$binding.profile)) {
        $errors.Add("Binding references missing profile '$($binding.profile)'.")
        continue
    }

    $branches = @($profileTable[[string]$binding.profile])
    $maxObservedChildren = [Math]::Max($maxObservedChildren, $branches.Count)
    if ($branches.Count -gt $maxChildren) {
        $errors.Add("Profile '$($binding.profile)' has $($branches.Count) root children; limit is $maxChildren.")
    }
    $queueIndexes = @(
        for ($index = 0; $index -lt $branches.Count; $index++) {
            if ([string](Get-OptionalPropertyValue -InputObject $branches[$index] -Name 'label') -eq 'Queues') { $index }
        }
    )
    if ($queueIndexes.Count -gt 0 -and $queueIndexes[-1] -ne ($branches.Count - 1)) {
        $errors.Add("Profile '$($binding.profile)' does not place Queues last.")
    }

    foreach ($target in @($binding.targets)) {
        $targetIdentity = ('{0}|{1}' -f $binding.targetType, $target)
        if (-not $seenTargets.Add($targetIdentity)) {
            $errors.Add("Duplicate target binding: $targetIdentity")
            continue
        }

        $shellPath = Get-TargetShellPath -Hive $binding.hive -TargetType $binding.targetType -Target $target
        $rootPath = "$shellPath\$($manifest.rootVerb)"
        $ownedRoots.Add($rootPath)
        $targetActions = [System.Collections.Generic.List[string]]::new()

        foreach ($branch in $branches) {
            $branchActions = @($branch.actions)
            $maxObservedChildren = [Math]::Max($maxObservedChildren, $branchActions.Count)
            if ($branchActions.Count -gt $maxChildren) {
                $errors.Add("Profile '$($binding.profile)' branch '$($branch.id)' has $($branchActions.Count) actions; limit is $maxChildren.")
            }
            foreach ($actionId in $branchActions) {
                if (-not $actionTable.ContainsKey([string]$actionId)) {
                    $errors.Add("Profile '$($binding.profile)' references missing action '$actionId'.")
                    continue
                }
                $action = $actionTable[[string]$actionId]
                $targetActions.Add([string]$actionId)
                $coverageTarget = Get-CoverageTarget -TargetType $binding.targetType -Target $target
                $coverageKey = Get-CoverageKey -TargetType $binding.targetType -Target $coverageTarget -Verb $action.coversVerb
                [void]$coverageKeys.Add($coverageKey)
                if ($coverageCommands.ContainsKey($coverageKey) -and $coverageCommands[$coverageKey] -cne [string]$action.command) {
                    $errors.Add("Conflicting generated commands for coverage mapping '$coverageKey'.")
                }
                else {
                    $coverageCommands[$coverageKey] = [string]$action.command
                }

                $pathMatches = [regex]::Matches([string]$action.command, '(?i)[A-Z]:\\[^\"]+\.(?:ps1|vbs|ico)')
                foreach ($pathMatch in $pathMatches) {
                    if (-not (Test-Path -LiteralPath $pathMatch.Value -PathType Leaf)) {
                        $errors.Add("Action '$actionId' references missing path '$($pathMatch.Value)'.")
                    }
                }
            }
        }

        $targetRecords.Add([pscustomobject]@{
            Hive = [string]$binding.hive
            TargetType = [string]$binding.targetType
            Target = [string]$target
            Profile = [string]$binding.profile
            RootPath = $rootPath
            RootIcon = [string](Get-OptionalPropertyValue -InputObject $binding -Name 'rootIcon' -DefaultValue (Get-OptionalPropertyValue -InputObject $manifest -Name 'rootIcon'))
            RootChildren = $branches.Count
            ActionCount = $targetActions.Count
            Actions = @($targetActions)
        })
    }
}

$missingLegacyCoverage = [System.Collections.Generic.List[object]]::new()
$extraCoverage = [System.Collections.Generic.List[string]]::new()
$legacyCommandMismatches = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $InventoryPath -PathType Leaf) {
    $inventory = Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json
    $legacyKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($definition in @($inventory.SourceDefinitions | Where-Object Lifecycle -EQ 'current-direct')) {
        $key = Get-CoverageKey -TargetType $definition.TargetType -Target $definition.Target -Verb $definition.Verb
        [void]$legacyKeys.Add($key)
        if (-not $coverageKeys.Contains($key)) {
            $missingLegacyCoverage.Add([pscustomobject]@{
                SourceFile = $definition.SourceFile
                TargetType = $definition.TargetType
                Target = $definition.Target
                Verb = $definition.Verb
                Label = $definition.Label
            })
        }
        else {
            $legacyCommands = @($definition.Commands)
            if ($legacyCommands.Count -ne 1 -or $coverageCommands[$key] -cne [string]$legacyCommands[0]) {
                $legacyCommandMismatches.Add([pscustomobject]@{
                    SourceFile = $definition.SourceFile
                    TargetType = $definition.TargetType
                    Target = $definition.Target
                    Verb = $definition.Verb
                    LegacyCommands = $legacyCommands
                    GeneratedCommand = $coverageCommands[$key]
                })
            }
        }
    }
    foreach ($key in $coverageKeys) {
        if (-not $legacyKeys.Contains($key)) {
            $extraCoverage.Add($key)
        }
    }
}
else {
    $errors.Add("Inventory required for legacy coverage was not found: $InventoryPath")
}

if ($missingLegacyCoverage.Count -gt 0) {
    $errors.Add("The organized menu is missing $($missingLegacyCoverage.Count) legacy target/verb mappings.")
}
if ($legacyCommandMismatches.Count -gt 0) {
    $errors.Add("The organized menu has $($legacyCommandMismatches.Count) legacy command mismatches.")
}

if ($errors.Count -gt 0) {
    throw ($errors -join [Environment]::NewLine)
}

$outputTargetRecords = @(
    if ($OutputHive -eq 'All') {
        $targetRecords
    }
    else {
        $targetRecords | Where-Object Hive -EQ $OutputHive
    }
)
$outputOwnedRoots = @($outputTargetRecords | ForEach-Object RootPath)
$outputCleanupRoots = [System.Collections.Generic.List[string]]::new()
foreach ($rootPath in $outputOwnedRoots) {
    $outputCleanupRoots.Add($rootPath)
}
$cleanupRootVerbs = @(Get-OptionalPropertyValue -InputObject $manifest -Name 'cleanupRootVerbs' -DefaultValue @())
foreach ($targetRecord in $outputTargetRecords) {
    $rootParent = $targetRecord.RootPath.Substring(0, $targetRecord.RootPath.LastIndexOf('\') + 1)
    foreach ($cleanupRootVerb in $cleanupRootVerbs) {
        if (-not [string]::IsNullOrWhiteSpace([string]$cleanupRootVerb)) {
            $outputCleanupRoots.Add("$rootParent$cleanupRootVerb")
        }
    }
}

$regLines = [System.Collections.Generic.List[string]]::new()
$regLines.Add('Windows Registry Editor Version 5.00')
$regLines.Add('')
$regLines.Add('; Generated by tools\New-MediaToolsMenu.ps1 from config\MediaTools-Menu.json.')
$regLines.Add('; Re-import is idempotent: only manifest-owned Media Tools roots are replaced.')
$regLines.Add('; Current direct production verbs remain untouched during preview acceptance.')
$regLines.Add('')
foreach ($rootPath in $outputCleanupRoots) {
    $regLines.Add("[-$rootPath]")
}

foreach ($targetRecord in $outputTargetRecords) {
    $branches = @($profileTable[$targetRecord.Profile])
    $rootPath = $targetRecord.RootPath
    $regLines.Add('')
    $regLines.Add("[$rootPath]")
    $regLines.Add(('"MUIVerb"="{0}"' -f (ConvertTo-RegString $manifest.rootLabel)))
    $regLines.Add('"SubCommands"=""')
    $rootIcon = Resolve-IconValue -Reference $targetRecord.RootIcon -IconTable $iconTable
    if (-not [string]::IsNullOrWhiteSpace($rootIcon)) {
        $regLines.Add(('"Icon"="{0}"' -f (ConvertTo-RegString $rootIcon)))
    }
    if ($targetRecord.TargetType -eq 'Class' -and $targetRecord.Target -eq 'DesktopBackground') {
        $regLines.Add('"Position"="Bottom"')
    }

    foreach ($branch in $branches) {
        $branchPath = "$rootPath\shell\$($branch.id)"
        $branchActions = @($branch.actions)
        $branchLabel = [string](Get-OptionalPropertyValue -InputObject $branch -Name 'label')
        $separatorBefore = [bool](Get-OptionalPropertyValue -InputObject $branch -Name 'separatorBefore' -DefaultValue $false)
        if ([string]::IsNullOrWhiteSpace($branchLabel) -and $branchActions.Count -eq 1) {
            $action = $actionTable[[string]$branchActions[0]]
            $regLines.Add('')
            $regLines.Add("[$branchPath]")
            $regLines.Add(('"MUIVerb"="{0}"' -f (ConvertTo-RegString $action.label)))
            $actionIcon = Resolve-IconValue -Reference ([string](Get-OptionalPropertyValue -InputObject $action -Name 'icon')) -IconTable $iconTable
            if (-not [string]::IsNullOrWhiteSpace($actionIcon)) {
                $regLines.Add(('"Icon"="{0}"' -f (ConvertTo-RegString $actionIcon)))
            }
            if ($separatorBefore) {
                $regLines.Add('"CommandFlags"=dword:00000020')
            }
            $regLines.Add('')
            $regLines.Add("[$branchPath\command]")
            $regLines.Add(('@="{0}"' -f (ConvertTo-RegString $action.command)))
            continue
        }

        $regLines.Add('')
        $regLines.Add("[$branchPath]")
        $regLines.Add(('"MUIVerb"="{0}"' -f (ConvertTo-RegString $branchLabel)))
        $regLines.Add('"SubCommands"=""')
        $branchIcon = Resolve-IconValue -Reference ([string](Get-OptionalPropertyValue -InputObject $branch -Name 'icon')) -IconTable $iconTable
        if (-not [string]::IsNullOrWhiteSpace($branchIcon)) {
            $regLines.Add(('"Icon"="{0}"' -f (ConvertTo-RegString $branchIcon)))
        }
        if ($separatorBefore) {
            $regLines.Add('"CommandFlags"=dword:00000020')
        }
        for ($actionIndex = 0; $actionIndex -lt $branchActions.Count; $actionIndex++) {
            $actionId = [string]$branchActions[$actionIndex]
            $action = $actionTable[$actionId]
            $actionToken = ConvertTo-KeyToken $actionId
            $actionPath = ('{0}\shell\{1:D2}_{2}' -f $branchPath, ($actionIndex + 1), $actionToken)
            $regLines.Add('')
            $regLines.Add("[$actionPath]")
            $regLines.Add(('"MUIVerb"="{0}"' -f (ConvertTo-RegString $action.label)))
            $actionIcon = Resolve-IconValue -Reference ([string](Get-OptionalPropertyValue -InputObject $action -Name 'icon')) -IconTable $iconTable
            if (-not [string]::IsNullOrWhiteSpace($actionIcon)) {
                $regLines.Add(('"Icon"="{0}"' -f (ConvertTo-RegString $actionIcon)))
            }
            $regLines.Add('')
            $regLines.Add("[$actionPath\command]")
            $regLines.Add(('@="{0}"' -f (ConvertTo-RegString $action.command)))
        }
    }
}

$removeLines = [System.Collections.Generic.List[string]]::new()
$removeLines.Add('Windows Registry Editor Version 5.00')
$removeLines.Add('')
$removeLines.Add('; Generated cleanup. Removes only manifest-owned Media Tools roots.')
$removeLines.Add('')
foreach ($rootPath in $outputCleanupRoots) {
    $removeLines.Add("[-$rootPath]")
}

[System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedOutputRegPath)) | Out-Null
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedRemovalRegPath)) | Out-Null
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedReportPath)) | Out-Null
$regEncoding = [System.Text.UnicodeEncoding]::new($false, $true)
[System.IO.File]::WriteAllLines($resolvedOutputRegPath, $regLines, $regEncoding)
[System.IO.File]::WriteAllLines($resolvedRemovalRegPath, $removeLines, $regEncoding)

$report = [ordered]@{
    GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
    ManifestPath = $resolvedManifestPath
    OutputHive = $OutputHive
    OutputRegPath = $resolvedOutputRegPath
    RemovalRegPath = $resolvedRemovalRegPath
    TargetRoots = $targetRecords.Count
    GeneratedTargetRoots = $outputTargetRecords.Count
    CoverageMappings = $coverageKeys.Count
    MissingLegacyCoverage = @($missingLegacyCoverage)
    ExtraCoverage = @($extraCoverage)
    LegacyCommandMismatches = @($legacyCommandMismatches)
    MaxVisibleChildrenPerLevel = $maxChildren
    MaxObservedVisibleChildrenPerLevel = $maxObservedChildren
    Targets = @($targetRecords)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedReportPath -Encoding utf8BOM

[pscustomobject]@{
    TargetRoots = $targetRecords.Count
    GeneratedTargetRoots = $outputTargetRecords.Count
    OutputHive = $OutputHive
    CoverageMappings = $coverageKeys.Count
    MissingLegacyCoverage = $missingLegacyCoverage.Count
    ExtraCoverage = $extraCoverage.Count
    LegacyCommandMismatches = $legacyCommandMismatches.Count
    MaxObservedVisibleChildrenPerLevel = $maxObservedChildren
    OutputRegPath = $resolvedOutputRegPath
    RemovalRegPath = $resolvedRemovalRegPath
    ReportPath = $resolvedReportPath
} | Format-List
