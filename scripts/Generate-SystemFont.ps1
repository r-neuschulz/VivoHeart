# Generate bitmap font from a system font (OCR Extended, Rockwell Extra Bold, Sans Bold).
# Produces fill, outline, and outline_thick variants (like ProtoMolecule).
# Assumes font is installed; warns and skips if export fails (e.g. font not present).
# Usage: .\Generate-SystemFont.ps1 -FontKey "OCR Extended" -OutputBase "OcrExtended" -Scale 1.0

param(
    [string]$FontKey,
    [string]$OutputBase,
    [double]$Scale = 1.0,
    [string]$FontsDir = (Join-Path $PSScriptRoot "..\resources\fonts")
)

$ErrorActionPreference = "Stop"
$FontsDir = (Resolve-Path $FontsDir).Path
$scriptDir = $PSScriptRoot

# FontKey -> Inkscape/SVG font-family display name (assume font is installed)
$FontDisplayNames = @{
    "OCR Extended"       = "OCR A Extended"
    "Rockwell Extra Bold" = "Rockwell Extra Bold"
    "Sans Bold"          = "Segoe UI Bold"
}
$fontDisplayName = if ($FontDisplayNames.ContainsKey($FontKey)) { $FontDisplayNames[$FontKey] } else { $FontKey }

$templatePath = Join-Path $FontsDir "SystemFontTemplate.svg"
if (-not (Test-Path $templatePath)) {
    Write-Host "Template not found: $templatePath" -ForegroundColor Red
    exit 1
}

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
    Write-Host "Inkscape not found." -ForegroundColor Red
    exit 1
}

$exportSize = [Math]::Round(512 * $Scale)

function Export-SystemFontVariant {
    param([string]$Content, [string]$PngName, [string]$FntName)
    $tempSvg = Join-Path $FontsDir "${OutputBase}_temp.svg"
    $Content | Set-Content -Path $tempSvg -Encoding UTF8 -NoNewline
    $destPng = Join-Path $FontsDir $PngName
    $exportArgs = @($tempSvg, "--export-filename=$destPng", "--export-type=png", "--export-width=$exportSize", "--export-height=$exportSize")
    & $inkscape $exportArgs 2>&1 | Out-Null
    if (-not (Test-Path $destPng)) {
        Remove-Item $tempSvg -ErrorAction SilentlyContinue
        return $false
    }
    & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -SourceSvg $tempSvg -OutputFnt $FntName -PageFile $PngName -Scale $Scale 2>&1 | Out-Null
    Remove-Item $tempSvg -ErrorAction SilentlyContinue
    return $true
}

# 1. Fill (with thin stroke for consistency)
$content = Get-Content -Path $templatePath -Raw -Encoding UTF8
$content = $content -replace '\{\{FONT_FAMILY\}\}', $fontDisplayName
if (-not (Export-SystemFontVariant -Content $content -PngName "${OutputBase}.png" -FntName "${OutputBase}.fnt")) {
    Write-Host "Skipping $OutputBase: font '$fontDisplayName' may not be installed or export failed." -ForegroundColor Yellow
    exit 0
}

# 2. Outline (stroke-only, thin)
$outlineStyle = "fill:none;stroke:#ffffff;stroke-width:2"
$contentOutline = $content -replace 'fill:#ffffff;stroke:#010101;stroke-width:1', $outlineStyle
Export-SystemFontVariant -Content $contentOutline -PngName "${OutputBase}_Outline.png" -FntName "${OutputBase}_outline.fnt"

# 3. Outline thick
$outlineThickStyle = "fill:none;stroke:#ffffff;stroke-width:9"
$contentThick = $content -replace 'fill:#ffffff;stroke:#010101;stroke-width:1', $outlineThickStyle
Export-SystemFontVariant -Content $contentThick -PngName "${OutputBase}_Outline_Thick.png" -FntName "${OutputBase}_outline_thick.fnt"

Write-Host "Generated $OutputBase font (${fontDisplayName}) + outline variants" -ForegroundColor Cyan
