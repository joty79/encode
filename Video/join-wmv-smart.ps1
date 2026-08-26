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

if ([System.IO.Path]::GetExtension($InputFile) -ine ".wmv") {
    Write-Host "ERROR: Input must be a .wmv file" -ForegroundColor Red
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
    $selectionText = Read-Host

    $indexes = $selectionText -split ',' |
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

if ([System.IO.File]::Exists($outFile)) {
    Write-Host "ERROR: Output already exists; refusing to overwrite it." -ForegroundColor Red
    Write-Host $outFile
    Read-Host "Press ENTER to exit"
    exit 3
}

Write-Host ""
Write-Host "Output file:"
Write-Host $outFile
Read-Host "Press ENTER to start join"

# --------------------------------------------------
# ASF BIN
# --------------------------------------------------
$asfbin = "C:\Program Files\CutAssist\asfbin\asfbin.exe"

if (-not [System.IO.File]::Exists($asfbin)) {
    Write-Host "ERROR: ASFBin was not found:" -ForegroundColor Red
    Write-Host $asfbin
    Read-Host "Press ENTER to exit"
    exit 4
}

$asfbinArgs = @()
foreach ($f in $related) {
    $asfbinArgs += "-i"
    $asfbinArgs += $f.FullName # FullName is safe, contains literal path
}

$asfbinArgs += "-o"
$asfbinArgs += $outFile
$asfbinArgs += "-cvb"
$asfbinArgs += "-istart"
$asfbinArgs += "-u"

# Execute safely
& $asfbin @asfbinArgs
$asfbinExitCode = $LASTEXITCODE

if ($asfbinExitCode -ne 0) {
    if ([System.IO.File]::Exists($outFile)) {
        Remove-Item -LiteralPath $outFile -Force
    }
    Write-Host "ERROR: ASFBin failed with exit code $asfbinExitCode" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit 5
}

if (-not [System.IO.File]::Exists($outFile) -or (Get-Item -LiteralPath $outFile).Length -le 0) {
    if ([System.IO.File]::Exists($outFile)) {
        Remove-Item -LiteralPath $outFile -Force
    }
    Write-Host "ERROR: ASFBin did not create a usable output file" -ForegroundColor Red
    Read-Host "Press ENTER to exit"
    exit 6
}

$probeOutput = & ffprobe.exe -v error -show_entries format=format_name,duration -of default=noprint_wrappers=1 $outFile 2>&1
$probeExitCode = $LASTEXITCODE
if ($probeExitCode -ne 0) {
    Remove-Item -LiteralPath $outFile -Force
    Write-Host "ERROR: ffprobe could not validate the joined WMV" -ForegroundColor Red
    $probeOutput | Write-Host
    Read-Host "Press ENTER to exit"
    exit 7
}

Write-Host ""
Write-Host "DONE ✔"
Write-Host "Created: $([System.IO.Path]::GetFileName($outFile))"
Read-Host "Press ENTER to exit..."
