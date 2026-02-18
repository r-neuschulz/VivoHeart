# Build and deploy VivoHeart watchface to connected Garmin watch
# Supports all 454x454 round AMOLED watches (same resolution as Epix 2 Pro 51mm)

param(
    [string]$KeyPath = "developer_key.der",
    [string]$Device = "epix2pro51mm",
    [switch]$ListDevices,  # Show supported devices and exit
    [string]$Output = "VivoHeart.prg",
    [switch]$NoBuild,
    [switch]$BuildOnly,  # Build .prg only, exit before deploy (artifact ready for manual copy)
    [switch]$Production,  # Build .iq package for Connect IQ Store submission
    [switch]$Emulator,
    [switch]$DebugHR,    # Use synthetic HR data (ramp through all zones) for visual testing
    [switch]$DeploySettings  # Also copy .SET from simulator temp to device (for sideloaded app settings)
)

$ErrorActionPreference = "Stop"

# Font outline variants: Outside px (expand rects to fit). Change here to tune outline thickness.
$FontOutlineVariants = @(
    @{ Outside = 1; Inside = 1; Png = "ProtoMolecule_0_Outline.png"; Fnt = "ProtoMolecule_outline.fnt" },
    @{ Outside = 8; Inside = 1; Png = "ProtoMolecule_0_Outline_Thick.png"; Fnt = "ProtoMolecule_outline_thick.fnt" }
)
$FontExpandRects = ($FontOutlineVariants | ForEach-Object { $_.Outside } | Measure-Object -Maximum).Maximum

# Font size variants: 0=Small (88%), 1=Default (100%), 2=Large (112%), 3=Extra Large (125%, may clip)
$FontSizeVariants = @(
    @{ Scale = 0.88; Suffix = "_s" },
    @{ Scale = 1.0;  Suffix = "" },
    @{ Scale = 1.12; Suffix = "_l" },
    @{ Scale = 1.25; Suffix = "_xl" }
)

# 454x454 round AMOLED devices (same resolution, single build)
$SupportedDevices = @(
    "epix2pro51mm", "approachs7047mm", "descentmk351mm",
    "fenix847mm", "fr57047mm", "fr965", "fr970",
    "venu3"
)
if ($ListDevices) {
    Write-Host "Supported devices (454x454):" -ForegroundColor Cyan
    $SupportedDevices | ForEach-Object { Write-Host "  $_" }
    exit 0
}

# --- Production build (.iq package for Connect IQ Store) ---
if ($Production) {
    $sdkConfig = "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg"
    if (-not (Test-Path $sdkConfig)) {
        Write-Host "Connect IQ SDK not found. Install from: https://developer.garmin.com/connect-iq/sdk/" -ForegroundColor Red
        exit 1
    }
    $sdkPath = (Get-Content $sdkConfig -Raw).Trim()
    $monkeyc = Join-Path $sdkPath "bin\monkeyc.bat"
    if (-not (Test-Path $monkeyc)) {
        Write-Host "monkeyc not found at: $monkeyc" -ForegroundColor Red
        exit 1
    }
    $keyBase = if ([System.IO.Path]::IsPathRooted($KeyPath)) { $KeyPath } else { Join-Path $PSScriptRoot $KeyPath }
    $keyFile = $null
    foreach ($p in @($keyBase, $keyBase + ".der", $keyBase + ".pem", (Join-Path $PSScriptRoot "developer_key.der"), (Join-Path $PSScriptRoot "developer_key.pem"))) {
        if (Test-Path $p) { $keyFile = (Resolve-Path $p).Path; break }
    }
    if (-not $keyFile) {
        Write-Host "Developer key not found. Create with VS Code Monkey C extension or: openssl genrsa -out developer_key.pem 4096" -ForegroundColor Red
        exit 1
    }
    $iqOutput = Join-Path $PSScriptRoot "VivoHeart.iq"
    $junglePath = Join-Path $PSScriptRoot "monkey.jungle"
    $scriptDir = Join-Path $PSScriptRoot "scripts"
    # Font size variants: generate fill, outline, outline_thick for each size
    foreach ($sz in $FontSizeVariants) {
        $sfx = $sz.Suffix
        $fillPng = "ProtoMolecule_0$sfx.png"
        $fillFnt = "ProtoMolecule$sfx.fnt"
        & (Join-Path $scriptDir "Generate-FillFont.ps1") -OutputPng $fillPng -Scale $sz.Scale
        & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -ExpandRects $FontExpandRects -OutputFnt $fillFnt -PageFile $fillPng -Scale $sz.Scale
        foreach ($v in $FontOutlineVariants) {
            $outPng = $v.Png -replace '\.png$', "$sfx.png"
            $outFnt = $v.Fnt -replace '\.fnt$', "$sfx.fnt"
            & (Join-Path $scriptDir "Generate-OutlineFont.ps1") -Outside $v.Outside -Inside $v.Inside -OutputPng $outPng -Scale $sz.Scale
            & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -ExpandRects $FontExpandRects -OutputFnt $outFnt -PageFile $outPng -Scale $sz.Scale
        }
    }
    Write-Host "Building production .iq package for Connect IQ Store..." -ForegroundColor Green
    & $monkeyc -f $junglePath -e -o $iqOutput -y $keyFile -O 3 -r
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "IQ package ready: $iqOutput" -ForegroundColor Green
    exit 0
}

