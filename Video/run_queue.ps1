param([string]$CurrentFolder)

# ===============================
# CONFIG
# ===============================
$queueDir = "D:\Users\joty79\scripts\encode\Video\queue"
$queueFile = Join-Path $queueDir "queue.txt"
# 🔸 NEW: Error Log
$errorLog = Join-Path $queueDir "add_errors.log"
$encoder = "D:\Users\joty79\scripts\encode\Video\video_encode.ps1"
$settings = Join-Path $queueDir "batch_settings.json"

# ===============================
# DETECT CURRENT FOLDER
# ===============================
if (-not $CurrentFolder) {
    # Fallback to current working directory
    $CurrentFolder = (Get-Location).Path
}

# Ensure full path
if (-not [System.IO.Path]::IsPathRooted($CurrentFolder)) {
    $CurrentFolder = Join-Path (Get-Location) $CurrentFolder
}

# Normalize path (resolve to full path)
# 🔸 FIX: LiteralPath
if (Test-Path -LiteralPath $CurrentFolder) {
    $CurrentFolder = (Resolve-Path -LiteralPath $CurrentFolder).Path
}

# ===============================
# PRECHECKS
# ===============================
# 🔸 FIX: LiteralPath
if (-not (Test-Path -LiteralPath $encoder)) {
    Write-Host "Encoder script not found:" -ForegroundColor Red
    Write-Host $encoder
    Read-Host "Press ENTER to exit"
    exit 1
}

