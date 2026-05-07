param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile
)

# 🔸 TRAP: Κρατάει το παράθυρο ανοιχτό αν σκάσει κάτι
trap {
    Write-Host ""
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit 1
}

# Clean quotes just in case
$InputFile = $InputFile -replace '"', ''

Clear-Host
Write-Host "=== JOIN WMV (SMART MODE) ===" -ForegroundColor Cyan
Write-Host "Clicked file:"
# .NET Safe Filename extraction
Write-Host ([System.IO.Path]::GetFileName($InputFile))
Write-Host ""

# 🔸 FIX: .NET Check
if (-not [System.IO.File]::Exists($InputFile)) {
    Write-Host "ERROR: Input file not found" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit 1
}

# 🔸 FIX: .NET Paths
$folder = [System.IO.Path]::GetDirectoryName($InputFile)
$clickedBase = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)

# 🔸 FIX: LiteralPath is CRITICAL here for folders with []
$allFiles = Get-ChildItem -LiteralPath $folder -Filter *.wmv | Sort-Object Name
$related = $null

# Helper: exact lookup by BaseName (case-insensitive)
function Find-ByBaseName([string]$name) {
    return $allFiles | Where-Object { $_.BaseName -ieq $name } | Select-Object -First 1
}

# --------------------------------------------------
# AUTO MATCH MODE A: numeric sequence (1.wmv, 2.wmv)
# --------------------------------------------------
if ($clickedBase -match '^\d+$') {
    $numericFiles = $allFiles | Where-Object { $_.BaseName -match '^\d+$' } |
        Sort-Object { [int]$_.BaseName }

    if ($numericFiles.Count -ge 2) {
        $related = $numericFiles
        Write-Host "Auto-match: numeric sequence detected" -ForegroundColor Green
    }
}

# --------------------------------------------------
# AUTO MATCH MODE C: Part A/B
# --------------------------------------------------
if (-not $related) {

    $otherBase = $null

    # (PART A) -> (PART B)
    if ($clickedBase -match '\(PART\s+([AB])\)\s*$') {
        $letter = $Matches[1].ToUpper()
        $swap = if ($letter -eq 'A') { 'B' } else { 'A' }
        $otherBase = ($clickedBase -replace '\(PART\s+[AB]\)\s*$', "(PART $swap)")
    }
    # ends with " A" or " B"
    elseif ($clickedBase -match '\s([AB])\s*$') {
        $letter = $Matches[1].ToUpper()
        $swap = if ($letter -eq 'A') { 'B' } else { 'A' }
        $otherBase = ($clickedBase -replace '\s[AB]\s*$', " $swap")
    }

    if ($otherBase) {
        $other = Find-ByBaseName $otherBase
        if ($other) {
            $clicked = Find-ByBaseName $clickedBase
            if ($clicked) {
                $related = @($clicked, $other)
                Write-Host "Auto-match: A/B pair detected" -ForegroundColor Green
            }
        }
    }
}

# --------------------------------------------------
# AUTO MATCH MODE B: first-token ID
# --------------------------------------------------
if (-not $related) {

    $clickedToken = ($clickedBase -split '\s+', 2)[0]

    if ($clickedToken -match '^(?<id>.*?\d+)(?<suffix>[A-Za-z])?$') {
        $id = $Matches['id']

        if ($id -and $id.Length -gt 0) {
            $candidates = $allFiles | Where-Object {
                $t = ($_.BaseName -split '\s+', 2)[0]
                $t.StartsWith($id)
            }

            if ($candidates.Count -ge 2) {
                $related = $candidates
                Write-Host "Auto-match: token ID detected ($id*)" -ForegroundColor Green
            }
        }
    }
}

# --------------------------------------------------
# INTERACTIVE CONFIRMATION
# --------------------------------------------------
if ($related) {
    Write-Host ""
    Write-Host "Proposed files to join:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $related.Count; $i++) {
        Write-Host "[$i] $($related[$i].Name)"
    }

    Write-Host ""
    Write-Host "Press ENTER to continue"
    Write-Host "Type N and press ENTER for manual selection"

    $choice = Read-Host
    if ($choice -match '^[Nn]') {
        $related = $null
    }
}

# --------------------------------------------------
# MANUAL MODE
# --------------------------------------------------
if (-not $related) {
    Write-Host ""
    Write-Host "Manual selection:" -ForegroundColor Yellow

    for ($i = 0; $i -lt $allFiles.Count; $i++) {
        Write-Host "[$i] $($allFiles[$i].Name)"
    }

    Write-Host ""
    Write-Host "Enter numbers to join (comma separated, e.g. 0,1):"
    $input = Read-Host

    $indexes = $input -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+$' }

    $related = foreach ($idx in $indexes) {
        if ($idx -lt $allFiles.Count) { $allFiles[$idx] }
    }

    if ($related.Count -lt 2) {
        Write-Host "ERROR: Need at least two files" -ForegroundColor Red
        Read-Host "Press ENTER to exit"
        exit 2
    }
}

# --------------------------------------------------
# FINAL CONFIRM
# --------------------------------------------------
Write-Host ""
Write-Host "Final files to join:" -ForegroundColor Green
$related | ForEach-Object { Write-Host $_.Name }

# 🔸 FIX: .NET Path Combine
$outFile = [System.IO.Path]::Combine($folder, $clickedBase + "_joined.wmv")

Write-Host ""
Write-Host "Output file:"
Write-Host $outFile
Read-Host "Press ENTER to start join"

# --------------------------------------------------
# ASF BIN
# --------------------------------------------------
$asfbin = "C:\Program Files\CutAssist\asfbin\asfbin.exe"

$args = @()
foreach ($f in $related) {
    $args += "-i"
    $args += $f.FullName # FullName is safe, contains literal path
}

$args += "-o"
$args += $outFile
$args += "-cvb"
$args += "-istart"
$args += "-u"
$args += "-y"

# Execute safely
& $asfbin @args

Write-Host ""
Write-Host "DONE ✔"
Write-Host "Created: $([System.IO.Path]::GetFileName($outFile))"
Read-Host "Press ENTER to exit..."