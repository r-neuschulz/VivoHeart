# Build and deploy VivoHeart watchface to connected Garmin watch
# Supports the round AMOLED watches listed in manifest.xml (360/390/416/454 px)

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

# Font size variants: 0=Small (88%), 1=Default (100%), 2=Large (112%), 3=Extra Large (125%, may clip)
$FontSizeVariants = @(
    @{ Scale = 0.88; Suffix = "_s" },
    @{ Scale = 1.0;  Suffix = "" },
    @{ Scale = 1.12; Suffix = "_l" },
    @{ Scale = 1.25; Suffix = "_xl" }
)

# Alternate system fonts (generated from Windows fonts via Inkscape)
$SystemFontVariants = @(
    @{ Key = "OCR Extended"; Base = "OcrExtended" },
    @{ Key = "Rockwell Extra Bold"; Base = "RockwellExtraBold" },
    @{ Key = "Sans Bold"; Base = "SansBold" }
)

# Fonts are designed for 454 px screens (resources/fonts). Other resolutions get the same
# fonts scaled by width/454 in resources-round-WxH/fonts, which the compiler picks up as a
# device-qualified override of resources/fonts.
$BaseResolution = 454

# Supported devices come from manifest.xml (single source of truth)
[xml]$manifestXml = Get-Content (Join-Path $PSScriptRoot "manifest.xml") -Raw
$SupportedDevices = @($manifestXml.manifest.application.products.product | ForEach-Object { $_.id })

$sdkConfigPath = "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg"
$devicesDir = "$env:APPDATA\Garmin\ConnectIQ\Devices"

function Get-DeviceWidth([string]$deviceId) {
    $cj = Join-Path $devicesDir "$deviceId\compiler.json"
    if (-not (Test-Path $cj)) { throw "Device '$deviceId' not installed in SDK Manager ($cj missing)" }
    return [int](Get-Content $cj -Raw | ConvertFrom-Json).resolution.width
}

if ($ListDevices) {
    Write-Host "Supported devices:" -ForegroundColor Cyan
    $SupportedDevices | ForEach-Object { Write-Host ("  {0,-22} {1}px" -f $_, (Get-DeviceWidth $_)) }
    exit 0
}