# ===============================
# MENU LOOP
# ===============================
while ($true) {
    # Load queue
    $items = @()
    # 🔸 FIX: LiteralPath
    if (Test-Path -LiteralPath $queueFile) {
        $items = @(Get-Content -LiteralPath $queueFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" })
    }
    
    # Check if current folder is in queue
    $inQueue = $items -contains $CurrentFolder
    
    # 🔸 NEW: Check for Errors
    $hasErrors = Test-Path -LiteralPath $errorLog

    # Validate paths
    $validItems = @()
    foreach ($p in $items) {
        # 🔸 FIX: LiteralPath
        if (Test-Path -LiteralPath $p) {
            $validItems += $p
        }
    }
    
    # Display
    Clear-Host
    Write-Host ""
    Write-Host "=== Encode Queue Manager ===" -ForegroundColor Cyan
    
    # 🔸 NEW: Warning Banner
    if ($hasErrors) {
        Write-Host ""
        Write-Host " ⚠️  WARNING: Errors detected during silent add! Press 'L' to view.  " -BackgroundColor Red -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host ""
    }
    
    if ($validItems.Count -eq 0) {
        Write-Host "Queue is empty (0 items)" -ForegroundColor Gray
    }
    else {
        Write-Host "Queue contents:" -ForegroundColor DarkGray -NoNewline
        Write-Host " Total items: $($validItems.Count)" -ForegroundColor Gray
        Write-Host ""
        
        $i = 1
        foreach ($p in $validItems) {
            $basename = Split-Path $p -Leaf
            $parent = Split-Path $p -Parent
            
            Write-Host ("{0}) " -f $i) -ForegroundColor Gray -NoNewline
            Write-Host $basename -ForegroundColor Cyan -NoNewline
            Write-Host "  [$parent]" -ForegroundColor DarkGray
            $i++
        }
    }
    
    Write-Host ""
    Write-Host "Current folder: " -ForegroundColor DarkGray -NoNewline
    Write-Host (Split-Path $CurrentFolder -Leaf) -ForegroundColor Cyan -NoNewline
    if ($inQueue) {
        Write-Host " (IN QUEUE)" -ForegroundColor Green
    }
    else {
        Write-Host " (not in queue)" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    
    # Options
    if ($validItems.Count -gt 0) {
        Write-Host "Press ENTER to start batch encoding" -ForegroundColor Gray
        Write-Host "Press E to EDIT queue (remove items)" -ForegroundColor Magenta
    }
    
    if (-not $inQueue) {
        Write-Host "Press NUMPAD [+] to ADD current folder" -ForegroundColor Yellow
    }
    else {
        Write-Host "Press NUMPAD [-] to REMOVE current folder" -ForegroundColor Yellow
    }
    
    Write-Host "Press R to REFRESH queue" -ForegroundColor Cyan
    Write-Host "Press C to CLEAR queue" -ForegroundColor Red
    
    # 🔸 NEW: Log Option
    if ($hasErrors) {
        Write-Host "Press L to VIEW/CLEAR Errors" -ForegroundColor Red
    }

    Write-Host "Press ESC to EXIT without clearing" -ForegroundColor DarkGray
    
    # Get key
    $key = [Console]::ReadKey($true)
    
    # Handle input
    if ($key.Key -eq [ConsoleKey]::Enter -and $validItems.Count -gt 0) {
        # Start encoding
        break
    }
    elseif ($key.Key -eq [ConsoleKey]::Add -and -not $inQueue) {
        # Add current folder
        if (-not (Test-Path -LiteralPath $queueDir)) {
            New-Item -ItemType Directory -Path $queueDir | Out-Null
        }
        Add-Content -LiteralPath $queueFile -Value $CurrentFolder -Encoding UTF8
        # Loop continues
    }
    elseif ($key.Key -eq [ConsoleKey]::Subtract -and $inQueue) {
        # Remove current folder
        $items = $items | Where-Object { $_ -ne $CurrentFolder }
        if ($items.Count -eq 0) {
            if (Test-Path -LiteralPath $queueFile) {
                Remove-Item -LiteralPath $queueFile -Force
            }
        }
        else {
            $items | Set-Content -LiteralPath $queueFile -Encoding UTF8
        }
        # Loop continues
    }
    elseif ($key.Key -eq [ConsoleKey]::Escape) {
        # Exit without clearing
        exit
    }
    elseif ($key.KeyChar -in 'c', 'C') {
        # Clear queue (but stay in menu)
        if (Test-Path -LiteralPath $queueFile) { Remove-Item -LiteralPath $queueFile -Force }
        if (Test-Path -LiteralPath $settings) { Remove-Item -LiteralPath $settings -Force }
        if (Test-Path -LiteralPath $errorLog) { Remove-Item -LiteralPath $errorLog -Force }
        # Loop continues - menu refreshes with empty queue
    }
    # 🔸 NEW: Log Viewer Logic
    elseif ($key.KeyChar -in 'l', 'L' -and $hasErrors) {
        Clear-Host
        Write-Host ""
        Write-Host "=== ERROR LOG ===" -ForegroundColor Red
        Write-Host ""
        Get-Content -LiteralPath $errorLog | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
        Write-Host ""
        Write-Host "Press C to CLEAR logs and go back." -ForegroundColor Cyan
        Write-Host "Press any other key to go back (keep logs)." -ForegroundColor Gray
        
        $k2 = [Console]::ReadKey($true)
        if ($k2.KeyChar -in 'c', 'C') {
            Remove-Item -LiteralPath $errorLog -Force
        }
    }
    elseif ($key.KeyChar -in 'e', 'E' -and $validItems.Count -gt 0) {
        # Edit Mode - Remove items by number
        while ($true) {
            # Reload items
            if (Test-Path -LiteralPath $queueFile) {
                $items = @(Get-Content -LiteralPath $queueFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" })
            }
            else {
                break  # No items left, exit edit mode
            }
            
            if ($items.Count -eq 0) {
                break
            }
            
            # Display
            Clear-Host
            Write-Host ""
            Write-Host "=== EDIT QUEUE ===" -ForegroundColor Magenta
            Write-Host ""
            Write-Host "Queue contents:" -ForegroundColor DarkGray -NoNewline
            Write-Host " Total items: $($items.Count)" -ForegroundColor Gray
            Write-Host ""
            
            for ($i = 0; $i -lt $items.Count; $i++) {
                $p = $items[$i]
                $basename = Split-Path $p -Leaf
                $parent = Split-Path $p -Parent
                
                Write-Host ("{0}) " -f ($i + 1)) -ForegroundColor Gray -NoNewline
                Write-Host $basename -ForegroundColor Cyan -NoNewline
                Write-Host "  [$parent]" -ForegroundColor DarkGray
            }
            
            Write-Host ""
            Write-Host "Type " -ForegroundColor DarkGray -NoNewline
            Write-Host "NUMBER" -ForegroundColor Yellow -NoNewline
            Write-Host " and press " -ForegroundColor DarkGray -NoNewline
            Write-Host "ENTER" -ForegroundColor Green -NoNewline
            Write-Host " to remove. Press " -ForegroundColor DarkGray -NoNewline
            Write-Host "ESC" -ForegroundColor Red -NoNewline
            Write-Host " to go back." -ForegroundColor DarkGray
            Write-Host ""
            Write-Host "> " -ForegroundColor Yellow -NoNewline
            
            # Multi-digit input with ENTER confirmation
            $inputBuffer = ""
            $shouldExitEditMode = $false
            while ($true) {
                $editKey = [Console]::ReadKey($true)
                
                if ($editKey.Key -eq [ConsoleKey]::Escape) {
                    Write-Host ""
                    $shouldExitEditMode = $true
                    break  # Exit input loop
                }
                
                if ($editKey.Key -eq [ConsoleKey]::Enter) {
                    Write-Host ""
                    if ($inputBuffer -match '^\d+$') {
                        $num = [int]$inputBuffer
                        if ($num -ge 1 -and $num -le $items.Count) {
                            # Remove item
                            $removedItem = $items[$num - 1]
                            $items = $items | Where-Object { $_ -ne $removedItem }
                            
                            if ($items.Count -eq 0) {
                                Remove-Item -LiteralPath $queueFile -Force
                                Write-Host ""
                                Write-Host "Queue is now empty." -ForegroundColor Green
                                Start-Sleep -Milliseconds 800
                                $shouldExitEditMode = $true
                                break
                            }
                            else {
                                $items | Set-Content -LiteralPath $queueFile -Encoding UTF8
                            }
                            
                            # Show confirmation
                            Write-Host "Removed: " -ForegroundColor Yellow -NoNewline
                            Write-Host (Split-Path $removedItem -Leaf) -ForegroundColor Red
                            Start-Sleep -Milliseconds 700
                            break  # Refresh display
                        }
                        else {
                            Write-Host "Invalid number (1-$($items.Count))" -ForegroundColor Red
                            Start-Sleep -Milliseconds 800
                            break  # Refresh display
                        }
                    }
                    else {
                        # Empty or invalid - just refresh
                        break
                    }
                }
                
                if ($editKey.Key -eq [ConsoleKey]::Backspace) {
                    if ($inputBuffer.Length -gt 0) {
                        $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1)
                        Write-Host "`b `b" -NoNewline
                    }
                    continue
                }
                
                # Accept digits only
                if ($editKey.KeyChar -ge '0' -and $editKey.KeyChar -le '9') {
                    $inputBuffer += $editKey.KeyChar
                    Write-Host $editKey.KeyChar -NoNewline -ForegroundColor Yellow
                }
            }
            
            # Check if we should exit edit mode
            if ($shouldExitEditMode) {
                break
            }
        }
        # Return to main menu (loop continues)
    }
    elseif ($key.KeyChar -in 'r', 'R') {
        # Manual refresh - just loop continue
        continue
    }
}

# ===============================
# NORMALIZE & VALIDATE PATHS
# ===============================
$validItems = @()
foreach ($p in $items) {
    # 🔸 FIX: LiteralPath
    if (Test-Path -LiteralPath $p) {
        $validItems += $p
    }
    else {
        Write-Host "Skipping missing path:" -ForegroundColor Yellow
        Write-Host $p
    }
}

if (-not $validItems) {
    Write-Host "No valid paths in queue. Aborting." -ForegroundColor Red
    Remove-Item -LiteralPath $queueFile -Force
    exit 1
}

# ===============================
# BATCH HEADER
# ===============================

Write-Host ""
Write-Host "=== Batch encoding started ===" -ForegroundColor Cyan
Start-Sleep -Milliseconds 1000

# ===============================
# STEP 1: SETTINGS SELECTION (UI ONCE)
# ===============================
$firstItem = $validItems[0]

Write-Host "Using first item to select settings:" -ForegroundColor Gray
Write-Host "  $firstItem" -ForegroundColor Green
Write-Host ""

# Delete old settings to avoid stale reuse
if (Test-Path -LiteralPath $settings) {
    Remove-Item -LiteralPath $settings -Force
}

# Run encoder WITH UI (no -Batch)
$env:RUN_FROM_QUEUE = "1"
# 🔸 FIX: Quotes around paths in execution call usually handled by pwsh parsing, 
# but LiteralPath logic is inside the called script.
& pwsh -NoProfile -ExecutionPolicy Bypass -File $encoder $firstItem

# Verify settings were created
if (-not (Test-Path -LiteralPath $settings)) {
    Write-Host ""
    Write-Host "Batch settings were not saved. Aborting queue." -ForegroundColor Red
    exit 1
}

# ===============================
# STEP 2: ENCODING QUEUE
# ===============================
Write-Host ""
Write-Host "=== Encoding queue ===" -ForegroundColor Cyan

for ($i = 1; $i -lt $validItems.Count; $i++) {
    $path = $validItems[$i]

    Write-Host ""
    Write-Host "[$($i + 1) / $($validItems.Count)] $path" -ForegroundColor Green
    Write-Host "Encoding..." -ForegroundColor Gray

    if ($i -eq 0) {
        # First item already ran once for UI, run again in batch mode
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $encoder $path -Batch
    }
    else {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $encoder $path -Batch
    }

    Write-Host "Done." -ForegroundColor DarkGreen
}

# ===============================
# CLEANUP
# ===============================
if (Test-Path -LiteralPath $queueFile) { Remove-Item -LiteralPath $queueFile -Force }
if (Test-Path -LiteralPath $settings) { Remove-Item -LiteralPath $settings -Force }
if (Test-Path -LiteralPath $errorLog) { Remove-Item -LiteralPath $errorLog -Force }

Write-Host ""
Write-Host "=== All queue encodes completed ===" -ForegroundColor Green
Write-Host "Queue cleared." -ForegroundColor Gray
Read-Host "Press ENTER to close"