[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetDirectory = $PWD
)

# Καθορισμός των τύπων αρχείων βίντεο προς έλεγχο
$videoExtensions = @('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts', '.m2ts')

if (-not (Test-Path -LiteralPath $TargetDirectory)) {
    Write-Error "Η διαδρομή δεν βρέθηκε: $TargetDirectory"
    exit
}

# Εύρεση αρχείων βίντεο στον επιλεγμένο φάκελο
$files = Get-ChildItem -LiteralPath $TargetDirectory -File | Where-Object { $videoExtensions -contains $_.Extension.ToLower() }

if ($files.Count -eq 0) {
    Write-Host "Δεν βρέθηκαν αρχεία βίντεο."
    exit
}

foreach ($file in $files) {
    $hasAudio = $false
    
    # Ορίσματα για το ffprobe
    $ffprobeArgs = @(
        "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_type",
        "-of", "default=noprint_wrappers=1:nokey=1",
        $file.FullName
    )
    
    # Εκτέλεση ffprobe και λήψη του αποτελέσματος
    $output = & ffprobe @ffprobeArgs 2>&1
    
    # Αν το output περιέχει "audio", τότε υπάρχει ροή ήχου
    if ($output -is [array]) { $output = $output -join "" }
    if (-not [string]::IsNullOrWhiteSpace($output) -and $output.ToString().Trim() -eq "audio") {
        $hasAudio = $true
    }
    
    if (-not $hasAudio) {
        Write-Host "🔸 Μετακίνηση (Χωρίς Ήχο): $($file.Name)" -ForegroundColor Yellow
        
        $noAudioPath = Join-Path -Path $file.DirectoryName -ChildPath "no_audio"
        
        # Δημιουργία του φακέλου αν δεν υπάρχει
        if (-not (Test-Path -LiteralPath $noAudioPath)) {
            New-Item -ItemType Directory -Path $noAudioPath | Out-Null
        }
        
        $destination = Join-Path -Path $noAudioPath -ChildPath $file.Name
        Move-Item -LiteralPath $file.FullName -Destination $destination -Force
    } else {
        Write-Host "✅ Έχει Ήχο: $($file.Name)" -ForegroundColor Green
    }
}
