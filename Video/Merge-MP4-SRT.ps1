param (
    [string]$VideoFile
)

# 🔸 TRAP: Κρατάει το παράθυρο ανοιχτό αν σκάσει κάτι
trap {
    Write-Host ""
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit 1
}

# Καθαρισμός quotes
$VideoFile = $VideoFile -replace '"', ''

# Basic validation (.NET Safe)
if (-not [System.IO.File]::Exists($VideoFile)) {
    Write-Host "Video file not found." -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit 1
}

# Paths (.NET Safe)
$dir  = [System.IO.Path]::GetDirectoryName($VideoFile)
$base = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)
$fileName = [System.IO.Path]::GetFileName($VideoFile)

$srt = [System.IO.Path]::Combine($dir, $base + '.srt')
$out = [System.IO.Path]::Combine($dir, $base + '.mkv')

if (-not [System.IO.File]::Exists($srt)) {
    Write-Host "No matching subtitle found." -ForegroundColor Red
    Write-Host "Expected exactly:" -ForegroundColor Yellow
    Write-Host "  $($base).srt" -ForegroundColor Yellow
    Read-Host "Press ENTER to exit..."
    exit
}

# 🔒 OVERWRITE PROTECTION
if ([System.IO.File]::Exists($out)) {
    Write-Host ""
    Write-Host "Output file already exists. Aborting." -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Existing MKV : " -NoNewline
    Write-Host ([System.IO.Path]::GetFileName($out)) -ForegroundColor Blue

    Write-Host ""
    Write-Host "Nothing was overwritten." -ForegroundColor DarkGray
    Read-Host "Press ENTER to close..."
    exit
}

$mkvmerge = "C:\Program Files\MKVToolNix\mkvmerge.exe"

if (-not [System.IO.File]::Exists($mkvmerge)) {
    Write-Host "mkvmerge.exe not found." -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

# Run merge (Arguments array helps avoid quoting issues)
$mergeArgs = @("-o", $out, $VideoFile, $srt)
& $mkvmerge $mergeArgs | Out-Null

# ---- CLEAN SUCCESS OUTPUT ----
Write-Host ""
Write-Host "MKVToolNix merge completed successfully" -ForegroundColor Cyan
Write-Host ""

Write-Host "Input video : " -NoNewline
Write-Host $fileName -ForegroundColor Green

Write-Host "Subtitle    : " -NoNewline
Write-Host ([System.IO.Path]::GetFileName($srt)) -ForegroundColor Red

Write-Host "Output MKV  : " -NoNewline
Write-Host ([System.IO.Path]::GetFileName($out)) -ForegroundColor Blue

Write-Host ""
Read-Host "Press ENTER to close..."