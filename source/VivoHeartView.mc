using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang as Lang;
using Toybox.Application as App;
using Toybox.UserProfile as Up;
using Toybox.ActivityMonitor as Act;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;

class VivoHeartView extends Ui.WatchFace {

    //! Instance variable to store heart rate zones and font
    private var heartRateZones as Lang.Array or Null;
    private var bigNumProtomolecule as Gfx.FontDefinition or Gfx.FontReference or Ui.FontResource = Graphics.FONT_LARGE;
    private var bigNumProtomoleculeOutline as Gfx.FontDefinition or Gfx.FontReference or Ui.FontResource = Graphics.FONT_MEDIUM;
    private var bigNumProtomoleculeOutlineThick as Gfx.FontDefinition or Gfx.FontReference or Ui.FontResource = Graphics.FONT_MEDIUM;
    private var width as Lang.Number = 0;
    private var height as Lang.Number = 0;

    // Pre-cached layout positions (computed once in onLayout)
    private var centerX as Lang.Number = 0;

    // Pre-cached graph layout constants (computed once in onLayout)
    private var graphBottom as Lang.Number = 0;
    private var graphHeight as Lang.Number = 0;
    private var reducedWidth as Lang.Number = 0;
    private var stepSize as Lang.Number = 1;
    private var barIntervalMs as Lang.Number = 0;
    private const MAX_DATA_POINTS = 86;
    private const PERIOD_SEC = 6 * 3600;

    // Layout ratios (fraction of screen dimension)
    private const HOUR_Y_RATIO_TOP = 0.20;       // hour when position=top
    private const MINUTE_Y_RATIO_TOP = 0.53;     // minute when position=top
    private const HOUR_Y_RATIO_CENTER = 0.335;   // hour when position=centered (block centered)
    private const MINUTE_Y_RATIO_CENTER = 0.665; // minute when position=centered
    private const SIDEBYSIDE_Y_RATIO_TOP = 0.354;    // single line when position=top (~70px below stacked top)
    private const SIDEBYSIDE_Y_RATIO_CENTER = 0.5;   // single line when position=centered
    // Graph height as percentage of screen height (see getBarsHeightPercent())
    // Removed fixed GRAPH_HEIGHT_RATIO; now driven by BarsHeight setting.
    private const GRAPH_WIDTH_RATIO = 0.97;  // graph width (slight inset from right edge)
    
    // Cache HR graph data - refetch interval based on bar count (period/numBars), only update when new sample arrives
    // Production: values + timestamps (seconds) for fixed-interval time-based sampling. Debug: values only.
    private var cachedHeartRateData as Lang.Array or Null = null;
    private var cachedHeartRateTimes as Lang.Array or Null = null;  // parallel array of epoch seconds; null in debug
    private var cachedFetchEpochSec as Lang.Number = 0;  // Time.now().value() captured at fetch; used by bar builder
    private var cachedDataSampleCount as Lang.Number = 0;
    private var lastFetchTime as Lang.Number = 0;

    //! When true, skip sensor fetch on the next onUpdate to unblock the first wake frame
    private var deferFetch as Lang.Boolean = false;

    // Cached zone-bucketed bar data (flat arrays: every 3 elements = x, y, h). Zone 0..5.
    private var cachedBarVersion as Lang.Number = -1;
    private var cachedZone0Bars as Lang.Array or Null = null;
    private var cachedZone1Bars as Lang.Array or Null = null;
    private var cachedZone2Bars as Lang.Array or Null = null;
    private var cachedZone3Bars as Lang.Array or Null = null;
    private var cachedZone4Bars as Lang.Array or Null = null;
    private var cachedZone5Bars as Lang.Array or Null = null;
    private var cachedAllBars as Lang.Array or Null = null;

    // Custom colors to replace muddy Garmin defaults
    private const COLOR_VIVID_BLUE = 0x0088FF;       // bright azure (replaces dim COLOR_BLUE)
    private const COLOR_DK_VIVID_BLUE = 0x005599;    // darker azure for minutes shade
    private const COLOR_VIVID_ORANGE = 0xFF4400;      // red-orange (replaces muddy COLOR_ORANGE)
    private const COLOR_DK_VIVID_ORANGE = 0xCC3300;
    // Near-black for text outline – dark enough to read as black, but NOT
    // 0x000000 which Garmin treats as transparent in bitmap fonts.
    private const OUTLINE_COLOR = 0x050505;

    // Color schemes: 0=White, 1=Greyscale, 2=Garmin, 3=Viridis, 4=Magma
    // Each scheme: 6 zone colors [fill], 6 darker shades [for minutes]
    private const SCHEME_WHITE = 0;
    private const SCHEME_GREYSCALE = 1;
    private const SCHEME_GARMIN = 2;
    private const SCHEME_VIRIDIS = 3;
    private const SCHEME_MAGMA = 4;

    // Pre-computed zone color lookup tables (initialized once in initialize())
    // Each array has 6 entries: one color per zone index 0..5.
    private var greyscaleFill as Lang.Array = [] as Lang.Array;
    private var greyscaleDark as Lang.Array = [] as Lang.Array;
    private var garminFill as Lang.Array = [] as Lang.Array;
    private var garminDark as Lang.Array = [] as Lang.Array;
    private var viridisFill as Lang.Array = [] as Lang.Array;
    private var viridisDark as Lang.Array = [] as Lang.Array;
    private var magmaFill as Lang.Array = [] as Lang.Array;
    private var magmaDark as Lang.Array = [] as Lang.Array;

