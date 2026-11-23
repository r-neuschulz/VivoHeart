# Write bin/manifest.<kind>.xml: manifest.xml with its own app id, so diagnostic and
# benchmark builds install next to (never on top of) the real VivoHeart.
# Used by monkey.diag.jungle / monkey.bench.jungle via Sideload-Test.ps1 and Run-Benchmark.ps1.

param([ValidateSet("diag", "bench")][string]$Kind)

$ids = @{
    diag  = "660f00ba-e4dc-4ad6-a2ab-df7ffc144fe9"
    bench = "2085439b-5084-4998-b8f3-9df1f8340193"
}
$root = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content (Join-Path $root "manifest.xml") -Raw
$manifest = $manifest -replace 'id="25d02826-d46b-4b1b-9494-7da33d20852e"', "id=`"$($ids[$Kind])`""
New-Item -ItemType Directory -Force (Join-Path $root "bin") | Out-Null
Set-Content -Path (Join-Path $root "bin\manifest.$Kind.xml") -Value $manifest -Encoding UTF8
