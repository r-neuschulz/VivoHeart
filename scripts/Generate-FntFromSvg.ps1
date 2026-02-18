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

# BMFont text format
$header = @"
info face="ProtomoleculeRegular" size=140 bold=0 italic=0 charset="0123456789" unicode=0 stretchH=100 smooth=1 aa=1 padding=2,2,2,2 spacing=0,0 outline=0
common lineHeight=$lineHeight base=$base scaleW=512 scaleH=512 pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0
page id=0 file="$PageFile"
chars count=$($chars.Count)

"@

$lines = @()
foreach ($c in $chars) {
    $lines += "char id=$($c.id)   x=$($c.x)    y=$($c.y)    width=$($c.w)    height=$($c.h)   xoffset=$($c.xoff)     yoffset=$($c.yoff)    xadvance=$($c.xadv)    page=0  chnl=15"
}

$content = $header + ($lines -join "`n")
$content | Set-Content -Path $DestFnt -Encoding ASCII -NoNewline

Write-Host "Generated $OutputFnt (page=$PageFile)" -ForegroundColor Cyan
