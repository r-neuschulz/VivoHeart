# Generate .fnt (AngelCode BMFont) files from actual glyph bounding boxes in an SVG.
# Uses Inkscape --query-all to get bounding boxes of text/glyph objects.
# No manual FNT Bounds rectangles required.
#
# Usage: .\Generate-FntFromSvg.ps1 -SourceSvg "ProtoMolecule_0.svg"
#        .\Generate-FntFromSvg.ps1 -SourceSvg "path/to/outline.svg" -PageFile "ProtoMolecule_0_Outline.png"

param(
    [string]$SourceSvg,
    [string]$PageFile = "ProtoMolecule_0.png",
    [string]$OutputFnt = "ProtoMolecule.fnt",
    [double]$Scale = 1.0,
    [string]$FontsDir = (Join-Path $PSScriptRoot "..\resources\fonts")
)

$ErrorActionPreference = "Stop"
$FontsDir = (Resolve-Path $FontsDir).Path
$SvgPath = if ([System.IO.Path]::IsPathRooted($SourceSvg)) { $SourceSvg } else { Join-Path $FontsDir $SourceSvg }
$DestFnt = Join-Path $FontsDir $OutputFnt

if (-not (Test-Path $SvgPath)) {
    Write-Host "Source SVG not found: $SvgPath" -ForegroundColor Red
    exit 1
}

# Find Inkscape
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
    exit 1
}

# Parse SVG to find text elements in Image layer and map id -> digit (char code 48-57)
[xml]$doc = Get-Content -Path $SvgPath -Raw -Encoding UTF8
$imageLayer = $null
foreach ($g in $doc.SelectNodes("//*[local-name()='g']")) {
    $label = $g.GetAttribute("label", "http://www.inkscape.org/namespaces/inkscape")
    if (-not $label) { $label = ($g.Attributes | Where-Object { $_.LocalName -eq "label" }).Value }
    if ($label -eq "Image") { $imageLayer = $g; break }
}
if (-not $imageLayer) {
    Write-Host "Image layer not found in SVG" -ForegroundColor Red
    exit 1
}

$idToChar = @{}
foreach ($text in $imageLayer.SelectNodes(".//*[local-name()='text']")) {
    $tspan = $text.SelectSingleNode(".//*[local-name()='tspan']")
    $digit = if ($tspan -and $tspan.InnerText -match '^\d$') { $tspan.InnerText.Trim() } else { $null }
    if ($digit -and $text.id) {
        $idToChar[$text.id] = [int][char]$digit  # '0'=48, '1'=49, ...
    }
}

# Use one consistent set (text11-20 or text1-10) - prefer text11+ (stroke version)
$textIds = @($idToChar.Keys | Where-Object { $_ -match '^text(1[1-9]|20)$' } | Sort-Object { [int]($_ -replace 'text','') })
if ($textIds.Count -lt 10) {
    $textIds = @($idToChar.Keys | Where-Object { $_ -match '^text(1\d|10)$' } | Sort-Object { [int]($_ -replace 'text','') })
}
if ($textIds.Count -lt 10) {
    Write-Host "Expected 10 digit glyphs in Image layer, found $($textIds.Count)" -ForegroundColor Red
    exit 1
}

# Query Inkscape for bounding boxes
$queryOutput = & $inkscape $SvgPath --query-all 2>$null
if (-not $queryOutput) {
    Write-Host "Inkscape --query-all failed" -ForegroundColor Red
    exit 1
}

$bbox = @{}
foreach ($line in $queryOutput) {
    $parts = $line -split ','
    if ($parts.Count -ge 5) {
        $id = $parts[0].Trim()
        $x = [double]$parts[1]
        $y = [double]$parts[2]
        $w = [double]$parts[3]
        $h = [double]$parts[4]
        $bbox[$id] = @{ x = $x; y = $y; w = $w; h = $h }
    }
}

# Build char list from object bboxes. Use xadvance = max(98, maxGlyphWidth+4) to avoid clipping wide fonts (e.g. Rockwell).
$chars = @()
$defaultXAdvance = 98
$maxW = 0
foreach ($id in $textIds) {
    if (-not $bbox.ContainsKey($id)) { continue }
    $b = $bbox[$id]
    $w = [Math]::Ceiling($b.w)
    if ($w -gt $maxW) { $maxW = $w }
}
$xadvance = [Math]::Max($defaultXAdvance, $maxW + 4)
foreach ($id in $textIds) {
    if (-not $bbox.ContainsKey($id)) { continue }
    $b = $bbox[$id]
    $charId = $idToChar[$id]
    $x = [Math]::Floor($b.x)
    $y = [Math]::Floor($b.y)
    $w = [Math]::Ceiling($b.w)
    $h = [Math]::Ceiling($b.h)
    $xoffset = [Math]::Max(0, [Math]::Floor(($xadvance - $w) / 2))
    $yoffset = 0
    $chars += [PSCustomObject]@{ id = $charId; x = $x; y = $y; w = $w; h = $h; xoff = $xoffset; yoff = $yoffset; xadv = $xadvance }
}

$chars = $chars | Sort-Object -Property id
if ($chars.Count -ne 10) {
    Write-Host "Expected 10 chars, got $($chars.Count)" -ForegroundColor Red
    exit 1
}

# lineHeight/base from max glyph height
$maxHeight = ($chars | ForEach-Object { $_.h } | Measure-Object -Maximum).Maximum
$lineHeight = [Math]::Max(143, $maxHeight + 4)
$base = $lineHeight - 3

# Apply scale
$scaleW = [Math]::Round(512 * $Scale)
$scaleH = [Math]::Round(512 * $Scale)
$scaledSize = [Math]::Round(140 * $Scale)
$scaledLineHeight = [Math]::Round($lineHeight * $Scale)
$scaledBase = [Math]::Round($base * $Scale)

$header = @"
info face="ProtomoleculeRegular" size=$scaledSize bold=0 italic=0 charset="0123456789" unicode=0 stretchH=100 smooth=1 aa=1 padding=2,2,2,2 spacing=0,0 outline=0
common lineHeight=$scaledLineHeight base=$scaledBase scaleW=$scaleW scaleH=$scaleH pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0
page id=0 file="$PageFile"
chars count=$($chars.Count)

"@

$lines = @()
foreach ($c in $chars) {
    $sx = [Math]::Round($c.x * $Scale)
    $sy = [Math]::Round($c.y * $Scale)
    $sw = [Math]::Round($c.w * $Scale)
    $sh = [Math]::Round($c.h * $Scale)
    $sxoff = [Math]::Round($c.xoff * $Scale)
    $syoff = [Math]::Round($c.yoff * $Scale)
    $sxadv = [Math]::Round($c.xadv * $Scale)
    $lines += "char id=$($c.id)   x=$sx    y=$sy    width=$sw    height=$sh   xoffset=$sxoff     yoffset=$syoff    xadvance=$sxadv    page=0  chnl=15"
}

$content = $header + ($lines -join "`n")
$content | Set-Content -Path $DestFnt -Encoding ASCII -NoNewline

Write-Host "Generated $OutputFnt (page=$PageFile, scale=$Scale, from object bboxes)" -ForegroundColor Cyan
