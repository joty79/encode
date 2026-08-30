param (
    [string]$ExeFile
)

# 🔸 TRAP: Keep window open ONLY if there is a crash
trap {
    Write-Host ""
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit 1
}

# ---------------------------------
# Validate input (.NET Safe)
# ---------------------------------
if ([string]::IsNullOrEmpty($ExeFile) -or -not [System.IO.File]::Exists($ExeFile)) {
    Write-Host ""
    Write-Host "Executable not found: $ExeFile" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit
}

# 🔸 Paths using .NET (Safe for special characters and brackets)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($ExeFile)
$baseDir  = [System.IO.Path]::GetDirectoryName($ExeFile)

$outFinalSameDir = [System.IO.Path]::Combine($baseDir, "$baseName.ico")
$desktopDir      = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$outFinalDesktop = [System.IO.Path]::Combine($desktopDir, "$baseName.ico")

# ---------------------------------
# IconsExtract path
# ---------------------------------
$iconsExtract = "D:\Programs\Windows\IconsExtract\iconsext.exe"

if (-not [System.IO.File]::Exists($iconsExtract)) {
    Write-Host ""
    Write-Host "IconsExtract not found at: $iconsExtract" -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit
}

# ---------------------------------
# Run IconsExtract (Safe Temp Folder in user AppData)
# ---------------------------------
$tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "_icon_tmp_" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
[System.IO.Directory]::CreateDirectory($tempDir) | Out-Null

try {
    # Extract to user's temp directory (always writable regardless of EXE directory permissions)
    & $iconsExtract /save "$ExeFile" "$tempDir" -icons | Out-Null

    # Find the extracted icons
    $icons = @([System.IO.Directory]::GetFiles($tempDir, "*.ico"))

    if ($icons.Count -gt 0) {
        # Take the best / primary icon
        $extractedIcon = $icons | Sort-Object | Select-Object -First 1

        # ---------------------------------
        # Try saving to same folder first
        # ---------------------------------
        $savedPath = $null
        try {
            if ([System.IO.File]::Exists($outFinalSameDir)) {
                Write-Host "Icon already exists: $outFinalSameDir" -ForegroundColor Yellow
                return
            }

            [System.IO.File]::Move($extractedIcon, $outFinalSameDir)
            $savedPath = $outFinalSameDir
        }
        catch {
            # ---------------------------------
            # Fallback to Desktop on Access Denied / Protected Folders
            # ---------------------------------
            if ([System.IO.File]::Exists($outFinalDesktop)) {
                try { Clear-Host } catch {}
                Write-Host ""
                Write-Host " ========================================================= " -ForegroundColor Yellow
                Write-Host "  ⚠️  NOTICE: Icon already exists on Desktop               " -ForegroundColor Yellow
                Write-Host " ========================================================= " -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Desktop Icon : " -NoNewline -ForegroundColor Gray
                Write-Host $outFinalDesktop -ForegroundColor Cyan
                Write-Host ""
                Read-Host " Press ENTER to close..."
                return
            }

            [System.IO.File]::Move($extractedIcon, $outFinalDesktop)
            $savedPath = $outFinalDesktop

            try { Clear-Host } catch {}
            Write-Host ""
            Write-Host " ========================================================= " -ForegroundColor Yellow
            Write-Host "  ⚠️  ACCESS DENIED IN FOLDER (Protected Directory)        " -ForegroundColor Yellow
            Write-Host " ========================================================= " -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Source EXE  : " -NoNewline -ForegroundColor Gray
            Write-Host $ExeFile -ForegroundColor White
            Write-Host "  Saved Icon  : " -NoNewline -ForegroundColor Gray
            Write-Host $outFinalDesktop -ForegroundColor Green
            Write-Host ""
            Write-Host " ========================================================= " -ForegroundColor Yellow
            Write-Host ""
            Read-Host " Press ENTER to close..."
        }
    } 
    else {
        # Fail case
        Write-Host ""
        Write-Host "No icon was extracted from '$ExeFile'." -ForegroundColor Red
        Write-Host "The executable may not contain any icon resources." -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "Press ENTER to exit..."
    }

} finally {
    # 🔸 CLEANUP: Delete temp folder safely
    if ([System.IO.Directory]::Exists($tempDir)) {
        try { [System.IO.Directory]::Delete($tempDir, $true) } catch {}
    }
}