<#
.SYNOPSIS
    Scans the current folder (and all child folders/files) and writes a
    SourceCodeManifest.txt that captures every file's path, extension,
    encoding, size, and content.

.NOTES
    - No hard-coded paths. Operates on the current directory.
    - Skips: $ExcludeFolders and $ExcludeExtensions.
    - Treats files with $textExtensions as UTF-8 text; everything else as base64.
    - Output: SourceCodeManifest.txt in the same folder.
#>

[CmdletBinding()]
param(
    [string]$OutputFile = "SourceCodeManifest.txt",

    [string[]]$ExcludeFolders = @(
        '.git', '.vs', 'bin', 'obj', 'node_modules', 'packages', 'logs', '.idea', '.vscode'
    ),

    [string[]]$ExcludeExtensions = @(
        '.dll', '.pdb', '.exe', '.log', '.tmp', '.cache'
    )
)

$ErrorActionPreference = 'Stop'

# ---- Text extensions (round-trip safe when saved as UTF-8) ----
$textExtensions = @(
    '.cs','.csproj','.sln','.json','.xml','.config','.yml','.yaml','.md','.txt',
    '.html','.htm','.css','.scss','.less','.js','.ts','.jsx','.tsx','.razor',
    '.cshtml','.vbhtml','.sql','.ps1','.psm1','.psd1','.sh','.bat','.cmd',
    '.gitignore','.gitattributes','.editorconfig','.dockerignore','.env','.example',
    '.props','.targets','.resx','.xaml','.vue','.php','.py','.rb','.go',
    '.java','.kt','.swift','.c','.cpp','.h','.hpp','.m','.mm','.pl','.lua','.r',
    '.toml','.ini','.conf','.csv','.tsv','.svg','.map','.lock','.template'
)

# ---- Root is always the current directory ----
$root = (Get-Location).Path

function Test-IsText([string]$path, [string]$ext) {
    if ($textExtensions -contains $ext.ToLowerInvariant()) { return $true }
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try {
            $buf = New-Object byte[] 8192
            $n = $fs.Read($buf, 0, $buf.Length)
            for ($i = 0; $i -lt $n; $i++) {
                if ($buf[$i] -eq 0) { return $false }
            }
            return $true
        } finally { $fs.Dispose() }
    } catch { return $false }
}

function Get-RelativePath([string]$base, [string]$full) {
    $b = $base.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($b.Length)
    }
    return $full
}

Write-Host "Scanning $root ..." -ForegroundColor Cyan

# ---- Collect files (deterministic order) ----
$files = Get-ChildItem -Path $root -Recurse -File -Force |
    Where-Object {
        $rel   = Get-RelativePath $root $_.FullName
        $parts = $rel -split '[\\/]'

        foreach ($p in $parts) {
            if ($ExcludeFolders -contains $p) { return $false }
        }
        if ($ExcludeExtensions -contains $_.Extension.ToLowerInvariant()) { return $false }
        if ($_.FullName -eq (Join-Path $root $OutputFile)) { return $false }
        return $true
    } | Sort-Object FullName

$sb        = New-Object System.Text.StringBuilder
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("# SOURCE CODE MANIFEST")
[void]$sb.AppendLine("# Root     : $root")
[void]$sb.AppendLine("# Created  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("# Host     : $env:COMPUTERNAME")
[void]$sb.AppendLine("# Files    : $($files.Count)")
[void]$sb.AppendLine("# Format   : See HEADER block below.")
[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("# HEADER")
[void]$sb.AppendLine("# Each file block is:")
[void]$sb.AppendLine("#   >>>>> FILE: <relative-path>")
[void]$sb.AppendLine("#   <<<<< ENCODING: text|base64")
[void]$sb.AppendLine("#   <<<<< SIZE: <bytes>")
[void]$sb.AppendLine("#   <content>")
[void]$sb.AppendLine("#   >>>>> END FILE")
[void]$sb.AppendLine("#")
[void]$sb.AppendLine("# For 'text': content is UTF-8 verbatim (line endings preserved as \n).")
[void]$sb.AppendLine("# For 'base64': content is a single line of base64.")
[void]$sb.AppendLine("# Delimiter lines start with '>>>>>' or '<<<<<' at column 0.")
[void]$sb.AppendLine("# ============================================================")
[void]$sb.AppendLine("")

$count = 0
foreach ($f in $files) {
    $rel   = (Get-RelativePath $root $f.FullName) -replace '\\','/'
    $ext   = $f.Extension.ToLowerInvariant()
    $isTxt = Test-IsText $f.FullName $ext

    [void]$sb.AppendLine(">>>>> FILE: $rel")
    [void]$sb.AppendLine("<<<<< ENCODING: $(if ($isTxt) {'text'} else {'base64'})")
    [void]$sb.AppendLine("<<<<< SIZE: $($f.Length)")

    if ($isTxt) {
        $content = [System.IO.File]::ReadAllText($f.FullName, $utf8NoBom)
        $content = $content -replace "`r`n", "`n" -replace "`r", "`n"
        [void]$sb.Append($content)
        if (-not $content.EndsWith("`n")) { [void]$sb.AppendLine("") }
    } else {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        [void]$sb.AppendLine([Convert]::ToBase64String($bytes))
    }

    [void]$sb.AppendLine(">>>>> END FILE")
    [void]$sb.AppendLine("")
    $count++
    if ($count % 25 -eq 0) { Write-Host "  ... $count files" -ForegroundColor DarkGray }
}

$outPath = Join-Path $root $OutputFile
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8NoBom)
Write-Host "Done. Captured $count files into $outPath" -ForegroundColor Green