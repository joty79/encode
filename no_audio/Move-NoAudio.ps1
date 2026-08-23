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
$files = @(Get-ChildItem -LiteralPath $TargetDirectory -File | Where-Object { $videoExtensions -contains $_.Extension.ToLower() })

if ($files.Count -eq 0) {
    Write-Host "Δεν βρέθηκαν αρχεία βίντεο."
    exit
}

foreach ($file in $files) {
    # Ορίσματα για το ffprobe
    $ffprobeArgs = @(
        "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_type",
        "-of", "default=noprint_wrappers=1:nokey=1",
        $file.FullName
    )
    
    # Εκτέλεση ffprobe και λήψη του αποτελέσματος. Αποτυχία probing δεν
    # ισοδυναμεί με αρχείο χωρίς ήχο, οπότε σε κάθε αβέβαιο αποτέλεσμα
    # αφήνουμε το αρχείο ανέγγιχτο.
    try {
        $output = & ffprobe @ffprobeArgs 2>&1
        $ffprobeExitCode = $LASTEXITCODE
    }
    catch {
        Write-Error "Αποτυχία εκκίνησης ffprobe για '$($file.Name)': $($_.Exception.Message). Το αρχείο δεν μετακινήθηκε."
        continue
    }

    if ($ffprobeExitCode -ne 0) {
        $errorText = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        Write-Error "Το ffprobe απέτυχε για '$($file.Name)' με exit code $ffprobeExitCode. $($errorText.Trim()) Το αρχείο δεν μετακινήθηκε."
        continue
    }

    $outputText = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $outputText = $outputText.Trim()

    if (-not [string]::IsNullOrEmpty($outputText) -and
        -not [string]::Equals($outputText, "audio", [StringComparison]::Ordinal)) {
        Write-Error "Το ffprobe επέστρεψε μη αναμενόμενο αποτέλεσμα για '$($file.Name)': '$outputText'. Το αρχείο δεν μετακινήθηκε."
        continue
    }

    $hasAudio = [string]::Equals($outputText, "audio", [StringComparison]::Ordinal)
    
    if (-not $hasAudio) {
        Write-Host "🔸 Μετακίνηση (Χωρίς Ήχο): $($file.Name)" -ForegroundColor Yellow
        
        $noAudioPath = Join-Path -Path $file.DirectoryName -ChildPath "no_audio"
        
        # Δημιουργία του φακέλου αν δεν υπάρχει
        if (-not (Test-Path -LiteralPath $noAudioPath)) {
            New-Item -ItemType Directory -Path $noAudioPath | Out-Null
        }
        
        $destination = Join-Path -Path $noAudioPath -ChildPath $file.Name

        if (Test-Path -LiteralPath $destination) {
            Write-Error "Ο προορισμός υπάρχει ήδη και δεν θα αντικατασταθεί: $destination. Το αρχείο δεν μετακινήθηκε."
            continue
        }

        try {
            Move-Item -LiteralPath $file.FullName -Destination $destination -ErrorAction Stop
        }
        catch {
            Write-Error "Αποτυχία μετακίνησης του '$($file.Name)': $($_.Exception.Message)"
        }
    } else {
        Write-Host "✅ Έχει Ήχο: $($file.Name)" -ForegroundColor Green
    }
}
