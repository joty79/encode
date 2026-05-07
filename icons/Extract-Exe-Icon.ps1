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
    Write-Host "Executable not found." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit
}

# 🔸 FIX: Paths using .NET (Safe for [])
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($ExeFile)
$baseDir  = [System.IO.Path]::GetDirectoryName($ExeFile)
# Target is now the SAME folder as the EXE
$outFinal = [System.IO.Path]::Combine($baseDir, "$baseName.ico")

# ---------------------------------
# Overwrite protection
# ---------------------------------
if ([System.IO.File]::Exists($outFinal)) {
    # Seamless exit (Silent or minimal log)
    # User requested seamless, so we just exit without pausing.
    Write-Host "Icon already exists." -ForegroundColor Yellow
    exit
}

# ---------------------------------
# IconsExtract path
# ---------------------------------
$iconsExtract = "D:\Programs\Windows\IconsExtract\iconsext.exe"

if (-not [System.IO.File]::Exists($iconsExtract)) {
    Write-Host ""
    Write-Host "IconsExtract not found." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press ENTER to exit..."
    exit
}

# ---------------------------------
# Run IconsExtract (Safe Mode)
# ---------------------------------
# We use a TEMP folder inside the current dir to extract safely.
# This prevents accidentally deleting other icons in the main folder.
$tempDir = [System.IO.Path]::Combine($baseDir, "_icon_tmp_" + [Guid]::NewGuid().ToString().Substring(0,8))
[System.IO.Directory]::CreateDirectory($tempDir) | Out-Null

try {
    # Extract to temp
    & $iconsExtract /save "$ExeFile" "$tempDir" -icons | Out-Null

    # Find the extracted icon
    $icons = @([System.IO.Directory]::GetFiles($tempDir, "*.ico"))

    if ($icons.Count -gt 0) {
        # Take the first one (usually named after the exe)
        $extractedIcon = $icons | Sort-Object | Select-Object -First 1
        
        # Move to final destination (Same folder as EXE)
        [System.IO.File]::Move($extractedIcon, $outFinal)
        
        # SUCCESS: Script ends here cleanly (Seamless)
    } 
    else {
        # Fail case
        Write-Host ""
        Write-Host "No icon was extracted." -ForegroundColor Red
        Write-Host "The executable may not contain icons." -ForegroundColor DarkGray
        Write-Host ""
        Read-Host "Press ENTER..."
    }

} finally {
    # 🔸 CLEANUP: Delete temp folder safely
    if ([System.IO.Directory]::Exists($tempDir)) {
        try { [System.IO.Directory]::Delete($tempDir, $true) } catch {}
    }
}