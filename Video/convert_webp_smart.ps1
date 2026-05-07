param (
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# 🔸 TRAP: Κρατάει το παράθυρο ανοιχτό ΜΟΝΟ αν γίνει κρίσιμο λάθος
trap {
    Write-Host ""
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit 1
}

# ---------------------------------
# 1. Resolve Input (File or Folder) - .NET SAFE
# ---------------------------------
# Καθαρίζουμε τυχόν quotes
$Path = $Path -replace '"', ''

$files = @()

# Χρησιμοποιούμε System.IO που αγνοεί τις αγκύλες []
if ([System.IO.Directory]::Exists($Path)) {
    # Είναι φάκελος
    $files += @([System.IO.Directory]::GetFiles($Path, "*.webp"))
    $files += @([System.IO.Directory]::GetFiles($Path, "*.avif"))
    $files += @([System.IO.Directory]::GetFiles($Path, "*.heic"))
    $files += @([System.IO.Directory]::GetFiles($Path, "*.heif"))
}
elseif ([System.IO.File]::Exists($Path)) {
    # Είναι αρχείο
    $files = @($Path)
}
else {
    Write-Host "Path not found: $Path" -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
    exit
}

if ($files.Count -eq 0) {
    Write-Host "No compatible files found." -ForegroundColor Yellow
    Read-Host "Press ENTER to exit..."
    exit
}

# ---------------------------------
# 2. Process Files
# ---------------------------------
foreach ($filePath in $files) {
    # Ασφαλή Paths με .NET
    $fileName = [System.IO.Path]::GetFileName($filePath)
    $baseDir = [System.IO.Path]::GetDirectoryName($filePath)
    $fileBaseName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    
    Write-Host "`nProcessing: $fileName" -ForegroundColor Cyan

    # Έλεγχος Animation
    $frameInfo = & magick identify "$filePath" 2>$null
    $frames = $frameInfo | Where-Object { $_ -match '\[' }
    $isAnimated = ($frames.Count -gt 1)

    # === ANIMATED (WebP -> MP4) ===
    if ($isAnimated) {
        $animationDir = [System.IO.Path]::Combine($baseDir, "animation")
        
        # Ασφαλής δημιουργία φακέλου
        if (-not [System.IO.Directory]::Exists($animationDir)) {
            [System.IO.Directory]::CreateDirectory($animationDir) | Out-Null
        }
        
        # Temp folder
        $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "webp_" + [guid]::NewGuid().ToString())
        [System.IO.Directory]::CreateDirectory($tempDir) | Out-Null

        try {
            $framePattern = [System.IO.Path]::Combine($tempDir, "frame_%04d.png")
            & magick convert "$filePath" -coalesce "$framePattern"
            
            $outName = "$fileBaseName.mp4"
            $outPath = [System.IO.Path]::Combine($animationDir, $outName)
            $ffmpegInput = [System.IO.Path]::Combine($tempDir, "frame_%04d.png")

            & ffmpeg -hide_banner -loglevel error -y -framerate 25 -i "$ffmpegInput" -c:v libx264 -pix_fmt yuv420p "$outPath"
            
            if ([System.IO.File]::Exists($outPath)) {
                Write-Host "MP4 created -> $outName" -ForegroundColor Green
            } else {
                Write-Host "Failed to create MP4." -ForegroundColor Red
            }
        }
        finally {
            # Καθαρισμός temp
            if ([System.IO.Directory]::Exists($tempDir)) {
                try { [System.IO.Directory]::Delete($tempDir, $true) } catch {}
            }
        }
        continue
    }

    # === STATIC (Image -> JPG) ===
    $convertedDir = [System.IO.Path]::Combine($baseDir, "converted")
    if (-not [System.IO.Directory]::Exists($convertedDir)) {
        [System.IO.Directory]::CreateDirectory($convertedDir) | Out-Null
    }
    
    $jpgOut = [System.IO.Path]::Combine($convertedDir, "$fileBaseName.jpg")
    & magick convert "$filePath" -quality 85 "$jpgOut"
    Write-Host "JPG created -> $fileBaseName.jpg" -ForegroundColor Gray
}

Write-Host "`nDone." -ForegroundColor Green
# Αν θέλεις να κλείνει μόνο του, σβήσε την παρακάτω γραμμή:
Read-Host "Press ENTER to close..."