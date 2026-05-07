param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

# ===============================
# CONFIG
# ===============================
$queueDir = "D:\Users\joty79\scripts\encode\audio\queue"
$queueFile = Join-Path $queueDir "queue.txt"
# 🔸 NEW: Error Log for silent failures
$errorLog = Join-Path $queueDir "add_errors.log"

# Supported formats
$videoExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.mpg', '.mpeg', 
    '.vob', '.webm', '.flv', '.m2ts', '.ts')
$audioExtensions = @('.aac', '.mp3', '.flac', '.wav', '.ogg', '.opus', 
    '.m4a', '.wma', '.ac3', '.dts')
$allExtensions = $videoExtensions + $audioExtensions

# Helper function to log silent errors
function Log-Error {
    param([string]$Msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Msg" | Add-Content -LiteralPath $errorLog -Encoding UTF8
}

# ===============================
# NORMALIZE PATH
# ===============================
try {
    # 🔸 FIX: Use -LiteralPath
    $fullPath = (Resolve-Path -LiteralPath $TargetPath -ErrorAction Stop).Path
}
catch {
    Log-Error "FAILED to read path (Wildcard/Permission error): $TargetPath"
    exit 1
}

# ===============================
# VALIDATE FILE TYPE (for single files)
# ===============================
# 🔸 FIX: Use -LiteralPath
$isFile = Test-Path -LiteralPath $fullPath -PathType Leaf

if ($isFile) {
    $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
    if ($ext -notin $allExtensions) {
        Log-Error "Unsupported format: $ext ($fullPath)"
        exit 1
    }
}

# ===============================
# ENSURE QUEUE DIR EXISTS
# ===============================
# 🔸 FIX: Use -LiteralPath
if (-not (Test-Path -LiteralPath $queueDir)) {
    New-Item -ItemType Directory -Path $queueDir | Out-Null
}

# ===============================
# SMART DUPLICATE DETECTION
# ===============================
$existingItems = @()
if (Test-Path -LiteralPath $queueFile) {
    $existingItems = Get-Content -LiteralPath $queueFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" }
}

# Check if exact path already exists
if ($existingItems -contains $fullPath) {
    # Already exists - silent exit (success)
    exit 0
}

if ($isFile) {
    # Adding a FILE - check if parent folder is already in queue
    $parentFolder = Split-Path $fullPath -Parent
    
    foreach ($item in $existingItems) {
        # 🔸 FIX: Use -LiteralPath
        if (Test-Path -LiteralPath $item -PathType Container) {
            # Item is a folder - check if our file is inside it
            if ($fullPath.StartsWith($item + "\")) {
                exit 0
            }
        }
    }
}
else {
    # Adding a FOLDER - remove any individual files that are children
    $childFilesRemoved = @()
    $cleanedItems = @()
    
    foreach ($item in $existingItems) {
        # 🔸 FIX: Use -LiteralPath
        if (Test-Path -LiteralPath $item -PathType Leaf) {
            # Item is a file - check if it's inside our folder
            if ($item.StartsWith($fullPath + "\")) {
                $childFilesRemoved += $item
                # Skip this item (don't add to cleaned list)
            }
            else {
                $cleanedItems += $item
            }
        }
        else {
            $cleanedItems += $item
        }
    }
    
    # If we removed any child files, update the queue
    if ($childFilesRemoved.Count -gt 0) {
        if ($cleanedItems.Count -eq 0) {
            # Queue will only have the folder
            Remove-Item -LiteralPath $queueFile -Force -ErrorAction SilentlyContinue
        }
        else {
            # Write cleaned items back
            $cleanedItems | Set-Content -LiteralPath $queueFile -Encoding UTF8
        }
    }
}

# ===============================
# APPEND TO QUEUE
# ===============================
try {
    Add-Content -LiteralPath $queueFile -Value $fullPath -Encoding UTF8 -ErrorAction Stop
}
catch {
    Log-Error "Critical: Could not write to queue file. Locked?"
}

# ===============================
# FEEDBACK (Visual only if not silent)
# ===============================
Write-Host "Added to audio queue:" -ForegroundColor Green
Write-Host $fullPath -ForegroundColor Cyan