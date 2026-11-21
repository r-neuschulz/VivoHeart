# Build the benchmark variant (monkey.bench.jungle) and run it in the Connect IQ simulator.
# Prints the BENCH lines emitted by source/VivoHeartBenchView.mc.
#
# Usage: .\scripts\Run-Benchmark.ps1 -Device epix2pro51mm
#        .\scripts\Run-Benchmark.ps1 -Device epix2 -NoBuild -Prg bin\bench_epix2.prg
#
# Simulator timings come from the PC, not the watch: compare runs against each other,
# not against device budgets. For on-device numbers, sideload the bench .prg, create an
# empty GARMIN\APPS\LOGS\<PRGNAME>.TXT on the watch, let the face run ~1 minute, and read
# that file back.

param(
    [string]$Device = "epix2pro51mm",
    [string]$Prg = "",
    [switch]$NoBuild,
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$sdkPath = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg" -Raw).Trim()
if (-not $Prg) { $Prg = "bin\bench_$Device.prg" }
$prgPath = if ([System.IO.Path]::IsPathRooted($Prg)) { $Prg } else { Join-Path $root $Prg }

if (-not $NoBuild) {
    & (Join-Path $sdkPath "bin\monkeyc.bat") -d $Device -f (Join-Path $root "monkey.bench.jungle") -o $prgPath -y (Join-Path $root "developer_key.der") -O 3
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Join-Path $sdkPath "bin\simulator.exe")
    Start-Sleep -Seconds 4
}

$log = Join-Path $env:TEMP "vivoheart_bench_$Device.log"
Remove-Item $log -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath (Join-Path $sdkPath "bin\monkeydo.bat") -ArgumentList "`"$prgPath`"", $Device `
    -RedirectStandardOutput $log -NoNewWindow -PassThru

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if ((Test-Path $log) -and (Select-String -Path $log -Pattern "BENCH DONE" -Quiet)) { break }
}
Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue

if (Test-Path $log) {
    $lines = Select-String -Path $log -Pattern "^BENCH|ERROR|Exception|Watchdog" | ForEach-Object { $_.Line }
    if ($lines) { $lines } else { Write-Host "No BENCH output. Raw log:" -ForegroundColor Yellow; Get-Content $log }
} else {
    Write-Host "No output captured." -ForegroundColor Red
}