    private var hasSensorHistory as Lang.Boolean = false;

    // BufferedBitmap for off-screen graph rendering (single drawBitmap per frame)
    private var graphBitmapRef as Gfx.BufferedBitmapReference or Null = null;   // full view, 7-color palette
    private var graphTop as Lang.Number = 0;           // Y offset where bitmap is blitted
    private var hasBufferedBitmap as Lang.Boolean = false;
    private var graphBitmapVersion as Lang.Number = -1; // tracks which bar data version the full bitmap contains
    private var lastRenderedBarsScheme as Lang.Number = -1; // re-render bitmap when scheme changes
    private var lastRenderedBarsGap as Lang.Number = -1;   // re-render bitmap when gap setting changes
    private var lastComputedHeightPct as Lang.Number = -1; // track BarsHeight setting changes

    //! True when in low-power / Always On Display mode (after onEnterSleep)
    private var isLowPower as Lang.Boolean = false;

    // Cached user settings – loaded once in initialize() and refreshed in loadSettings().
    // Eliminates 9+ App.Properties.getValue() calls per frame.
    private var settingFontColorScheme as Lang.Number = SCHEME_GARMIN;
    private var settingBarsColorScheme as Lang.Number = SCHEME_GARMIN;
    private var settingBarsPosition as Lang.Number = 0;
    private var settingBarsGap as Lang.Number = 1;
    private var settingTimePosition as Lang.Number = 1;
    private var settingTimeLayout as Lang.Number = 1;
    private var settingMinutesColorMode as Lang.Number = 0;
    private var settingBarsHeightPercent as Lang.Number = 68;
    private var settingFontSize as Lang.Number = 1;  // 0=Small, 1=Default, 2=Large, 3=Extra Large
    private var cachedIs24Hour as Lang.Boolean = true;  // from System.getDeviceSettings(); refreshed in loadSettings()/onExitSleep()

    //! Cached setting accessors (no property reads – values are pre-loaded).
    private function getFontColorScheme() as Lang.Number { return settingFontColorScheme; }
    private function getBarsColorScheme() as Lang.Number { return settingBarsColorScheme; }
    //! 0 = bars behind font, 1 = bars in front of font
    private function getBarsPosition() as Lang.Number { return settingBarsPosition; }
    //! 0 = no gaps (bars touch), 1 = default gaps (current)
    private function getBarsGap() as Lang.Number { return settingBarsGap; }
    //! 0 = top, 1 = centered
    private function getTimePosition() as Lang.Number { return settingTimePosition; }
    //! 0 = stacked (hour above minute), 1 = side by side
    private function getTimeLayout() as Lang.Number { return settingTimeLayout; }
    //! 0 = minutes darker shade, 1 = minutes match hours
    private function getMinutesColorMode() as Lang.Number { return settingMinutesColorMode; }
    //! Bar height as percentage of screen height (already mapped from setting key)
    private function getBarsHeightPercent() as Lang.Number { return settingBarsHeightPercent; }
    //! 0=Small, 1=Default, 2=Large, 3=Extra Large
    private function getFontSize() as Lang.Number { return settingFontSize; }
    //! Bar width: stepSize when no gaps (bars touch), 2 when default gaps
    private function getBarWidth() as Lang.Number {
        return (settingBarsGap == 0) ? stepSize : 2;
    }

    //! Read all user-facing settings from App.Properties and cache them.
    //! Called once at startup and again whenever onSettingsChanged() fires.
    function loadSettings() as Void {
        settingFontColorScheme = readNumericSetting("FontColorScheme", 0, 4, SCHEME_GARMIN);
        settingBarsColorScheme = readNumericSetting("BarsColorScheme", 0, 4, SCHEME_GARMIN);
        settingBarsPosition = readNumericSetting("BarsPosition", 0, 1, 0);
        settingBarsGap = readNumericSetting("BarsGap", 0, 1, 1);
        settingTimePosition = readNumericSetting("TimePosition", 0, 1, 1);
        settingTimeLayout = readNumericSetting("TimeLayout", 0, 1, 1);
        settingMinutesColorMode = readNumericSetting("MinutesColorMode", 0, 1, 0);
        // BarsHeight: map setting key (0..4) to percentage
        var bh = readNumericSetting("BarsHeight", 0, 4, 1);
        if (bh == 0) { settingBarsHeightPercent = 50; }
        else if (bh == 2) { settingBarsHeightPercent = 80; }
        else if (bh == 3) { settingBarsHeightPercent = 90; }
        else if (bh == 4) { settingBarsHeightPercent = 100; }
        else { settingBarsHeightPercent = 68; }
        settingFontSize = readNumericSetting("FontSize", 0, 3, 1);
        // Cache device-level is24Hour (avoids allocating DeviceSettings every frame)
        cachedIs24Hour = System.getDeviceSettings().is24Hour;
        // Reload fonts when FontSize setting changes
        loadFontsForCurrentSize();
    }

