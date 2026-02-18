# Generate .fnt (AngelCode BMFont) files from FNT Bounds rects in ProtoMolecule_0.svg.
# Rectangles define glyph bounds (x,y,width,height). Optional data-xoffset, data-yoffset,
# data-xadvance on each rect for metrics; edit in Inkscape (Edit > XML Editor) to tune.
#
# Usage: .\Generate-FntFromSvg.ps1
#        .\Generate-FntFromSvg.ps1 -ExpandRects 2  (for outline_thick - expands bounds)

param(
    [int]$ExpandRects = 0,
    [string]$PageFile = "ProtoMolecule_0.png",
    [string]$OutputFnt = "ProtoMolecule.fnt",
    [double]$Scale = 1.0,
    [string]$FontsDir = (Join-Path $PSScriptRoot "..\resources\fonts")
)

$ErrorActionPreference = "Stop"
$FontsDir = (Resolve-Path $FontsDir).Path
$SourceSvg = Join-Path $FontsDir "ProtoMolecule_0.svg"
$DestFnt = Join-Path $FontsDir $OutputFnt

if (-not (Test-Path $SourceSvg)) {
    Write-Host "Source SVG not found: $SourceSvg" -ForegroundColor Red
    exit 1
}

[xml]$doc = Get-Content -Path $SourceSvg -Raw -Encoding UTF8

# Find FNT Bounds layer (g with inkscape:label="FNT Bounds")
$fntLayer = $null
foreach ($g in $doc.SelectNodes("//*[local-name()='g']")) {
    $label = $g.GetAttribute("label", "http://www.inkscape.org/namespaces/inkscape")
    if (-not $label) { $label = ($g.Attributes | Where-Object { $_.LocalName -eq "label" }).Value }
    if ($label -eq "FNT Bounds") { $fntLayer = $g; break }
}
if (-not $fntLayer) {
    Write-Host "FNT Bounds layer not found in SVG" -ForegroundColor Red
    exit 1
}

# Parse rects: id="fnt-rect-N" where N is char code (48-57 for 0-9)
$chars = @()
$defaultXAdvance = 98

foreach ($rect in $fntLayer.SelectNodes(".//*[local-name()='rect']")) {
    if ($rect.id -notlike "fnt-rect-*") { continue }
    $id = $rect.id
    if ($id -notmatch "fnt-rect-(\d+)") { continue }
    $charId = [int]$Matches[1]

    $x = [int]$rect.x
    $y = [int]$rect.y
    $w = [int]$rect.width
    $h = [int]$rect.height

    if ($ExpandRects -gt 0) {
        $x = [Math]::Max(0, $x - $ExpandRects)
        $y = [Math]::Max(0, $y - $ExpandRects)
        $w = [Math]::Min(512 - $x, $w + 2 * $ExpandRects)
        $h = [Math]::Min(512 - $y, $h + 2 * $ExpandRects)
    }
    $xoffset = if ($rect.GetAttribute("data-xoffset")) { [int]$rect.GetAttribute("data-xoffset") } else { [Math]::Max(0, ($defaultXAdvance - $w) / 2) }
    $yoffset = if ($rect.GetAttribute("data-yoffset")) { [int]$rect.GetAttribute("data-yoffset") } else { 0 }
    $xadvance = if ($rect.GetAttribute("data-xadvance")) { [int]$rect.GetAttribute("data-xadvance") } else { $defaultXAdvance }

    $chars += [PSCustomObject]@{ id = $charId; x = $x; y = $y; w = $w; h = $h; xoff = $xoffset; yoff = $yoffset; xadv = $xadvance }
}

# Sort by char id (0-9)
$chars = $chars | Sort-Object -Property id

# lineHeight/base must >= max glyph height or renderer clips bottom. Derive from tallest char.
$maxHeight = ($chars | ForEach-Object { $_.h } | Measure-Object -Maximum).Maximum
$lineHeight = [Math]::Max(143, $maxHeight + 4)
$base = $lineHeight - 3

# Apply scale to all dimensions
$scaleW = [Math]::Round(512 * $Scale)
$scaleH = [Math]::Round(512 * $Scale)
$scaledSize = [Math]::Round(140 * $Scale)
$scaledLineHeight = [Math]::Round($lineHeight * $Scale)
$scaledBase = [Math]::Round($base * $Scale)

# BMFont text format
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

Write-Host "Generated $OutputFnt (page=$PageFile, scale=$Scale)" -ForegroundColor Cyan
