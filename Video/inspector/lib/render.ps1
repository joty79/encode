# =============================
# CONFIG (Column Widths)
# =============================
$W_LABEL = 13  # Column 1 (Yellow Labels)
$W_C1    = 22  # Column 2
$W_C2    = 18  # Column 3
$W_C3    = 22  # Column 4
$W_C4    = 18  # Column 5

$SEP_CHAR = "─" 
$SEP = $SEP_CHAR * 105 

# =============================
# HELPERS
# =============================

function Write-Centered-Cell {
    param (
        [string]$Value = "", 
        [string]$Unit = "", 
        [int]$Width, 
        [bool]$Pipe = $true
    )
    
    $fullTextLength = if ($Value -and $Unit) { "$Value $Unit".Length } else { ($Value + $Unit).Length }
    
    $padTotal = $Width - $fullTextLength
    $padLeft  = [Math]::Max(0, [Math]::Floor($padTotal / 2))
    $padRight = [Math]::Max(0, $padTotal - $padLeft)

    Write-Host (" " * $padLeft) -NoNewline

    $color = (
		$Value -like "*≠*" -or
		$Unit  -like "*VFR*"
	) ? "Red" : "Green"

	if ($Value) { Write-Host $Value -ForegroundColor $color -NoNewline }

    if ($Value -and $Unit) { Write-Host " " -NoNewline } 
    if ($Unit)  { Write-Host $Unit -ForegroundColor White -NoNewline }

    Write-Host (" " * $padRight) -NoNewline

    if ($Pipe) {
        Write-Host " | " -ForegroundColor White -NoNewline
    }
}

function Render-Separator {
    param ($Color = "Green")
    Write-Host $SEP -ForegroundColor $Color
}

# =============================
# PUBLIC RENDER FUNCTIONS
# =============================

function Render-File {
    param ($Path)
    Render-Separator -Color Green  
    Write-Host ("File:".PadRight($W_LABEL)) -ForegroundColor Yellow -NoNewline
    Write-Host "| " -ForegroundColor White -NoNewline
    Write-Host $Path -ForegroundColor Cyan
    Render-Separator -Color White  
}

function Render-Video {
    param ($Res,$Bitrate,$Fps,$Scan,$FpsMode)

    Write-Host ("Video:".PadRight($W_LABEL)) -ForegroundColor Yellow -NoNewline
    Write-Host "| " -ForegroundColor White -NoNewline
    
    Write-Centered-Cell $Res "Pixels" $W_C1
    Write-Centered-Cell $Bitrate "Mbps" $W_C2
    
    # Combined $Fps and lowercase "fps" into the Green Value slot
	   if ($FpsMode -eq "VFR") {
		Write-Centered-Cell "$Fps fps" "(VFR)" $W_C3
	}
	else {
		Write-Centered-Cell "$Fps fps" "(CFR)" $W_C3
	}
    
    Write-Centered-Cell $Scan "" $W_C4 -Pipe $false
    Write-Host "" 
}

function Render-Compression {
    param ($Density,$Policy,$Codec)

    Write-Host ("Compression:".PadRight($W_LABEL)) -ForegroundColor Yellow -NoNewline
    Write-Host "| " -ForegroundColor White -NoNewline

    Write-Centered-Cell $Density $Policy $W_C1
    Write-Centered-Cell $Codec "Codec" $W_C2
    
    Write-Centered-Cell "" "" $W_C3
    Write-Centered-Cell "" "" $W_C4 -Pipe $false
    Write-Host ""
}

function Render-Geometry {
    param ($Sar,$Dar)

    Write-Host ("Geometry:".PadRight($W_LABEL)) -ForegroundColor Yellow -NoNewline
    Write-Host "| " -ForegroundColor White -NoNewline

		if ($Sar -eq "1:1") {
		Write-Centered-Cell $Sar "SAR" $W_C1
	}
		else {
		# SAR ≠ 1:1 → warning inside the same cell
		Write-Centered-Cell "$Sar ≠" "SAR" $W_C1
	}

    Write-Centered-Cell $Dar "DAR" $W_C2
    
    Write-Centered-Cell "" "" $W_C3
    Write-Centered-Cell "" "" $W_C4 -Pipe $false
    Write-Host "" 
    Render-Separator -Color White 
}

function Render-Audio {
    param ($SampleRate)

    Write-Host ("Audio:".PadRight($W_LABEL)) -ForegroundColor Yellow -NoNewline
    Write-Host "| " -ForegroundColor White -NoNewline
    Write-Host "$SampleRate " -ForegroundColor Green -NoNewline
    Write-Host "Hz" -ForegroundColor White
    Render-Separator -Color Green 
}