$prgPath = Join-Path $PSScriptRoot $Output
$prgDir = [System.IO.Path]::GetDirectoryName($prgPath)
$prgBaseName = [System.IO.Path]::GetFileNameWithoutExtension($prgPath)
$settingsJsonName = "$prgBaseName-settings.json"
$settingsJsonPath = Join-Path $prgDir $settingsJsonName

# --- Build ---
if (-not $NoBuild) {
    $sdkConfig = "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg"
    if (-not (Test-Path $sdkConfig)) {
        Write-Host "Connect IQ SDK not found. Install from: https://developer.garmin.com/connect-iq/sdk/" -ForegroundColor Red
        exit 1
    }

    $sdkPath = (Get-Content $sdkConfig -Raw).Trim()
    $monkeyc = Join-Path $sdkPath "bin\monkeyc.bat"
    if (-not (Test-Path $monkeyc)) {
        Write-Host "monkeyc not found at: $monkeyc" -ForegroundColor Red
        exit 1
    }

    $keyBase = if ([System.IO.Path]::IsPathRooted($KeyPath)) { $KeyPath } else { Join-Path $PSScriptRoot $KeyPath }
    $keyFile = $null
    foreach ($p in @($keyBase, $keyBase + ".der", $keyBase + ".pem", (Join-Path $PSScriptRoot "developer_key.der"), (Join-Path $PSScriptRoot "developer_key.pem"))) {
        if (Test-Path $p) { $keyFile = (Resolve-Path $p).Path; break }
    }
    if (-not $keyFile) {
        Write-Host "Developer key not found. Create with VS Code Monkey C extension or: openssl genrsa -out developer_key.pem 4096" -ForegroundColor Red
        exit 1
    }

    $jungleFile = if ($DebugHR) { "monkey.debug.jungle" } else { "monkey.jungle" }
    $junglePath = Join-Path $PSScriptRoot $jungleFile
    $scriptDir = Join-Path $PSScriptRoot "scripts"
    # Font size variants: generate fill, outline, outline_thick for each size
    foreach ($sz in $FontSizeVariants) {
        $sfx = $sz.Suffix
        $fillPng = "ProtoMolecule_0$sfx.png"
        $fillFnt = "ProtoMolecule$sfx.fnt"
        & (Join-Path $scriptDir "Generate-FillFont.ps1") -OutputPng $fillPng -Scale $sz.Scale
        & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -ExpandRects $FontExpandRects -OutputFnt $fillFnt -PageFile $fillPng -Scale $sz.Scale
        foreach ($v in $FontOutlineVariants) {
            $outPng = $v.Png -replace '\.png$', "$sfx.png"
            $outFnt = $v.Fnt -replace '\.fnt$', "$sfx.fnt"
            & (Join-Path $scriptDir "Generate-OutlineFont.ps1") -Outside $v.Outside -Inside $v.Inside -OutputPng $outPng -Scale $sz.Scale
            & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -ExpandRects $FontExpandRects -OutputFnt $outFnt -PageFile $outPng -Scale $sz.Scale
        }
    }
    if ($DebugHR) {
        Write-Host "Building for $Device (DEBUG HR - synthetic data)..." -ForegroundColor Yellow
    } else {
        Write-Host "Building for $Device..." -ForegroundColor Green
    }
    & $monkeyc -d $Device -f $junglePath -o $prgPath -y $keyFile -O 3
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "Build succeeded." -ForegroundColor Green

    # Ensure settings JSON is alongside .prg (simulator looks in same directory)
    # monkeyc may put it in bin/ with device prefix; copy to prg dir if found elsewhere
    if (-not (Test-Path $settingsJsonPath)) {
        $binDir = Join-Path $PSScriptRoot "bin"
        $found = $null
        if (Test-Path (Join-Path $binDir $settingsJsonName)) {
            $found = Join-Path $binDir $settingsJsonName
        } elseif (Test-Path $binDir) {
            $anySettings = Get-ChildItem -Path $binDir -Filter "*-settings.json" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($anySettings) { $found = $anySettings.FullName }
        }
        if ($found) {
            Copy-Item -Path $found -Destination $settingsJsonPath -Force
            Write-Host "Copied settings to $settingsJsonPath" -ForegroundColor Cyan
        }
    }
}

