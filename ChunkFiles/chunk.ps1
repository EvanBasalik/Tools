param(
    <#
    .SYNOPSIS
        Splits a file into chunks or merges chunks back into a file.

    .PARAMETER FilePath
        Chunk mode: path to the file to split.
        Unchunk mode: path to the _chunks directory, any chunk file inside it, or the
        first chunk file (the script will locate the correct directory automatically).

    .PARAMETER ChunkSizeMB
        Size of each chunk in megabytes. Default is 10.

    .PARAMETER Mode
        "chunk" to split a file; "unchunk" to reassemble chunks. Default is "chunk".

    .PARAMETER FileExtension
        Required for unchunk mode. Extension for the reassembled output file.
        May be supplied with or without a leading dot (e.g. "zip" or ".zip").

    .EXAMPLE
        # Split a file into 10 MB pieces
        .\chunk.ps1 -FilePath "C:\path\to\largefile.zip" -ChunkSizeMB 10 -Mode chunk

    .EXAMPLE
        # Reassemble chunks — pass the _chunks directory
        .\chunk.ps1 -FilePath "C:\path\to\largefile_chunks" -Mode unchunk -FileExtension zip

    .EXAMPLE
        # Reassemble chunks — pass any chunk file inside the _chunks directory
        .\chunk.ps1 -FilePath "C:\path\to\largefile_chunks\0000_largefile.zip" -Mode unchunk -FileExtension zip
    #>
    [string]$FilePath = ".",
    [int]$ChunkSizeMB = 10,
    [ValidateSet("chunk", "unchunk")][string]$Mode = "chunk",
    [string]$FileExtension
)

if ($Mode -eq "unchunk" -and -not $FileExtension) {
    throw "FileExtension parameter is required when using unchunk mode"
}

if ($Mode -eq "chunk" -and $FileExtension) {
    throw "FileExtension parameter should not be provided when using chunk mode"
}

if ($FileExtension -and -not $FileExtension.StartsWith(".")) {
    $FileExtension = ".$FileExtension"
}

$chunkSizeBytes = $ChunkSizeMB * 1MB

if ($Mode -eq "chunk") {
    $file = Get-Item $FilePath
    $outputDir = Join-Path $file.DirectoryName "$($file.BaseName)_chunks"

    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }

    $stream = [System.IO.File]::OpenRead($file.FullName)
    $chunkNumber = 0
    $buffer = New-Object byte[] $chunkSizeBytes

    while ($stream.Position -lt $stream.Length) {
        $bytesRead = $stream.Read($buffer, 0, $chunkSizeBytes)
        $chunkFileName = "{0:D4}_{1}" -f $chunkNumber, $file.Name
        $chunkPath = Join-Path $outputDir $chunkFileName
        
        [System.IO.File]::WriteAllBytes($chunkPath, $buffer[0..($bytesRead - 1)])
        Write-Host "Created: $chunkFileName ($bytesRead bytes)"
        
        $chunkNumber++
    }

    $stream.Close()
    Write-Host "`nChunking complete. Files saved to: $outputDir"
}
else {
    if (Test-Path -LiteralPath $FilePath -PathType Container) {
        # User passed the _chunks directory directly
        $chunkDir = $FilePath
    } elseif (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        # User passed a chunk file — use its parent directory
        $chunkDir = (Get-Item -LiteralPath $FilePath).DirectoryName
    } else {
        # Path doesn't exist — check if the parent directory contains chunk files
        $parentDir = Split-Path $FilePath -Parent
        $candidateName = [System.IO.Path]::GetFileNameWithoutExtension((Split-Path $FilePath -Leaf)) -replace "^\d{4}_", ""
        $chunksDirCandidate = Join-Path $parentDir "${candidateName}_chunks"
        if (Test-Path -LiteralPath $chunksDirCandidate -PathType Container) {
            Write-Host "Path not found; using inferred chunks directory: $chunksDirCandidate"
            $chunkDir = $chunksDirCandidate
        } elseif (Test-Path -LiteralPath $parentDir -PathType Container) {
            # Chunks may be directly in the parent directory
            $chunkDir = $parentDir
        } else {
            throw "File path does not exist: $FilePath"
        }
    }
    $chunks = Get-ChildItem -LiteralPath $chunkDir -Filter "????_*" | Sort-Object Name
    $baseName = (Split-Path $chunkDir -Leaf) -replace "_chunks", ""
    $outputFile = Join-Path $chunkDir "$baseName$FileExtension"
    
    $outStream = [System.IO.File]::Create($outputFile)
    
    foreach ($chunk in $chunks) {
        $chunkBytes = [System.IO.File]::ReadAllBytes($chunk.FullName)
        $outStream.Write($chunkBytes, 0, $chunkBytes.Length)
        Write-Host "Merged: $($chunk.Name)"
    }
    
    $outStream.Close()
    Write-Host "`nUnchunking complete. File saved to: $outputFile"
}