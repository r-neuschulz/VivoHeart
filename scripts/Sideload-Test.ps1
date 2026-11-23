# Put a diagnostic or benchmark build on a USB-connected watch, and read its log back.
#   .\scripts\Sideload-Test.ps1 -Kind bench                 build VHBENCH.prg, copy it + empty log to the watch
#   .\scripts\Sideload-Test.ps1 -Kind diag                  build VHDIAG.prg (step logging, source/Diag.mc)
#   .\scripts\Sideload-Test.ps1 -Kind bench -Fetch          copy the log (and any CIQ_LOG) back and print it
#   .\scripts\Sideload-Test.ps1 -Kind bench -Remove         delete the .prg and log from APPS (if still there)
#
# Both builds install as separate apps ("VH Bench" / "VH Diag", own app ids) so they never
# collide with the store-installed VivoHeart. System.println output goes to
# GARMIN\APPS\LOGS\<PRG NAME>.TXT, but only if that file exists, so an empty one is copied too.

param(
    [ValidateSet("diag", "bench")][string]$Kind = "bench",
    [string]$Device = "epix2pro51mm",
    [switch]$Fetch,
    [switch]$Remove,
    [switch]$NoCopy
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$PrgName = if ($Kind -eq "diag") { "VHDIAG" } else { "VHBENCH" }

function Get-WatchGarminFolder {
    $sh = New-Object -ComObject Shell.Application
    foreach ($dev in $sh.NameSpace(17).Items()) {
        try {
            foreach ($top in @($dev.GetFolder.Items())) {
                foreach ($c in @($top) + @($top.GetFolder.Items())) {
                    if ($c.Name -eq "GARMIN" -and $c.IsFolder) { return @{ Shell = $sh; Garmin = $c.GetFolder; Name = $dev.Name } }
                }
            }
        } catch { }
    }
    return $null
}

function Get-Sub($folder, [string]$name) {
    $item = $folder.Items() | Where-Object { $_.Name -eq $name }
    if (-not $item) { throw "Folder $name not found on watch" }
    return $item.GetFolder
}

if ($Fetch -or $Remove) {
    $w = Get-WatchGarminFolder
    if (-not $w) { Write-Host "Watch not found over USB." -ForegroundColor Red; exit 1 }
    $apps = Get-Sub $w.Garmin "APPS"
    $logs = Get-Sub $apps "LOGS"
    if ($Fetch) {
        $outDir = Join-Path $root "bin\devicelogs"
        New-Item -ItemType Directory -Force $outDir | Out-Null
        foreach ($f in @($logs.Items())) {
            if ($f.Name -match "^$PrgName\." -or $f.Name -match "^CIQ_LOG\.YML") { $w.Shell.NameSpace($outDir).CopyHere($f, 16 + 1024) }
        }
        Start-Sleep -Seconds 3
        Get-ChildItem $outDir -Filter "*" | Where-Object { $_.Name -match "^$PrgName\.|^CIQ_LOG" } |
            ForEach-Object { Write-Host "=== $($_.Name) ($($_.Length) bytes)" -ForegroundColor Cyan; Get-Content $_.FullName }
    }
    if ($Remove) {
        foreach ($pair in @(@($apps, "$PrgName.prg"), @($logs, "$PrgName.TXT"))) {
            $item = $pair[0].Items() | Where-Object { $_.Name -eq $pair[1] }
            if ($item) { $item.InvokeVerb("delete"); Write-Host "Deleted $($pair[1])" -ForegroundColor Yellow }
        }
        Write-Host "If '$(if ($Kind -eq 'diag') { 'VH Diag' } else { 'VH Bench' })' is still in the watch face list, delete it there." -ForegroundColor Yellow
    }
    exit 0
}

& (Join-Path $PSScriptRoot "New-TestManifest.ps1") -Kind $Kind
$sdkPath = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg" -Raw).Trim()
$prg = Join-Path $root "bin\$PrgName.prg"
& (Join-Path $sdkPath "bin\monkeyc.bat") -d $Device -f (Join-Path $root "monkey.$Kind.jungle") -o $prg -y (Join-Path $root "developer_key.der") -O 3
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($NoCopy) { Write-Host "Built $prg" -ForegroundColor Green; exit 0 }

$w = Get-WatchGarminFolder
if (-not $w) { Write-Host "Watch not found over USB. Built $prg only." -ForegroundColor Yellow; exit 1 }
$apps = Get-Sub $w.Garmin "APPS"
$logs = Get-Sub $apps "LOGS"

$emptyLog = Join-Path $root "bin\$PrgName.TXT"
Set-Content -Path $emptyLog -Value $null -NoNewline
$logs.CopyHere($emptyLog, 16 + 1024)
$apps.CopyHere($prg, 16 + 1024)

$size = (Get-Item $prg).Length
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $p = $apps.Items() | Where-Object { $_.Name -eq "$PrgName.prg" }
    $l = $logs.Items() | Where-Object { $_.Name -eq "$PrgName.TXT" }
    if ($p -and $l -and [int64]$p.ExtendedProperty('System.Size') -eq $size) { break }
}
if ($p -and $l) {
    Write-Host "On $($w.Name): APPS\$PrgName.prg ($size bytes) and APPS\LOGS\$PrgName.TXT" -ForegroundColor Green
} else {
    Write-Host "Copy not confirmed (prg: $([bool]$p), log: $([bool]$l))." -ForegroundColor Red; exit 1
}
