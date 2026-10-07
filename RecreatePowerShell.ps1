<#
.SYNOPSIS
    Reads SourceCodeManifest.txt from the current folder and recreates the
    entire folder tree, filenames (with extensions), and file contents.

.NOTES
    - No hard-coded paths. Operates on the current directory.
    - Refuses to overwrite existing files unless -Force is passed.
#>

[CmdletBinding()]
param(
    [string]$Manifest   = "SourceCodeManifest.txt",
    [string]$TargetRoot = ".",
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Manifest)) {
    Write-Error "Manifest '$Manifest' not found. Run this from the folder containing SourceCodeManifest.txt."
    exit 1
}

$targetRootFull = (Resolve-Path -LiteralPath $TargetRoot).Path
$utf8NoBom      = New-Object System.Text.UTF8Encoding($false)
$lines          = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $Manifest).Path, $utf8NoBom)

$fileCount = 0
$skipped   = 0
$i         = 0
$n         = $lines.Length

while ($i -lt $n) {
    $line = $lines[$i]

    if ($line -match '^>>>>> FILE: (.+)$') {
        $relPath = $Matches[1].Trim() -replace '/', [IO.Path]::DirectorySeparatorChar
        $i++

        if ($i -ge $n -or $lines[$i] -notmatch '^<<<<< ENCODING: (.+)$') {
            throw "Malformed block at line $i for '$relPath' (expected ENCODING)."
        }
        $encoding = $Matches[1].Trim(); $i++

        if ($i -ge $n -or $lines[$i] -notmatch '^<<<<< SIZE: (\d+)$') {
            throw "Malformed block at line $i for '$relPath' (expected SIZE)."
        }
        $size = [int]$Matches[1]; $i++

        $contentLines = New-Object System.Collections.Generic.List[string]
        while ($i -lt $n -and $lines[$i] -ne '>>>>> END FILE') {
            $contentLines.Add($lines[$i]); $i++
        }
        if ($i -ge $n) { throw "Missing END FILE for '$relPath'." }
        $i++
        if ($i -lt $n -and $lines[$i] -eq '') { $i++ }

        $fullPath = Join-Path $targetRootFull $relPath
        $dir      = Split-Path $fullPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if ((Test-Path -LiteralPath $fullPath) -and -not $Force) {
            Write-Host "  skip (exists): $relPath" -ForegroundColor DarkYellow
            $skipped++
            continue
        }

        if ($encoding -eq 'text') {
            $text = ($contentLines -join "`n")
            [System.IO.File]::WriteAllText($fullPath, $text, $utf8NoBom)
        }
        elseif ($encoding -eq 'base64') {
            $b64   = ($contentLines -join '')
            $bytes = [Convert]::FromBase64String($b64)
            [System.IO.File]::WriteAllBytes($fullPath, $bytes)
        }
        else {
            throw "Unknown encoding '$encoding' for '$relPath'."
        }

        $fileCount++
        if ($fileCount % 25 -eq 0) { Write-Host "  ... $fileCount files restored" -ForegroundColor DarkGray }
    }
    else {
        $i++
    }
}

Write-Host "Done. Restored $fileCount files. Skipped $skipped existing." -ForegroundColor Green
Write-Host "Target root: $targetRootFull" -ForegroundColor Cyan