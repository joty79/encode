param (
    [string]$ImagePath
)

# 🔸 ERROR TRAP: Keep window open on crash
trap {
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press ENTER to close..."
    exit 1
}

# 🔸 CHECK: ImageMagick
if (-not (Get-Command "magick" -ErrorAction SilentlyContinue)) {
    Write-Host "Error: 'magick' command not found. Install ImageMagick." -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

# 🔸 FIX: Use .NET for File Existence (100% Safe for [])
if (-not [System.IO.File]::Exists($ImagePath)) {
    Write-Host "Error: File not found: $ImagePath" -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

$ext = [System.IO.Path]::GetExtension($ImagePath).ToLower()
if ($ext -notin @(".png", ".jpg", ".jpeg", ".bmp", ".webp")) {
    Write-Host "Unsupported extension: $ext" -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

# Detect animated WebP (Original logic preserved)
try {
    $frameInfo = & magick identify "$ImagePath" 2>$null
    $frames = $frameInfo | Where-Object { $_ -match '\[' }
    if ($frames.Count -gt 1) {
        [System.Console]::Beep(800, 200)
        exit
    }
} catch {
    # Ignore check fail
}

# 🔸 FIX: Use .NET for Paths (No 'Split-Path' errors)
$baseDir  = [System.IO.Path]::GetDirectoryName($ImagePath)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
$tempDir  = [System.IO.Path]::Combine($baseDir, "_ico_tmp")

# 🔸 FIX: Use .NET for Directory Creation
if (-not [System.IO.Directory]::Exists($tempDir)) {
    [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$tempImages = @()

foreach ($size in $sizes) {
    $outPng = [System.IO.Path]::Combine($tempDir, "icon_$size.png")

    magick "$ImagePath" `
        -resize "${size}x${size}" `
        -background none `
        -gravity center `
        -extent "${size}x${size}" `
        PNG32:"$outPng"

    # 🔸 FIX: Use .NET check
    if ([System.IO.File]::Exists($outPng)) {
        $tempImages += $outPng
    }
}

if ($tempImages.Count -gt 0) {
    $outputIco = [System.IO.Path]::Combine($baseDir, "$baseName.ico")
    magick $tempImages "$outputIco"
    Write-Host "Created: $outputIco" -ForegroundColor Green
}

# 🔸 FIX: Use .NET Cleanup (Avoids Remove-Item parameter error)
if ([System.IO.Directory]::Exists($tempDir)) {
    try {
        [System.IO.Directory]::Delete($tempDir, $true)
    } catch {
        # Ignore cleanup errors if file locked
    }
}