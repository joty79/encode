param([string]$CurrentFolder)

# ===============================
# CONFIG
# ===============================
$queueDir = "D:\Users\joty79\scripts\encode\audio\queue"
$queueFile = Join-Path $queueDir "queue.txt"
$errorLog = Join-Path $queueDir "add_errors.log"
$encoder = "D:\Users\joty79\scripts\encode\audio\audio_encode.ps1"
$settingsFile = Join-Path $queueDir "batch_settings.json"

# Supported formats
$videoExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.mpg', '.mpeg', 
    '.vob', '.webm', '.flv', '.m2ts', '.ts')
$audioExtensions = @('.aac', '.mp3', '.flac', '.wav', '.ogg', '.opus', 
    '.m4a', '.wma', '.ac3', '.dts')
$allExtensions = $videoExtensions + $audioExtensions

# ===============================
# DETECT CURRENT FOLDER
# ===============================
if (-not $CurrentFolder) {
    $CurrentFolder = (Get-Location).Path
}
if (-not [System.IO.Path]::IsPathRooted($CurrentFolder)) {
    $CurrentFolder = Join-Path (Get-Location) $CurrentFolder
}
if (Test-Path -LiteralPath $CurrentFolder) {
    $CurrentFolder = (Resolve-Path -LiteralPath $CurrentFolder).Path
}

# ===============================
# PRECHECKS
# ===============================
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
    if (Test-Path -LiteralPath $queueFile) {
        $items = @(Get-Content -LiteralPath $queueFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" })
    }
    
    # Check if current folder is in queue
    $inQueue = $items -contains $CurrentFolder
    
    # Check for SILENT ERRORS
    $hasErrors = Test-Path -LiteralPath $errorLog
    
    # Validate paths
    $validItems = @()
    foreach ($p in $items) {
        if (Test-Path -LiteralPath $p) {
            $validItems += $p
        }
    }
    
    # Display
    Clear-Host
    Write-Host ""
    Write-Host "=== Audio Queue Manager ===" -ForegroundColor Cyan
    
    # 🔸 WARNING BANNER IF ERRORS EXIST
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
        Write-Host "Press ENTER to start batch processing" -ForegroundColor Gray
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
    
    if ($hasErrors) {
        Write-Host "Press L to VIEW/CLEAR Errors" -ForegroundColor Red
    }
    
    Write-Host "Press ESC to EXIT without clearing" -ForegroundColor DarkGray
    
    # Get key
    $key = [Console]::ReadKey($true)
    
    # Handle input
    if ($key.Key -eq [ConsoleKey]::Enter -and $validItems.Count -gt 0) {
        break
    }
    elseif ($key.Key -eq [ConsoleKey]::Add -and -not $inQueue) {
        if (-not (Test-Path -LiteralPath $queueDir)) {
            New-Item -ItemType Directory -Path $queueDir | Out-Null
        }
        Add-Content -LiteralPath $queueFile -Value $CurrentFolder -Encoding UTF8
    }
    elseif ($key.Key -eq [ConsoleKey]::Subtract -and $inQueue) {
        $items = $items | Where-Object { $_ -ne $CurrentFolder }
        if ($items.Count -eq 0) {
            if (Test-Path -LiteralPath $queueFile) { Remove-Item -LiteralPath $queueFile -Force }
        } else {
            $items | Set-Content -LiteralPath $queueFile -Encoding UTF8
        }
    }
    elseif ($key.Key -eq [ConsoleKey]::Escape) {
        exit
    }
    elseif ($key.KeyChar -in 'r', 'R') {
        continue
    }
    elseif ($key.KeyChar -in 'c', 'C') {
        if (Test-Path -LiteralPath $queueFile) { Remove-Item -LiteralPath $queueFile -Force }
        if (Test-Path -LiteralPath $settingsFile) { Remove-Item -LiteralPath $settingsFile -Force }
        if (Test-Path -LiteralPath $errorLog) { Remove-Item -LiteralPath $errorLog -Force } # Clear errors on clear queue
    }
    # 🔸 LOG VIEWER
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
    # 🔸 UPDATED PRETTY EDIT MODE
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
}

# ===============================
# BATCH PROCESSING
# ===============================
Clear-Host
Write-Host ""
Write-Host "=== Starting Batch Processing ===" -ForegroundColor Cyan
Write-Host ""

$totalSuccess = 0
$totalFail = 0
$itemIndex = 0

foreach ($item in $validItems) {
    $itemIndex++
    Write-Host ""
    Write-Host "[$itemIndex / $($validItems.Count)] $item" -ForegroundColor Cyan
    
    if ($itemIndex -eq 1) {
        & $encoder -InputFile $item -NoPause
    } else {
        & $encoder -InputFile $item -Batch -NoPause
    }
    
    if ($LASTEXITCODE -eq 0) { $totalSuccess++ } else { $totalFail++ }
}

if (Test-Path -LiteralPath $queueFile) { Remove-Item -LiteralPath $queueFile -Force }
if (Test-Path -LiteralPath $errorLog) { Remove-Item -LiteralPath $errorLog -Force }

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Press any key to exit..."
[Console]::ReadKey($true) | Out-Null