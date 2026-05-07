param (
    [string]$VideoFile
)

Write-Host "=====================================" -ForegroundColor DarkCyan
Write-Host " MP4 Replace Audio (AAC)" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor DarkCyan
Write-Host ""

# ----------------- Validation (ONE TIME) -----------------
if (-not $VideoFile) {
    Write-Host "[ERROR] No MP4 file received." -ForegroundColor Red
    exit 1
}

# 🔸 FIX: LiteralPath
if (-not (Test-Path -LiteralPath $VideoFile)) {
    Write-Host "[ERROR] File not found:" -ForegroundColor Red
    Write-Host " $VideoFile" -ForegroundColor Gray
    exit 1
}

if ([System.IO.Path]::GetExtension($VideoFile).ToLower() -ne ".mp4") {
    Write-Host "[ERROR] This tool works ONLY on MP4 files." -ForegroundColor Red
    exit 1
}

$dir = Split-Path $VideoFile
$base = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)

Write-Host "[INFO] Video:" -ForegroundColor Blue
Write-Host " $VideoFile" -ForegroundColor Gray
Write-Host ""

# ========================================
# MAIN LOOP (AAC selection + replacement)
# ========================================
while ($true) {

    # Reset audioFile for each iteration
    $audioFile = $null
    
    # ----------------- Scan AAC files -----------------
    Write-Host "[INFO] Scanning folder for AAC files..." -ForegroundColor Blue

    # 🔸 FIX: LiteralPath inside Get-ChildItem is CRITICAL for folders with []
    $aacCandidates = @(Get-ChildItem -LiteralPath $dir -Filter "*.aac" -File |
        Select-Object -ExpandProperty FullName)

    if ($aacCandidates.Count -eq 0) {
        Write-Host "[ERROR] No AAC file found in folder." -ForegroundColor Red
        exit 1
    }

    # ----------------- Choose AAC with Instant Selection -----------------
    # Check if exact match exists (same basename)
    $exactMatch = Join-Path $dir "$base.aac"
    # 🔸 FIX: LiteralPath
    $hasExactMatch = Test-Path -LiteralPath $exactMatch

    if ($aacCandidates.Count -eq 1 -and $hasExactMatch) {
        # Only one AAC and it matches - use it directly
        $audioFile = $exactMatch
    }
    elseif ($hasExactMatch) {
        # Exact match exists + other alternatives
        Write-Host "[INFO] Exact match found:" -ForegroundColor Green
        Write-Host " $base.aac" -ForegroundColor Cyan
        Write-Host ""
        
        # Show alternatives (excluding exact match)
        $alternatives = @($aacCandidates | Where-Object { $_ -ne $exactMatch })
        
        if ($alternatives.Count -gt 0) {
            Write-Host "Alternative AAC files:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $alternatives.Count; $i++) {
                Write-Host " [$($i+1)] $(Split-Path $alternatives[$i] -Leaf)" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        Write-Host "Press ENTER to use exact match" -ForegroundColor White
        if ($alternatives.Count -gt 0 -and $alternatives.Count -le 9) {
            Write-Host "Press number (1-$($alternatives.Count)) for alternative (instant)" -ForegroundColor White
        }
        elseif ($alternatives.Count -gt 9) {
            Write-Host "Type number (1-$($alternatives.Count)) + ENTER for alternative" -ForegroundColor White
        }
        Write-Host "Press ESC or Q to cancel" -ForegroundColor DarkGray
        Write-Host ""
        
        # Instant selection for <=9 alternatives
        if ($alternatives.Count -le 9 -and $alternatives.Count -gt 0) {
            while ($true) {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                
                # ESC key
                if ($key.VirtualKeyCode -eq 27) {
                    Write-Host "Cancelled." -ForegroundColor Yellow
                    exit 0
                }
                
                # Q/q key
                if ($key.Character -match '^[Qq]$') {
                    Write-Host "Cancelled." -ForegroundColor Yellow
                    exit 0
                }
                
                # ENTER key - use exact match
                if ($key.VirtualKeyCode -eq 13) {
                    $audioFile = $exactMatch
                    Write-Host "[OK] Using exact match" -ForegroundColor Green
                    break
                }
                
                # Number keys
                if ($key.Character -match '^\d$') {
                    $num = [int]::Parse($key.Character)
                    if ($num -ge 1 -and $num -le $alternatives.Count) {
                        $audioFile = $alternatives[$num - 1]
                        Write-Host "[$num] Selected" -ForegroundColor Green
                        break
                    }
                }
            }
        }
        else {
            # More than 9 alternatives - use custom input for multi-digit with ESC support
            $input = ""
            
            while ($true) {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                
                # ESC key - cancel
                if ($key.VirtualKeyCode -eq 27) {
                    Write-Host ""
                    Write-Host "Cancelled." -ForegroundColor Yellow
                    exit 0
                }
                
                # Q/q key - cancel
                if ($key.Character -match '^[Qq]$') {
                    Write-Host $key.Character
                    Write-Host "Cancelled." -ForegroundColor Yellow
                    exit 0
                }
                
                # ENTER key - submit
                if ($key.VirtualKeyCode -eq 13) {
                    Write-Host ""
                    if ([string]::IsNullOrWhiteSpace($input)) {
                        # Empty input = use exact match
                        $audioFile = $exactMatch
                        Write-Host "[OK] Using exact match" -ForegroundColor Green
                        break
                    }
                    else {
                        # Validate number
                        $num = $input -as [int]
                        if ($num -and $num -ge 1 -and $num -le $alternatives.Count) {
                            $audioFile = $alternatives[$num - 1]
                            Write-Host "[OK] Using alternative" -ForegroundColor Green
                            break
                        }
                        else {
                            Write-Host "[WARN] Invalid selection. Restarting..." -ForegroundColor Yellow
                            Write-Host ""
                            continue  # Restart main loop (outer)
                        }
                    }
                }
                
                # Backspace key - delete last digit
                if ($key.VirtualKeyCode -eq 8 -and $input.Length -gt 0) {
                    $input = $input.Substring(0, $input.Length - 1)
                    Write-Host "`b `b" -NoNewline  # Erase character from console
                }
                
                # Number key - add digit
                if ($key.Character -match '^\d$') {
                    $input += $key.Character
                    Write-Host $key.Character -NoNewline
                }
            }
        }
    }
    else {
        # NO exact match - show all AAC with numbers
        if ($aacCandidates.Count -eq 1) {
            $audioFile = $aacCandidates[0]
        }
        else {
            Write-Host "[INFO] Multiple AAC files found:" -ForegroundColor Yellow
            Write-Host ""
            
            for ($i = 0; $i -lt $aacCandidates.Count; $i++) {
                Write-Host " [$($i+1)] $(Split-Path $aacCandidates[$i] -Leaf)" -ForegroundColor Gray
            }
            Write-Host ""
            
            if ($aacCandidates.Count -le 9) {
                Write-Host "Press number (1-$($aacCandidates.Count)) for selection (instant)" -ForegroundColor White
                Write-Host "Press ESC or Q to cancel" -ForegroundColor DarkGray
                Write-Host ""
                
                while ($true) {
                    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    
                    # ESC key
                    if ($key.VirtualKeyCode -eq 27) {
                        Write-Host "Cancelled." -ForegroundColor Yellow
                        exit 0
                    }
                    
                    # Q/q key
                    if ($key.Character -match '^[Qq]$') {
                        Write-Host "Cancelled." -ForegroundColor Yellow
                        exit 0
                    }
                    
                    # Number keys
                    if ($key.Character -match '^\d$') {
                        $num = [int]::Parse($key.Character)
                        if ($num -ge 1 -and $num -le $aacCandidates.Count) {
                            $audioFile = $aacCandidates[$num - 1]
                            Write-Host "[$num] Selected" -ForegroundColor Green
                            break
                        }
                    }
                }
            }
            else {
                # More than 9 files - use custom input for multi-digit with ESC support
                $input = ""
                
                while ($true) {
                    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    
                    # ESC key - cancel
                    if ($key.VirtualKeyCode -eq 27) {
                        Write-Host ""
                        Write-Host "Cancelled." -ForegroundColor Yellow
                        exit 0
                    }
                    
                    # Q/q key - cancel
                    if ($key.Character -match '^[Qq]$') {
                        Write-Host $key.Character
                        Write-Host "Cancelled." -ForegroundColor Yellow
                        exit 0
                    }
                    
                    # ENTER key - submit (no exact match here - must enter number)
                    if ($key.VirtualKeyCode -eq 13) {
                        Write-Host ""
                        if ([string]::IsNullOrWhiteSpace($input)) {
                            Write-Host "[WARN] No selection made. Restarting..." -ForegroundColor Yellow
                            Write-Host ""
                            continue  # Restart main loop (outer)
                        }
                        
                        # Validate number
                        $num = $input -as [int]
                        if ($num -and $num -ge 1 -and $num -le $aacCandidates.Count) {
                            $audioFile = $aacCandidates[$num - 1]
                            break
                        }
                        else {
                            Write-Host "[WARN] Invalid selection. Restarting..." -ForegroundColor Yellow
                            Write-Host ""
                            continue  # Restart main loop (outer)
                        }
                    }
                    
                    # Backspace key - delete last digit
                    if ($key.VirtualKeyCode -eq 8 -and $input.Length -gt 0) {
                        $input = $input.Substring(0, $input.Length - 1)
                        Write-Host "`b `b" -NoNewline  # Erase character from console
                    }
                    
                    # Number key - add digit
                    if ($key.Character -match '^\d$') {
                        $input += $key.Character
                        Write-Host $key.Character -NoNewline
                    }
                }
            }
        }
    }

    Write-Host ""
    Write-Host "[OK] Using audio file:" -ForegroundColor Green
    Write-Host " $(Split-Path $audioFile -Leaf)" -ForegroundColor Cyan
    Write-Host ""

    # ----------------- Duration Check -----------------
    $useShortest = $false
    
    # Get durations using ffprobe
    $videoDuration = & ffprobe -v error -select_streams v:0 -show_entries format=duration -of csv=p=0 "$VideoFile" 2>$null
    $audioDuration = & ffprobe -v error -select_streams a:0 -show_entries format=duration -of csv=p=0 "$audioFile" 2>$null
    
    if ($videoDuration -and $audioDuration) {
        $videoDur = [math]::Round([double]$videoDuration, 1)
        $audioDur = [math]::Round([double]$audioDuration, 1)
        $difference = [math]::Abs($videoDur - $audioDur)
        
        if ($difference -gt 1.0) {
            # Significant mismatch (>1 second)
            Write-Host "⚠️  Duration mismatch detected:" -ForegroundColor Yellow
            Write-Host "   Video: $($videoDur)s | Audio: $($audioDur)s | Diff: $($difference)s" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Output will trim to video duration (audio may be cut)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Press ENTER to continue or ESC to select different audio" -ForegroundColor White
            Write-Host ""
            
            while ($true) {
                $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                
                if ($key.VirtualKeyCode -eq 27) {
                    # ESC - restart selection
                    Write-Host "Restarting selection..." -ForegroundColor Cyan
                    Write-Host ""
                    continue  # Restart main loop (outer)
                }
                
                if ($key.VirtualKeyCode -eq 13) {
                    # ENTER - continue with -shortest
                    $useShortest = $true
                    Write-Host "Continuing with trim..." -ForegroundColor Green
                    Write-Host ""
                    break
                }
            }
        }
    }

    # ----------------- Output naming -----------------
    # Create unique output name based on audio file
    $audioBaseName = [System.IO.Path]::GetFileNameWithoutExtension($audioFile)
    
    if ($audioBaseName -eq $base) {
        # Same name - simple suffix
        $output = Join-Path $dir "$base.audio-replaced.mp4"
    }
    else {
        # Different name - include audio basename
        $output = Join-Path $dir "$base-audio-$audioBaseName.mp4"
    }

    # ----------------- Replace audio -----------------
    Write-Host "[INFO] Replacing audio..." -ForegroundColor Blue

    if ($useShortest) {
        # Duration mismatch - use -shortest to trim to video duration
        ffmpeg -hide_banner -loglevel error -y `
            -i "$VideoFile" `
            -i "$audioFile" `
            -map 0:v:0 `
            -map 1:a:0 `
            -c:v copy `
            -c:a copy `
            -shortest `
            "$output"
    }
    else {
        # Normal operation
        ffmpeg -hide_banner -loglevel error -y `
            -i "$VideoFile" `
            -i "$audioFile" `
            -map 0:v:0 `
            -map 1:a:0 `
            -c:v copy `
            -c:a copy `
            "$output"
    }

    Write-Host ""
    # 🔸 FIX: LiteralPath
    if (Test-Path -LiteralPath $output) {
        Write-Host "[SUCCESS] New file created:" -ForegroundColor Green
        Write-Host " $(Split-Path $output -Leaf)" -ForegroundColor Cyan
    }
    else {
        Write-Host "[ERROR] Failed to create output file." -ForegroundColor Red
        exit 1
    }

    # ----------------- Loop Prompt -----------------
    Write-Host ""
    Write-Host "Press ENTER to select different audio for same video" -ForegroundColor Cyan
    Write-Host "Press ESC to exit" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
        # ESC key - exit
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host "Exiting..." -ForegroundColor Gray
            exit 0
        }
    
        # ENTER key - loop (same MP4, different AAC)
        if ($key.VirtualKeyCode -eq 13) {
            Write-Host ""
            Write-Host "Restarting audio selection..." -ForegroundColor Cyan
            Write-Host ""
            break  # Continue to next iteration of main loop
        }
    }

} # End of main while loop