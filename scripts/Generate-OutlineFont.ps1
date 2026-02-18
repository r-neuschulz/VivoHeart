# Generate outline (contour-only) font PNG from base SVG at build time.
# Source: ProtoMolecule_0.svg. Output: contour with outside+inside px stroke.
# Requires Inkscape (used to create the SVGs). No other dependencies.
#
# Usage: .\Generate-OutlineFont.ps1 -Outside 1 -Inside 1 -OutputPng "ProtoMolecule_0_Outline.png"
#        .\Generate-OutlineFont.ps1 -Outside 2 -Inside 1 -OutputPng "ProtoMolecule_0_Outline_Thick.png"

param(
    [int]$Outside = 1,
    [int]$Inside = 1,
    [string]$OutputPng = "ProtoMolecule_0_Outline.png",
    [string]$FontsDir = (Join-Path $PSScriptRoot "..\resources\fonts")
)

$ErrorActionPreference = "Stop"
$FontsDir = (Resolve-Path $FontsDir).Path
$SourceSvg = Join-Path $FontsDir "ProtoMolecule_0.svg"
$TempSvg = Join-Path $env:TEMP "ProtoMolecule_outline_$([guid]::NewGuid().ToString('N').Substring(0,8)).svg"
$DestPng = Join-Path $FontsDir $OutputPng

if (-not (Test-Path $SourceSvg)) {
    Write-Host "Source SVG not found: $SourceSvg" -ForegroundColor Red
    exit 1
}

$strokeWidth = $Outside + $Inside
if ($strokeWidth -lt 1) { $strokeWidth = 1 }
$outlineStyle = "fill:none;stroke:#ffffff;stroke-width:$strokeWidth"

# Read SVG and replace fill/stroke with contour-only (Protomolecule digit glyphs)
$content = Get-Content -Path $SourceSvg -Raw -Encoding UTF8

# Replace fill+stroke variants with outline style (contour only)
$content = $content -replace 'fill:#ffffff;stroke:#010101;stroke-width:3', $outlineStyle
$content = $content -replace 'fill:#ffffff;stroke:#010101', $outlineStyle
$content = $content -replace ';fill:#ffffff"', ";$outlineStyle`""  # fill-only (no stroke) glyphs

# Remove FNT Bounds layer so exported PNG has no cyan rects
$content = $content -replace '(<g[^>]*inkscape:label="FNT Bounds"[^>]*>[\s\S]*?</g>)', ''

$content | Set-Content -Path $TempSvg -Encoding UTF8 -NoNewline

# Export to PNG via Inkscape
$inkscapeCmd = Get-Command "inkscape" -ErrorAction SilentlyContinue
$inkscapePaths = @(
    $(if ($inkscapeCmd) { $inkscapeCmd.Source }),
    "C:\Program Files\Inkscape\bin\inkscape.exe",
    "C:\Program Files (x86)\Inkscape\bin\inkscape.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\Inkscape\bin\inkscape.exe")
)
$inkscape = $null
foreach ($p in $inkscapePaths) {
    if ($p -and (Test-Path $p -ErrorAction SilentlyContinue)) { $inkscape = $p; break }
}
if (-not $inkscape) {
    Write-Host "Inkscape not found. Install from https://inkscape.org or add to PATH." -ForegroundColor Red
    Remove-Item $TempSvg -ErrorAction SilentlyContinue
    exit 1
}

& $inkscape $TempSvg --export-filename=$DestPng --export-type=png 2>&1 | Out-Null
Remove-Item $TempSvg -ErrorAction SilentlyContinue

if (-not (Test-Path $DestPng)) {
    Write-Host "Inkscape export failed. PNG not created: $DestPng" -ForegroundColor Red
    exit 1
}

Write-Host "Generated outline font: $OutputPng (outside=$Outside, inside=$Inside)" -ForegroundColor Cyan