# Generate every font variant for one screen width. Skips the work when the inputs
# (generator scripts, source SVGs, fonts.xml, scale) are unchanged since the last run.
function Build-FontsForWidth([int]$width) {
    $scriptDir = Join-Path $PSScriptRoot "scripts"
    $srcDir = Join-Path $PSScriptRoot "resources\fonts"
    $outDir = if ($width -eq $BaseResolution) { $srcDir } else { Join-Path $PSScriptRoot "resources-round-${width}x${width}\fonts" }
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $resScale = $width / $BaseResolution

    $inputs = @(Get-ChildItem $scriptDir -Filter "Generate-*.ps1") + @(Get-ChildItem $srcDir -Filter "*.svg") + @(Get-Item (Join-Path $srcDir "fonts.xml"))
    $hashes = ($inputs | Sort-Object Name | ForEach-Object { (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ""
    $stampValue = "$hashes|$resScale"
    $stampFile = Join-Path $outDir ".fontstamp"
    if ((Test-Path $stampFile) -and ((Get-Content $stampFile -Raw).Trim() -eq $stampValue)) {
        Write-Host "Fonts for ${width}px up to date." -ForegroundColor DarkGray
        return
    }
    Write-Host "Generating fonts for ${width}px (scale $([Math]::Round($resScale, 3)))..." -ForegroundColor Cyan
    if ($outDir -ne $srcDir) { Copy-Item (Join-Path $srcDir "fonts.xml") $outDir -Force }
    $sourceSvg = Join-Path $srcDir "ProtoMolecule_0.svg"
    foreach ($sz in $FontSizeVariants) {
        $sfx = $sz.Suffix
        $scale = $sz.Scale * $resScale
        $fillPng = "ProtoMolecule_0$sfx.png"
        $fillFnt = "ProtoMolecule$sfx.fnt"
        & (Join-Path $scriptDir "Generate-FillFont.ps1") -OutputPng $fillPng -Scale $scale -SourceDir $srcDir -FontsDir $outDir
        & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -SourceSvg $sourceSvg -OutputFnt $fillFnt -PageFile $fillPng -Scale $scale -FontsDir $outDir
        foreach ($v in $FontOutlineVariants) {
            $outPng = $v.Png -replace '\.png$', "$sfx.png"
            $outFnt = $v.Fnt -replace '\.fnt$', "$sfx.fnt"
            $variantName = if ($v.Outside -eq 8) { "thick" } else { "outline" }
            $tempOutlineSvg = Join-Path $outDir "ProtoMolecule_${variantName}_temp$sfx.svg"
            & (Join-Path $scriptDir "Generate-OutlineFont.ps1") -Outside $v.Outside -Inside $v.Inside -OutputPng $outPng -Scale $scale -TempSvgPath $tempOutlineSvg -SourceDir $srcDir -FontsDir $outDir
            & (Join-Path $scriptDir "Generate-FntFromSvg.ps1") -SourceSvg $tempOutlineSvg -OutputFnt $outFnt -PageFile $outPng -Scale $scale -FontsDir $outDir
            Remove-Item $tempOutlineSvg -ErrorAction SilentlyContinue
        }
    }
    # Alternate system fonts (OCR Extended, Rockwell Extra Bold, Sans Bold)
    foreach ($sf in $SystemFontVariants) {
        foreach ($sz in $FontSizeVariants) {
            $outputBase = if ($sz.Suffix) { $sf.Base + $sz.Suffix } else { $sf.Base }
            & (Join-Path $scriptDir "Generate-SystemFont.ps1") -FontKey $sf.Key -OutputBase $outputBase -Scale ($sz.Scale * $resScale) -SourceDir $srcDir -FontsDir $outDir
        }
    }
    Set-Content -Path $stampFile -Value $stampValue -Encoding ASCII
}

# Base (454 px) fonts are always needed: the compiler validates resources/fonts for every device.
function Build-Fonts([string[]]$devices) {
    $widths = @($BaseResolution) + @($devices | ForEach-Object { Get-DeviceWidth $_ }) | Sort-Object -Unique -Descending
    foreach ($w in $widths) { Build-FontsForWidth $w }
}

function Get-SdkPath {
    if (-not (Test-Path $sdkConfigPath)) {
        Write-Host "Connect IQ SDK not found. Install from: https://developer.garmin.com/connect-iq/sdk/" -ForegroundColor Red
        exit 1
    }
    return (Get-Content $sdkConfigPath -Raw).Trim()
}

function Get-KeyFile {
    $keyBase = if ([System.IO.Path]::IsPathRooted($KeyPath)) { $KeyPath } else { Join-Path $PSScriptRoot $KeyPath }
    foreach ($p in @($keyBase, $keyBase + ".der", $keyBase + ".pem", (Join-Path $PSScriptRoot "developer_key.der"), (Join-Path $PSScriptRoot "developer_key.pem"))) {
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    Write-Host "Developer key not found. Create with VS Code Monkey C extension or: openssl genrsa -out developer_key.pem 4096" -ForegroundColor Red
    exit 1
}

# --- Production build (.iq package for Connect IQ Store) ---
if ($Production) {
    $sdkPath = Get-SdkPath
    $monkeyc = Join-Path $sdkPath "bin\monkeyc.bat"
    $keyFile = Get-KeyFile
    $iqOutput = Join-Path $PSScriptRoot "VivoHeart.iq"
    $junglePath = Join-Path $PSScriptRoot "monkey.jungle"
    Build-Fonts $SupportedDevices
    Write-Host "Building production .iq package for Connect IQ Store ($($SupportedDevices.Count) devices)..." -ForegroundColor Green
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
    $sdkPath = Get-SdkPath
    $monkeyc = Join-Path $sdkPath "bin\monkeyc.bat"
    if (-not (Test-Path $monkeyc)) {
        Write-Host "monkeyc not found at: $monkeyc" -ForegroundColor Red
        exit 1
    }
    $keyFile = Get-KeyFile

    $jungleFile = if ($DebugHR) { "monkey.debug.jungle" } else { "monkey.jungle" }
    $junglePath = Join-Path $PSScriptRoot $jungleFile
    Build-Fonts @($Device)
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