# --- Build-only: produce .prg artifact and exit ---
if ($BuildOnly) {
    Write-Host "PRG artifact ready: $prgPath" -ForegroundColor Green
    exit 0
}

# --- Deploy or Emulator ---
if (-not (Test-Path $prgPath)) {
    Write-Host "PRG not found: $prgPath" -ForegroundColor Red
    exit 1
}

if ($Emulator) {
    $sdkConfig = "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg"
    if (-not (Test-Path $sdkConfig)) {
        Write-Host "Connect IQ SDK not found. Install from: https://developer.garmin.com/connect-iq/sdk/" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $settingsJsonPath)) {
        Write-Host "Warning: $settingsJsonName not found alongside .prg. Simulator may show 'No values defined' for settings." -ForegroundColor Yellow
        Write-Host "  Build with VS Code/Eclipse to generate it, or ensure resources/settings/*.xml are correct." -ForegroundColor Yellow
    }
    $sdkPath = (Get-Content $sdkConfig -Raw).Trim()
    $simulator = Join-Path $sdkPath "bin\simulator.exe"
    $monkeydo = Join-Path $sdkPath "bin\monkeydo.bat"
    if (-not (Test-Path $simulator) -or -not (Test-Path $monkeydo)) {
        Write-Host "Simulator not found. Ensure device images are installed via SDK Manager." -ForegroundColor Red
        exit 1
    }
    Write-Host "Starting simulator..." -ForegroundColor Green
    Start-Process -FilePath $simulator -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # monkeydo auto-discovers the debug XML but NOT the settings JSON.
    # The simulator reads settings schema from GARMIN/Settings/<APPNAME>-settings.json
    # inside its temp directory.  The VS Code debug adapter pushes this via a dedicated
    # pushSettingsJson call, but monkeydo has no equivalent — so we copy it ourselves.
    if (Test-Path $settingsJsonPath) {
        $simSettingsDir = Join-Path $env:LOCALAPPDATA "Temp\com.garmin.connectiq\GARMIN\Settings"
        if (-not (Test-Path $simSettingsDir)) { New-Item -ItemType Directory -Path $simSettingsDir -Force | Out-Null }
        $destName = $prgBaseName.ToUpper() + "-settings.json"
        Copy-Item -Path $settingsJsonPath -Destination (Join-Path $simSettingsDir $destName) -Force
        Write-Host "Copied settings JSON to simulator." -ForegroundColor Cyan
    }

    Write-Host "Launching app on $Device..." -ForegroundColor Green
    & $monkeydo (Resolve-Path $prgPath).Path $Device
    Write-Host "Emulator ready. Use File > Quit to close." -ForegroundColor Green
    exit 0
}

Write-Host "Looking for Garmin watch..." -ForegroundColor Green

function Find-GarminAppsPath {
    $drives = Get-WmiObject -Class Win32_LogicalDisk -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -and (Test-Path $_.DeviceID) }
    foreach ($drive in $drives) {
        $garminPath = Join-Path $drive.DeviceID "GARMIN\APPS"
        if (Test-Path $garminPath) {
            return @{ Path = $garminPath; DeviceID = $drive.DeviceID.TrimEnd('\'); UseShell = $false }
        }
    }
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($device in $shell.NameSpace(17).Items()) {
            $appsFolder = Get-AppsFolderFromDevice $device $shell
            if ($appsFolder) {
                return @{ Folder = $appsFolder; Device = $device; Shell = $shell; UseShell = $true }
            }
        }
    }
    catch { }
    return $null
}