    //! Load fill and outline fonts for the current FontSize setting (0=Small, 1=Default, 2=Large, 3=XL).
    private function loadFontsForCurrentSize() as Void {
        var sz = settingFontSize;
        var fillRes = (sz == 0) ? Rez.Fonts.protomoleculefont_s :
                     (sz == 2) ? Rez.Fonts.protomoleculefont_l :
                     (sz == 3) ? Rez.Fonts.protomoleculefont_xl :
                     Rez.Fonts.protomoleculefont;
        var outRes = (sz == 0) ? Rez.Fonts.protomoleculefontoutline_s :
                     (sz == 2) ? Rez.Fonts.protomoleculefontoutline_l :
                     (sz == 3) ? Rez.Fonts.protomoleculefontoutline_xl :
                     Rez.Fonts.protomoleculefontoutline;
        var outThickRes = (sz == 0) ? Rez.Fonts.protomoleculefontoutlinethick_s :
                         (sz == 2) ? Rez.Fonts.protomoleculefontoutlinethick_l :
                         (sz == 3) ? Rez.Fonts.protomoleculefontoutlinethick_xl :
                         Rez.Fonts.protomoleculefontoutlinethick;
        var loadedFont = Ui.loadResource(fillRes);
        if (loadedFont != null) {
            bigNumProtomolecule = loadedFont as Gfx.FontReference;
        }
        var loadedOutline = Ui.loadResource(outRes);
        if (loadedOutline != null) {
            bigNumProtomoleculeOutline = loadedOutline as Gfx.FontReference;
        }
        var loadedOutlineThick = Ui.loadResource(outThickRes);
        if (loadedOutlineThick != null) {
            bigNumProtomoleculeOutlineThick = loadedOutlineThick as Gfx.FontReference;
        }
    }

