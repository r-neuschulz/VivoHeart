# Generate fill (solid) font PNG from base SVG at build time.
# Source: ProtoMolecule_0.svg. Output: filled glyphs (no FNT Bounds).
# Requires Inkscape.
#
# Usage: .\Generate-FillFont.ps1 -OutputPng "ProtoMolecule_0.png"
#        .\Generate-FillFont.ps1 -OutputPng "ProtoMolecule_0_s.png" -Scale 0.88

param(
    [string]$OutputPng = "ProtoMolecule_0.png",
    [double]$Scale = 1.0,
    [string]$FontsDir = (Join-Path $PSScriptRoot "..\resources\fonts")
)

$ErrorActionPreference = "Stop"
$FontsDir = (Resolve-Path $FontsDir).Path
$SourceSvg = Join-Path $FontsDir "ProtoMolecule_0.svg"
$TempSvg = Join-Path $env:TEMP "ProtoMolecule_fill_$([guid]::NewGuid().ToString('N').Substring(0,8)).svg"
$DestPng = Join-Path $FontsDir $OutputPng

if (-not (Test-Path $SourceSvg)) {
    Write-Host "Source SVG not found: $SourceSvg" -ForegroundColor Red
    exit 1
}

# Remove FNT Bounds layer so exported PNG has no cyan rects
$content = Get-Content -Path $SourceSvg -Raw -Encoding UTF8
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

$exportSize = [Math]::Round(512 * $Scale)
$exportArgs = @($TempSvg, "--export-filename=$DestPng", "--export-type=png", "--export-width=$exportSize", "--export-height=$exportSize")
& $inkscape $exportArgs 2>&1 | Out-Null
Remove-Item $TempSvg -ErrorAction SilentlyContinue

if (-not (Test-Path $DestPng)) {
    Write-Host "Inkscape export failed. PNG not created: $DestPng" -ForegroundColor Red
    exit 1
}

Write-Host "Generated fill font: $OutputPng (scale=$Scale)" -ForegroundColor Cyan