function Get-AppsFolderFromDevice($device, $shell) {
    try {
        foreach ($item in @($device.GetFolder.Items())) {
            if ($item.Name -eq "GARMIN") {
                foreach ($sub in @($item.GetFolder.Items())) {
                    if ($sub.Name -eq "APPS") { return $sub.GetFolder }
                }
            }
            if ($item.Name -eq "Internal Storage") {
                foreach ($sub in @($item.GetFolder.Items())) {
                    if ($sub.Name -eq "GARMIN") {
                        foreach ($apps in @($sub.GetFolder.Items())) {
                            if ($apps.Name -eq "APPS") { return $apps.GetFolder }
                        }
                    }
                }
            }
        }
    }
    catch { }
    return $null
}

function Invoke-Eject($deviceId, $shell) {
    try {
        $shell.NameSpace(17).ParseName($deviceId).InvokeVerb("Eject")
        Write-Host "Device safely ejected!" -ForegroundColor Green
    }
    catch {
        Write-Host "Could not auto-eject. Please eject manually from system tray." -ForegroundColor Yellow
    }
}

$target = Find-GarminAppsPath
if (-not $target) {
    Write-Host "Watch not found! Connect via USB, enable mass storage mode." -ForegroundColor Red
    exit 1
}

# Resolve paths: APPS and APPS\SETTINGS (settings is subfolder of APPS)
$appsPath = $null
$settingsPath = $null
if ($target.UseShell) {
    Write-Host "Copying to device..." -ForegroundColor Yellow
    $target.Folder.CopyHere((Resolve-Path $prgPath).Path, 5648)
    # Shell: we don't have a direct path for SETTINGS; DeploySettings will warn
}
else {
    $appsPath = $target.Path
    $settingsPath = Join-Path $appsPath "SETTINGS"
    Write-Host "Copying to $appsPath..." -ForegroundColor Yellow
    Copy-Item -Path $prgPath -Destination $appsPath -Force
}

# Optionally deploy settings (.SET) for sideloaded apps (GCM won't show settings UI)
if ($DeploySettings) {
    $tempBases = @(
        [System.IO.Path]::Combine($env:TEMP, "GARMIN", "APPS", "SETTINGS"),
        [System.IO.Path]::Combine($env:TEMP, "com.garmin.connectiq", "GARMIN", "APPS", "SETTINGS")
    )
    $setFile = $null
    foreach ($base in $tempBases) {
        if (Test-Path $base) {
            $candidate = Get-ChildItem -Path $base -Filter "*.set" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*VivoHeart*" -or $_.Name -like "*5c3185b52*" } |
                Select-Object -First 1
            if (-not $candidate) { $candidate = Get-ChildItem -Path $base -Filter "*.set" -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if ($candidate) { $setFile = $candidate.FullName; break }
        }
    }
    if ($setFile -and $settingsPath) {
        if (-not (Test-Path $settingsPath)) { New-Item -ItemType Directory -Path $settingsPath -Force | Out-Null }
        Copy-Item -Path $setFile -Destination $settingsPath -Force
        Write-Host "Copied settings to device (APPS\SETTINGS)." -ForegroundColor Cyan
    }
    elseif ($setFile -and $target.UseShell) {
        # Shell: navigate to SETTINGS and copy
        Write-Host "Settings .SET found; Shell copy to SETTINGS not implemented. Copy manually from: $setFile" -ForegroundColor Yellow
    }
    elseif (-not $setFile) {
        Write-Host "No .SET file in simulator temp. Run app in simulator first, change settings, then deploy." -ForegroundColor Yellow
    }
}

if ($target.UseShell) {
    Start-Sleep -Seconds 2
    Invoke-Eject $target.Device.Name $target.Shell
}
else {
    Invoke-Eject $target.DeviceID (New-Object -ComObject Shell.Application)
}

Write-Host "Deployed! Check your watch's app list." -ForegroundColor Green