    //! Read a numeric setting with range validation and fallback default.
    private function readNumericSetting(key as Lang.String, min as Lang.Number, max as Lang.Number, fallback as Lang.Number) as Lang.Number {
        try {
            var v = App.Properties.getValue(key);
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n >= min && n <= max) { return n; }
            }
        } catch (e) { }
        return fallback;
    }

    // Cached formatted time strings – only reformat when minute/hour actually changes
    private var cachedHourStr as Lang.String = "";
    private var cachedMinStr as Lang.String = "";
    private var lastCachedHour as Lang.Number = -1;
    private var lastCachedMin as Lang.Number = -1;
    private var lastIs24Hour as Lang.Boolean = true;


    //! Build age-estimated HR zones when UserProfile.getHeartRateZones returns null.
    //! Uses 220 - age for max HR; zone boundaries at 50%, 60%, 70%, 80%, 90%, 100%.
    private function getDefaultHeartRateZones() as Lang.Array {
        var maxHr = 190;  // safe default when age unknown
        var profile = Up.getProfile();
        if (profile != null && profile.birthYear != null) {
            var now = Time.now();
            if (now != null) {
                var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
                var currYear = info.year;
                if (currYear != null) {
                    var by = profile.birthYear as Lang.Number;
                    var age = currYear - by;
                    if (age > 0 && age < 120) {
                        maxHr = 220 - age;
                        if (maxHr < 100) { maxHr = 100; }
                        if (maxHr > 220) { maxHr = 220; }
                    }
                }
            }
        }
        // Zone boundaries: min zone 1, max 1..5 (% of max HR)
        return [
            maxHr * 50 / 100,
            maxHr * 60 / 100,
            maxHr * 70 / 100,
            maxHr * 80 / 100,
            maxHr * 90 / 100,
            maxHr
        ];
    }

    //! Get zone index 0..5 from HR value
    private function getZoneIndex(inheartRate as Lang.Number, inheartRateZones as Lang.Array) as Lang.Number {
        if (inheartRate < inheartRateZones[0]) { return 0; }
        if (inheartRate <= inheartRateZones[1]) { return 1; }
        if (inheartRate <= inheartRateZones[2]) { return 2; }
        if (inheartRate <= inheartRateZones[3]) { return 3; }
        if (inheartRate <= inheartRateZones[4]) { return 4; }
        return 5;
    }

    //! Get fill color for a zone in the given scheme (0=White, 1=Greyscale, 2=Garmin, 3=Viridis, 4=Magma).
    //! Color lookup tables are pre-computed as class-level arrays (see initialize()) to avoid
    //! allocating throwaway arrays on every call — this function is called 8+ times per frame.
    private function getColorForZone(schemeId as Lang.Number, zoneIndex as Lang.Number, forMinutes as Lang.Boolean) as Lang.Number {
        if (schemeId == SCHEME_WHITE) {
            return forMinutes ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_WHITE;
        }
        if (schemeId == SCHEME_GREYSCALE) {
            return forMinutes ? greyscaleDark[zoneIndex] : greyscaleFill[zoneIndex];
        }
        if (schemeId == SCHEME_GARMIN) {
            return forMinutes ? garminDark[zoneIndex] : garminFill[zoneIndex];
        }
        if (schemeId == SCHEME_VIRIDIS) {
            return forMinutes ? viridisDark[zoneIndex] : viridisFill[zoneIndex];
        }
        if (schemeId == SCHEME_MAGMA) {
            return forMinutes ? magmaDark[zoneIndex] : magmaFill[zoneIndex];
        }
        return Graphics.COLOR_WHITE;
    }

    //! Get current HR for time coloring. Production: ActivityMonitor or cached graph data.
    (:production)
    private function getCurrentHeartRateForDisplay() as Lang.Number or Null {
        if (Toybox has :ActivityMonitor && Toybox.ActivityMonitor has :getHeartRateHistory) {
            var iter = Act.getHeartRateHistory(1, true);  // 1 sample, newest first
            var sample = iter.next();
            if (sample != null && sample.heartRate != null && sample.heartRate != Act.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        // Fallback: use latest sample from cached graph data
        if (cachedHeartRateData == null) {
            return null;
        }
        var arr = cachedHeartRateData as Lang.Array;
        if (arr.size() > 0) {
            return arr[arr.size() - 1] as Lang.Number or Null;
        }
        return null;
    }

    //! Debug: cycle through random HR values every few seconds to exercise the color logic
    (:debugHrData)
    private function getCurrentHeartRateForDisplay() as Lang.Number or Null {
        var zones = heartRateZones;
        if (zones == null || zones.size() < 6) { return null; }
        var z0 = zones[0] as Lang.Number;
        var z5 = zones[5] as Lang.Number;
        var range = z5 - z0;
        if (range <= 0) { return z0; }
        // New value every 4 seconds – deterministic “random” across full zone range
        var ct = System.getClockTime();
        var slot = ct.hour * 900 + ct.min * 15 + ct.sec / 4;
        var h = ((slot & 0xFFFF) * 31421 + 6927) & 0xFFFF;
        var pct = h % 101;  // 0..100
        var hr = z0 + (range * pct / 100);
        if (hr < z0) { hr = z0; }
        if (hr > z5) { hr = z5; }
        return hr;
    }

    (:typecheck(false))
    function initialize() {
        WatchFace.initialize();

        // Load settings first (needed for font size selection)
        loadSettings();

        // Determine and store HR zones; fallback to age-estimated if profile not configured
        var profileZones = UserProfile.getHeartRateZones(Up.HR_ZONE_SPORT_GENERIC);
        if (profileZones != null && profileZones.size() > 5) {
            heartRateZones = profileZones;
        } else {
            heartRateZones = getDefaultHeartRateZones();
        }
        
        // Pre-compute zone color lookup tables (allocated once, reused every frame)
        greyscaleFill = [Graphics.COLOR_WHITE, Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY,
                         0x555555, 0x444444, 0x333333];
        greyscaleDark = [Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY, 0x444444,
                         0x333333, 0x222222, 0x111111];
        garminFill = [Graphics.COLOR_WHITE, Graphics.COLOR_LT_GRAY, COLOR_VIVID_BLUE,
                      Graphics.COLOR_GREEN, COLOR_VIVID_ORANGE, Graphics.COLOR_RED];
        garminDark = [Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY, COLOR_DK_VIVID_BLUE,
                      Graphics.COLOR_DK_GREEN, COLOR_DK_VIVID_ORANGE, Graphics.COLOR_DK_RED];
        viridisFill = [0x440154, 0x3b528b, 0x21908c, 0x5ec962, 0xb4de2c, 0xfde725];
        viridisDark = [0x2d0e3a, 0x28395e, 0x166161, 0x3e9a47, 0x8bb820, 0xc7b81c];
        magmaFill = [0x180f3e, 0x51127c, 0xb73779, 0xf89662, 0xfcfdbf, 0xfffef0];
        magmaDark = [0x0f0a26, 0x350b53, 0x7a2553, 0xcb6a43, 0xd4d5a8, 0xe8e8d0];

        // Cache capability check (avoids repeated "has" checks in onUpdate)
        hasSensorHistory = (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getHeartRateHistory);
    }

    // Load your resources here
    function onLayout(dc as Gfx.Dc) as Void {
        width = dc.getWidth();
        height = dc.getHeight();
        centerX = width / 2;

        // Pre-compute graph layout constants
        graphBottom = height;
        var heightPct = getBarsHeightPercent();
        graphHeight = height * heightPct / 100;
        lastComputedHeightPct = heightPct;
        reducedWidth = (width * GRAPH_WIDTH_RATIO).toNumber() + 36;
        stepSize = (reducedWidth / MAX_DATA_POINTS).toNumber();
        if (stepSize < 1) { stepSize = 1; }
        barIntervalMs = (PERIOD_SEC * 1000 / MAX_DATA_POINTS).toNumber();

        // Compute top Y of graph area
        graphTop = graphBottom - graphHeight;

        // Create off-screen BufferedBitmap for graph rendering (if supported).
        // Use native color depth with full alpha blending instead of a palette.
        // Palette-based bitmaps with COLOR_TRANSPARENT render correctly on the
        // emulator but display the transparent pixels as a visible color on
        // real hardware.  Full alpha blending is reliable on both.
        // Bitmap is full screen height so dynamic BarsHeight changes don't
        // require bitmap recreation; unused area stays transparent.
        if (Toybox.Graphics has :createBufferedBitmap) {
            graphBitmapRef = Graphics.createBufferedBitmap({
                :width => reducedWidth,
                :height => height,
                :alphaBlending => Graphics.ALPHA_BLENDING_FULL
            });
            hasBufferedBitmap = true;
        } else {
            graphBitmapRef = null;
            hasBufferedBitmap = false;
        }

        // Invalidate bar cache and bitmap version on layout change
        cachedBarVersion = -1;
        graphBitmapVersion = -1;
     }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view (typecheck disabled – getCurrentHeartRateForDisplay has (:production)/(:debugHrData) variants)
    (:typecheck(false))
    function onUpdate(dc as Gfx.Dc) as Void {
        // Clear the DC
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        var showClockTime = System.getClockTime();

        // Cache formatted time strings – format() is expensive (triggers
        // String.length & Float.toNumber internally).  Hour changes once/hr,
        // minute once/min, so almost every frame reuses the cached string.
        var hour = showClockTime.hour;
        var min  = showClockTime.min;
        var is24Hour = cachedIs24Hour;
        var lastHour = lastCachedHour;
        var lastMin = lastCachedMin;
        var lastIs24 = lastIs24Hour;
        if (hour != lastHour || is24Hour != lastIs24) {
            if (is24Hour) {
                cachedHourStr = hour.format("%02d");
            } else {
                // 12-hour conversion: 0 becomes 12, 13-23 become 1-11; zero-pad to 02d
                var displayHour = hour % 12;
                if (displayHour == 0) {
                    displayHour = 12;
                }
                cachedHourStr = displayHour.format("%02d");
            }
            lastCachedHour = hour;
            lastIs24Hour = is24Hour;
        }
        if (min != lastMin) {
            cachedMinStr  = min.format("%02d");
            lastCachedHour = hour;
            lastCachedMin = min;
            lastIs24Hour = is24Hour;
        }

        // Time colors based on current HR (same zone scale as graph); minutes per MinutesColorMode
        // NOTE: cachedHeartRateData may be stale (populated by drawHeartRateGraph on the
        // previous frame).  Production uses sensor/cache; debug uses synthetic via getCurrentHeartRateDebug.
        var currentHr = getCurrentHeartRateForDisplay();
        var fontScheme = getFontColorScheme();
        var hourColor = Graphics.COLOR_WHITE;
        var minColor = Graphics.COLOR_LT_GRAY;
        if (currentHr != null && heartRateZones != null && heartRateZones.size() > 5) {
            var zoneIdx = getZoneIndex(currentHr, heartRateZones);
            hourColor = getColorForZone(fontScheme, zoneIdx, false);
            minColor = (settingMinutesColorMode == 1) ? hourColor : getColorForZone(fontScheme, zoneIdx, true);
        }

        // Compute time positions from TimePosition and TimeLayout
        var timePos = getTimePosition();
        var timeLayout = getTimeLayout();
        var textYHH = 0;
        var textYMM = 0;
        var textYSide = 0;
        if (timeLayout == 1) {
            textYSide = (timePos == 1) ? (height * SIDEBYSIDE_Y_RATIO_CENTER).toNumber() : (height * SIDEBYSIDE_Y_RATIO_TOP).toNumber();
        } else {
            if (timePos == 1) {
                textYHH = (height * HOUR_Y_RATIO_CENTER).toNumber();
                textYMM = (height * MINUTE_Y_RATIO_CENTER).toNumber();
            } else {
                textYHH = (height * HOUR_Y_RATIO_TOP).toNumber();
                textYMM = (height * MINUTE_Y_RATIO_TOP).toNumber();
            }
        }

        // Draw order depends on BarsPosition setting:
        //   "Time on Top":  graph → outline → fill  (time fully on top)
        //   "Bars on Top":  outline → fill → graph  (bars fully on top)
        var hourStr = cachedHourStr;
        var minStr = cachedMinStr;
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var justRight = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
        var justLeft = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var hasGraph = (heartRateZones != null && heartRateZones.size() > 5);
        var barsInFront = (getBarsPosition() == 1);

        // 1. Graph first when "Time on Top"
        if (hasGraph && !barsInFront) {
            drawHeartRateGraph(dc, isLowPower);
        }

        // 2. Draw outline (border) - always behind fill
        var outFont = isLowPower ? bigNumProtomoleculeOutline : bigNumProtomoleculeOutlineThick;
        var outColor = isLowPower ? Graphics.COLOR_DK_GRAY : OUTLINE_COLOR;
        dc.setColor(outColor, Graphics.COLOR_TRANSPARENT);
        if (timeLayout == 1) {
            dc.drawText(centerX - 2, textYSide, outFont, hourStr, justRight);
            dc.drawText(centerX + 2, textYSide, outFont, minStr, justLeft);
        } else {
            dc.drawText(centerX, textYHH, outFont, hourStr, just);
            dc.drawText(centerX, textYMM, outFont, minStr, just);
        }

        // 3. Draw fill
        if (isLowPower) {
            dc.setColor(OUTLINE_COLOR, Graphics.COLOR_TRANSPARENT);
            if (timeLayout == 1) {
                dc.drawText(centerX - 2, textYSide, bigNumProtomolecule, hourStr, justRight);
                dc.drawText(centerX + 2, textYSide, bigNumProtomolecule, minStr, justLeft);
            } else {
                dc.drawText(centerX, textYHH, bigNumProtomolecule, hourStr, just);
                dc.drawText(centerX, textYMM, bigNumProtomolecule, minStr, just);
            }
        } else {
            if (timeLayout == 1) {
                dc.setColor(hourColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX - 2, textYSide, bigNumProtomolecule, hourStr, justRight);
                dc.setColor(minColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX + 2, textYSide, bigNumProtomolecule, minStr, justLeft);
            } else {
                dc.setColor(hourColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, textYHH, bigNumProtomolecule, hourStr, just);
                dc.setColor(minColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(centerX, textYMM, bigNumProtomolecule, minStr, just);
            }
        }

        // 4. Graph last when "Bars on Top" - completely on top of time
        if (hasGraph && barsInFront) {
            drawHeartRateGraph(dc, isLowPower);
        }

}

    //! Ensures cachedHeartRateData and bar caches are populated. Production: sensor fetch only.
    (:production)
    private function ensureHeartRateDataCached() as Lang.Boolean {
        doProductionFetch();
        return ensureHeartRateDataCachedCore();
    }

    //! Ensures cachedHeartRateData and bar caches are populated. Debug: synthetic HR data.
    (:debugHrData)
    private function ensureHeartRateDataCached() as Lang.Boolean {
        var debugData = generateDebugHrData();
        if (debugData.size() > 0) {
            cachedHeartRateData = debugData;
            cachedHeartRateTimes = null;  // debug uses index-based sampling
            cachedDataSampleCount = cachedDataSampleCount + 1;
        }
        return ensureHeartRateDataCachedCore();
    }

    //! Production path: throttled sensor fetch. Returns true if fetch was attempted.
    (:production)
    private function doProductionFetch() as Lang.Boolean {
        var now = System.getTimer();
        var shouldAttemptFetch = (cachedHeartRateData == null) || (now - lastFetchTime >= barIntervalMs);
        if (!shouldAttemptFetch || !hasSensorHistory) {
            return false;
        }
        if (deferFetch && cachedHeartRateData != null) {
            deferFetch = false;
            Ui.requestUpdate();
            return false;
        }
        deferFetch = false;
        try {
            var sensorIter = Toybox.SensorHistory.getHeartRateHistory({:period => PERIOD_SEC, :order => SensorHistory.ORDER_OLDEST_FIRST});
            var newData = [];
            var newTimes = [];
            var sample = sensorIter.next();
            while (sample != null) {
                if (sample.data != null && sample.when != null) {
                    newData.add(sample.data);
                    newTimes.add((sample.when as Time.Moment).value());
                }
                sample = sensorIter.next();
            }
            lastFetchTime = now;
            var newSize = newData.size();
            if (newSize > 0) {
                cachedHeartRateData = newData;
                cachedHeartRateTimes = newTimes;
                cachedFetchEpochSec = Time.now().value();
                cachedDataSampleCount = cachedDataSampleCount + 1;
            }
        } catch (ex) {
            lastFetchTime = now;
        }
        return true;
    }

    //! Shared cache validation and bar rebuild logic (no debug-only symbol references).
    private function ensureHeartRateDataCachedCore() as Lang.Boolean {
        var zones = heartRateZones;
        if (zones == null || zones.size() < 6) {
            return false;
        }
        if (cachedHeartRateData == null) {
            return false;
        }
        var data = cachedHeartRateData as Lang.Array;
        var dataSize = data.size();
        if (dataSize == 0) {
            return false;
        }

        // Check if BarsHeight setting changed; recompute graph layout if so
        var heightPct = getBarsHeightPercent();
        if (heightPct != lastComputedHeightPct) {
            graphHeight = height * heightPct / 100;
            graphTop = graphBottom - graphHeight;
            lastComputedHeightPct = heightPct;
            cachedBarVersion = -1;       // force bar rebuild
            graphBitmapVersion = -1;     // force bitmap re-render
        }
        
        // Recompute bar cache only when HR data has changed (or after layout invalidation)
        if (cachedBarVersion != cachedDataSampleCount) {
            var zone0Bars = [];
            var zone1Bars = [];
            var zone2Bars = [];
            var zone3Bars = [];
            var zone4Bars = [];
            var zone5Bars = [];
            var allBars = [];
            
            var zones5 = zones[5] as Lang.Number;
            if (zones5 <= 0) { zones5 = 200; } // guard against corrupted profile
            var slotDurationSec = PERIOD_SEC / MAX_DATA_POINTS;
            var times = cachedHeartRateTimes;
            var useTimeBased = (times != null && times.size() == dataSize);

            // Build per-slot HR values: time-based (production) or index-based (debug)
            if (useTimeBased && dataSize > 0) {
                // Use epoch time captured at fetch so slots align with stored timestamps
                var periodStartSec = cachedFetchEpochSec - PERIOD_SEC;
                var slotValues = new [MAX_DATA_POINTS];
                var slotDist = new [MAX_DATA_POINTS];
                for (var i = 0; i < MAX_DATA_POINTS; i++) {
                    slotValues[i] = null;
                    slotDist[i] = slotDurationSec;
                }
                // O(N) single pass: assign each sample to its time slot
                for (var j = 0; j < dataSize; j++) {
                    var sampleSec = (times[j]) as Lang.Number;
                    var offsetSec = sampleSec - periodStartSec;
                    if (offsetSec < 0) { continue; }
                    var slotIdx = offsetSec / slotDurationSec;
                    if (slotIdx >= MAX_DATA_POINTS) { continue; }
                    var slotCenterSec = periodStartSec + slotIdx * slotDurationSec + slotDurationSec / 2;
                    var d = sampleSec - slotCenterSec;
                    var dist = (d > 0) ? d : (-d);
                    if (dist < (slotDist[slotIdx] as Lang.Number)) {
                        slotDist[slotIdx] = dist;
                        slotValues[slotIdx] = data[j] as Lang.Number or Null;
                    }
                }
                // Build bar arrays from slot values; empty slots are simply skipped (black = background)
                for (var slotIdx = 0; slotIdx < MAX_DATA_POINTS; slotIdx++) {
                    var heartRate = slotValues[slotIdx];
                    if (heartRate == null) { continue; }
                    var x = slotIdx * stepSize;
                    var y = (graphBottom - (heartRate * graphHeight / zones5)).toNumber();
                    var barH = graphBottom - y;
                    if (barH <= 0) { continue; }
                    allBars.add(x); allBars.add(y); allBars.add(barH);
                    var z = getZoneIndex(heartRate, zones);
                    if (z == 0) { zone0Bars.add(x); zone0Bars.add(y); zone0Bars.add(barH); }
                    else if (z == 1) { zone1Bars.add(x); zone1Bars.add(y); zone1Bars.add(barH); }
                    else if (z == 2) { zone2Bars.add(x); zone2Bars.add(y); zone2Bars.add(barH); }
                    else if (z == 3) { zone3Bars.add(x); zone3Bars.add(y); zone3Bars.add(barH); }
                    else if (z == 4) { zone4Bars.add(x); zone4Bars.add(y); zone4Bars.add(barH); }
                    else { zone5Bars.add(x); zone5Bars.add(y); zone5Bars.add(barH); }
                }
            } else {
                // Debug / fallback: index-based proportional sampling (no timestamps)
                var lastIdx = dataSize - 1;
                for (var i = 0; i < MAX_DATA_POINTS; i++) {
                    var sampleIndex = i * dataSize / MAX_DATA_POINTS;
                    if (sampleIndex > lastIdx) { sampleIndex = lastIdx; }
                    var heartRate = data[sampleIndex] as Lang.Number or Null;
                    if (heartRate == null) { continue; }
                    var x = i * stepSize;
                    var y = (graphBottom - (heartRate * graphHeight / zones5)).toNumber();
                    var barH = graphBottom - y;
                    if (barH <= 0) { continue; }
                    allBars.add(x); allBars.add(y); allBars.add(barH);
                    var z = getZoneIndex(heartRate, zones);
                    if (z == 0) { zone0Bars.add(x); zone0Bars.add(y); zone0Bars.add(barH); }
                    else if (z == 1) { zone1Bars.add(x); zone1Bars.add(y); zone1Bars.add(barH); }
                    else if (z == 2) { zone2Bars.add(x); zone2Bars.add(y); zone2Bars.add(barH); }
                    else if (z == 3) { zone3Bars.add(x); zone3Bars.add(y); zone3Bars.add(barH); }
                    else if (z == 4) { zone4Bars.add(x); zone4Bars.add(y); zone4Bars.add(barH); }
                    else { zone5Bars.add(x); zone5Bars.add(y); zone5Bars.add(barH); }
                }
            }
            
            cachedZone0Bars = zone0Bars;
            cachedZone1Bars = zone1Bars;
            cachedZone2Bars = zone2Bars;
            cachedZone3Bars = zone3Bars;
            cachedZone4Bars = zone4Bars;
            cachedZone5Bars = zone5Bars;
            cachedAllBars = allBars;
            cachedBarVersion = cachedDataSampleCount;
        }
        
        return true;
    }

    private function drawHeartRateGraph(dc as Gfx.Dc, useOutline as Lang.Boolean) as Void {
        if (!ensureHeartRateDataCached()) {
            return;
        }

        // Draw bars – prefer single drawBitmap blit; fall back to per-bar loops
        if (useOutline) {
            // Low-power / Always On: draw outlined rectangles directly on the DC.
            // No-data slots are simply absent (black background = implicit gap).
            var bars = cachedAllBars;
            if (bars != null && bars.size() > 0) {
                dc.setPenWidth(1);
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
                var sz = bars.size();
                var barW = getBarWidth();
                for (var i = 0; i < sz; i += 3) {
                    dc.drawRectangle(bars[i] as Lang.Number, bars[i + 1] as Lang.Number, barW, bars[i + 2] as Lang.Number);
                }
            }
        } else {
            var bitmapDrawn = false;
            if (hasBufferedBitmap && graphBitmapRef != null) {
                var gBitmap = graphBitmapRef.get();
                if (gBitmap != null) {
                    var barsScheme = getBarsColorScheme();
                    // Re-render to bitmap if bar data changed, scheme changed, gap changed, or bitmap was evicted
                    var barsGap = getBarsGap();
                    if (graphBitmapVersion != cachedBarVersion || lastRenderedBarsScheme != barsScheme || lastRenderedBarsGap != barsGap || !(gBitmap as Gfx.BufferedBitmap).isCached()) {
                        drawBarsToBitmap(gBitmap as Gfx.BufferedBitmap, barsScheme);
                        lastRenderedBarsScheme = barsScheme;
                        lastRenderedBarsGap = barsGap;
                    }
                    dc.drawBitmap(0, 0, gBitmap as Gfx.BufferedBitmap);
                    bitmapDrawn = true;
                }
            }
            if (!bitmapDrawn) {
                // Fallback: per-bar fillRectangle loops (setPenWidth not needed for fillRectangle)
                drawAllBarBuckets(dc, Graphics.COLOR_BLACK, 0, getBarsColorScheme(), getBarWidth());
            }
        }
    }

    //! Draw a bucket of bars with a single color (flat array: every 3 elements = x, y, h).
    //! bgColor sets the DC background; yOffset shifts each bar's Y (used for bitmap-local coords).
    //! barWidth: 2 for default gaps, stepSize for no gaps.
    private function drawBarBucket(dc as Gfx.Dc, bars as Lang.Array or Null, color as Lang.Number, bgColor as Lang.Number, yOffset as Lang.Number, barWidth as Lang.Number) as Void {
        if (bars == null || bars.size() == 0) {
            return;
        }
        dc.setColor(color, bgColor);
        var sz = bars.size();  // cache size – avoid repeated method call
        for (var i = 0; i < sz; i += 3) {
            // barH > 0 guaranteed by cache builder
            dc.fillRectangle(bars[i] as Lang.Number, (bars[i + 1] as Lang.Number) - yOffset, barWidth, bars[i + 2] as Lang.Number);
        }
    }

    //! Draw all six zone buckets onto a DC using the given color scheme.
    //! No-data slots are absent; black background serves as implicit gap.
    private function drawAllBarBuckets(dc as Gfx.Dc, bgColor as Lang.Number, yOffset as Lang.Number, barsScheme as Lang.Number, barWidth as Lang.Number) as Void {
        drawBarBucket(dc, cachedZone0Bars, getColorForZone(barsScheme, 0, false), bgColor, yOffset, barWidth);
        drawBarBucket(dc, cachedZone1Bars, getColorForZone(barsScheme, 1, false), bgColor, yOffset, barWidth);
        drawBarBucket(dc, cachedZone2Bars, getColorForZone(barsScheme, 2, false), bgColor, yOffset, barWidth);
        drawBarBucket(dc, cachedZone3Bars, getColorForZone(barsScheme, 3, false), bgColor, yOffset, barWidth);
        drawBarBucket(dc, cachedZone4Bars, getColorForZone(barsScheme, 4, false), bgColor, yOffset, barWidth);
        drawBarBucket(dc, cachedZone5Bars, getColorForZone(barsScheme, 5, false), bgColor, yOffset, barWidth);
    }

    //! Render filled HR bars into the off-screen full-view bitmap using bars color scheme.
    //! Bitmap is full screen height so bar coordinates map 1:1 (no y translation needed).
    //! Caller passes the resolved BufferedBitmap to avoid redundant weak-reference lookups.
    private function drawBarsToBitmap(bitmap as Gfx.BufferedBitmap, barsScheme as Lang.Number) as Void {
        var bdc = bitmap.getDc();
        // Clear to transparent
        bdc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        bdc.clear();
        // Draw each zone bucket with scheme colors (bitmap is full-screen, no y offset needed)
        drawAllBarBuckets(bdc, Graphics.COLOR_TRANSPARENT, 0, barsScheme, getBarWidth());
        graphBitmapVersion = cachedBarVersion;
    }


    //! Generate time-varying synthetic HR data that scrolls with the clock.
    //! Uses overlapping triangle waves + pseudo-random jitter to produce
    //! realistic-looking patterns that cover all HR zones (including zone 0 = below z0).
    //! Extends range below z0 to model resting/sleep HR (typically 40–70 bpm).
    //! Included only in debug builds (excluded by :debugHrData annotation in production).
    (:debugHrData)
    private function generateDebugHrData() as Lang.Array {
        var zones = heartRateZones;
        if (zones == null || zones.size() < 6) { return []; }
        var z0 = zones[0] as Lang.Number;
        var z5 = zones[5] as Lang.Number;
        var minHr = z0 - 55;  // extend below z0 for resting/sleep (zone 0)
        if (minHr < 40) { minHr = 40; }
        var range = z5 - minHr;

        var ct = System.getClockTime();
        var minuteNow = ct.hour * 60 + ct.min;
        // Each bar spans ~5 minutes (360 min / MAX_DATA_POINTS)
        var barSpan = 360 / MAX_DATA_POINTS;

        var data = new [MAX_DATA_POINTS];
        for (var i = 0; i < MAX_DATA_POINTS; i++) {
            // Absolute minute this bar represents (oldest on the left)
            var t = minuteNow - (MAX_DATA_POINTS - 1 - i) * barSpan;

            // --- Slow triangle wave (period ~127 min ≈ 2 hr) ---
            // Drives broad activity blocks (rest ↔ exercise)
            var sp = t % 127;
            if (sp < 0) { sp = sp + 127; }
            var slow = (sp < 64) ? (sp * 100 / 63) : ((127 - sp) * 100 / 63);

            // --- Medium triangle wave (period ~41 min) ---
            // Adds interval-style variation within an activity block
            var mp = t % 41;
            if (mp < 0) { mp = mp + 41; }
            var med = (mp < 21) ? (mp * 100 / 20) : ((41 - mp) * 100 / 20);

            // --- Pseudo-random jitter (deterministic from bar minute) ---
            var h = ((t & 0xFFFF) * 31421 + 6927) & 0xFFFF;
            var noise = (h % 20) - 10;  // -10 .. +9

            // Weighted blend: 50% slow + 30% medium + 20% (centered noise)
            var pct = (slow * 5 + med * 3 + (50 + noise) * 2) / 10;
            if (pct < 0) { pct = 0; }
            if (pct > 100) { pct = 100; }

            var hr = minHr + range * pct / 100;
            if (hr < minHr) { hr = minHr; }
            if (hr > z5) { hr = z5; }
            data[i] = hr;
        }
        return data;
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() as Void {
        isLowPower = false;
        deferFetch = true;  // draw first wake frame with stale cache, fetch on next update
        cachedIs24Hour = System.getDeviceSettings().is24Hour;  // refresh on wake
    }

    // Terminate any active timers and prepare for slow updates.
    // AMOLED: draw <10% pixels in onUpdate or display will turn off.
    function onEnterSleep() as Void {
        isLowPower = true;
    }
}
