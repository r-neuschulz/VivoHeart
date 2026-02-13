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
    private const MAX_DATA_POINTS = 77;
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
    private var cachedHeartRateData as Lang.Array or Null = null;
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

    //! Read color scheme from properties (0..4). Default SCHEME_GARMIN if unavailable.
    private function getFontColorScheme() as Lang.Number {
        try {
            var v = App.Properties.getValue("FontColorScheme");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n >= 0 && n <= 4) { return n; }
            }
        } catch (e) { }
        return SCHEME_GARMIN;
    }
    private function getBarsColorScheme() as Lang.Number {
        try {
            var v = App.Properties.getValue("BarsColorScheme");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n >= 0 && n <= 4) { return n; }
            }
        } catch (e) { }
        return SCHEME_GARMIN;
    }
    //! 0 = bars behind font, 1 = bars in front of font
    private function getBarsPosition() as Lang.Number {
        try {
            var v = App.Properties.getValue("BarsPosition");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n == 0 || n == 1) { return n; }
            }
        } catch (e) { }
        return 0;
    }
    //! 0 = no gaps (bars touch), 1 = default gaps (current)
    private function getBarsGap() as Lang.Number {
        try {
            var v = App.Properties.getValue("BarsGap");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n == 0 || n == 1) { return n; }
            }
        } catch (e) { }
        return 1;
    }
    //! 0 = top, 1 = centered
    private function getTimePosition() as Lang.Number {
        try {
            var v = App.Properties.getValue("TimePosition");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n == 0 || n == 1) { return n; }
            }
        } catch (e) { }
        return 1;
    }
    //! 0 = stacked (hour above minute), 1 = side by side
    private function getTimeLayout() as Lang.Number {
        try {
            var v = App.Properties.getValue("TimeLayout");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n == 0 || n == 1) { return n; }
            }
        } catch (e) { }
        return 1;
    }
    //! 0 = minutes darker shade, 1 = minutes match hours
    private function getMinutesColorMode() as Lang.Number {
        try {
            var v = App.Properties.getValue("MinutesColorMode");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n == 0 || n == 1) { return n; }
            }
        } catch (e) { }
        return 0;
    }
    //! Bar height as percentage of screen height: 0=50%, 1=68% (default), 2=80%, 3=90%, 4=100%
    private function getBarsHeightPercent() as Lang.Number {
        try {
            var v = App.Properties.getValue("BarsHeight");
            if (v != null && v instanceof Lang.Number) {
                var n = v as Lang.Number;
                if (n == 0) { return 50; }
                if (n == 2) { return 80; }
                if (n == 3) { return 90; }
                if (n == 4) { return 100; }
            }
        } catch (e) { }
        return 68;  // default (setting value 1)
    }
    //! Bar width: stepSize when no gaps (bars touch), 2 when default gaps
    private function getBarWidth() as Lang.Number {
        return (getBarsGap() == 0) ? stepSize : 2;
    }

    // Cached formatted time strings – only reformat when minute/hour actually changes
    private var cachedHourStr as Lang.String = "";
    private var cachedMinStr as Lang.String = "";
    private var lastCachedHour as Lang.Number = -1;
    private var lastCachedMin as Lang.Number = -1;
    private var lastIs24Hour as Lang.Boolean = true;

    //! Returns [hourStr, minStr] – helper in type-checked code so compiler sees member reads
    private function getCachedTimeStrings() as Lang.Array {
        return [cachedHourStr, cachedMinStr];
    }

    //! Returns [lastHour, lastMin, lastIs24] – helper so compiler sees lastCached* reads
    private function getTimeCacheState() as Lang.Array {
        return [lastCachedHour, lastCachedMin, lastIs24Hour];
    }

    //! Updates time cache state – helper so compiler sees lastCached* writes
    private function setTimeCacheState(lastHour as Lang.Number, lastMin as Lang.Number, is24 as Lang.Boolean) as Void {
        lastCachedHour = lastHour;
        lastCachedMin = lastMin;
        lastIs24Hour = is24;
    }

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

    //! Get fill color for a zone in the given scheme (0=White, 1=Greyscale, 2=Garmin, 3=Viridis, 4=Magma)
    private function getColorForZone(schemeId as Lang.Number, zoneIndex as Lang.Number, forMinutes as Lang.Boolean) as Lang.Number {
        if (schemeId == SCHEME_WHITE) {
            return forMinutes ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_WHITE;
        }
        if (schemeId == SCHEME_GREYSCALE) {
            var fill = [Graphics.COLOR_WHITE, Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY,
                        0x555555, 0x444444, 0x333333];  // progressively darker
            var dark = [Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY, 0x444444,
                        0x333333, 0x222222, 0x111111];  // darker shades
            return forMinutes ? dark[zoneIndex] : fill[zoneIndex];
        }
        if (schemeId == SCHEME_GARMIN) {
            var fill = [Graphics.COLOR_WHITE, Graphics.COLOR_LT_GRAY, COLOR_VIVID_BLUE,
                        Graphics.COLOR_GREEN, COLOR_VIVID_ORANGE, Graphics.COLOR_RED];
            var dark = [Graphics.COLOR_LT_GRAY, Graphics.COLOR_DK_GRAY, COLOR_DK_VIVID_BLUE,
                        Graphics.COLOR_DK_GREEN, COLOR_DK_VIVID_ORANGE, Graphics.COLOR_DK_RED];
            return forMinutes ? dark[zoneIndex] : fill[zoneIndex];
        }
        if (schemeId == SCHEME_VIRIDIS) {
            // Viridis: dark purple → blue → teal → green → yellow (perceptually uniform)
            var fill = [0x440154, 0x3b528b, 0x21908c, 0x5ec962, 0xb4de2c, 0xfde725];
            var dark = [0x2d0e3a, 0x28395e, 0x166161, 0x3e9a47, 0x8bb820, 0xc7b81c];
            return forMinutes ? dark[zoneIndex] : fill[zoneIndex];
        }
        if (schemeId == SCHEME_MAGMA) {
            // Magma: dark purple → purple → magenta → orange → yellow (shifted; low zone no longer black)
            var fill = [0x180f3e, 0x51127c, 0xb73779, 0xf89662, 0xfcfdbf, 0xfffef0];
            var dark = [0x0f0a26, 0x350b53, 0x7a2553, 0xcb6a43, 0xd4d5a8, 0xe8e8d0];
            return forMinutes ? dark[zoneIndex] : fill[zoneIndex];
        }
        return Graphics.COLOR_WHITE;
    }

    //! Return the darker shade for minutes (scheme-aware)
    private function getDarkerShadeForZone(zoneIndex as Lang.Number, schemeId as Lang.Number) as Lang.Number {
        return getColorForZone(schemeId, zoneIndex, true);
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
        
        // Init fonts (fallback to system font defaults if resource load fails)
        var loadedFont = Ui.loadResource(Rez.Fonts.protomoleculefont);
        if (loadedFont != null) {
            bigNumProtomolecule = loadedFont as Gfx.FontReference;
        }
        var loadedFontOutline = Ui.loadResource(Rez.Fonts.protomoleculefontoutline);
        if (loadedFontOutline != null) {
            bigNumProtomoleculeOutline = loadedFontOutline as Gfx.FontReference;
        }
        var loadedFontOutlineThick = Ui.loadResource(Rez.Fonts.protomoleculefontoutlinethick);
        if (loadedFontOutlineThick != null) {
            bigNumProtomoleculeOutlineThick = loadedFontOutlineThick as Gfx.FontReference;
        }

        // Determine and store HR zones; fallback to age-estimated if profile not configured
        var profileZones = UserProfile.getHeartRateZones(Up.HR_ZONE_SPORT_GENERIC);
        if (profileZones != null && profileZones.size() > 5) {
            heartRateZones = profileZones;
        } else {
            heartRateZones = getDefaultHeartRateZones();
        }
        
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
        reducedWidth = (width * GRAPH_WIDTH_RATIO).toNumber();
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
        var is24Hour = System.getDeviceSettings().is24Hour;
        var state = getTimeCacheState();
        var lastHour = state[0] as Lang.Number;
        var lastMin = state[1] as Lang.Number;
        var lastIs24 = state[2] as Lang.Boolean;
        if (hour != lastHour || is24Hour != lastIs24) {
            if (is24Hour) {
                cachedHourStr = hour.format("%02d");
            } else {
                // 12-hour conversion: 0 becomes 12, 13-23 become 1-11
                var displayHour = hour % 12;
                if (displayHour == 0) {
                    displayHour = 12;
                }
                cachedHourStr = displayHour.format("%d");
            }
            setTimeCacheState(hour, lastMin, is24Hour);
        }
        if (min != lastMin) {
            cachedMinStr  = min.format("%02d");
            setTimeCacheState(hour, min, is24Hour);
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
            minColor = (getMinutesColorMode() == 1) ? hourColor : getDarkerShadeForZone(zoneIdx, fontScheme);
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
        var strs = getCachedTimeStrings();
        var hourStr = strs[0] as Lang.String;
        var minStr = strs[1] as Lang.String;
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

    // Always On view: outlined font + outlined rectangles to keep drawn pixels down for AMOLED.
    // Time is drawn by onUpdate; this only draws the graph.
    private function drawLowPowerView(dc as Gfx.Dc) as Void {
        drawHeartRateGraph(dc, true);
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
            var sample = sensorIter.next();
            while (sample != null) {
                if (sample.data != null) {
                    newData.add(sample.data);
                }
                sample = sensorIter.next();
            }
            lastFetchTime = now;
            var newSize = newData.size();
            if (newSize > 0) {
                cachedHeartRateData = newData;
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
            
            var zones5 = zones[5] as Lang.Number;  // hoist invariant out of loop
            var lastIdx = dataSize - 1;
            for (var x = 0; x < reducedWidth; x += stepSize) {
                var sampleIndex = x * dataSize / reducedWidth;  // all Numbers – integer division, no toNumber needed
                if (sampleIndex > lastIdx) {
                    sampleIndex = lastIdx;
                }
                
                var heartRate = data[sampleIndex] as Lang.Number or Null;
                if (heartRate != null) {
                    var y = (graphBottom - (heartRate * graphHeight / zones5)).toNumber();
                    var barH = graphBottom - y;
                    if (barH <= 0) { continue; }  // filter at build time – drawing loops skip the check
                    // Low-power flat array
                    allBars.add(x);
                    allBars.add(y);
                    allBars.add(barH);
                    // Full view - bucket by zone index (scheme applied at draw time)
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
            // Low-power / Always On: draw rectangles directly on the DC.
            // A drawBitmap blit would register the entire bitmap area in the
            // AMOLED heatmap, even for transparent pixels.  Direct drawing
            // is fine here because AOD updates at most once per minute.
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
            if (hasBufferedBitmap && graphBitmapRef != null) {
                var gBitmap = graphBitmapRef.get() as Gfx.BufferedBitmap;
                var barsScheme = getBarsColorScheme();
                // Re-render to bitmap if bar data changed, scheme changed, gap changed, or bitmap was evicted
                var barsGap = getBarsGap();
                if (graphBitmapVersion != cachedBarVersion || lastRenderedBarsScheme != barsScheme || lastRenderedBarsGap != barsGap || !gBitmap.isCached()) {
                    drawBarsToBitmap(barsScheme);
                    lastRenderedBarsScheme = barsScheme;
                    lastRenderedBarsGap = barsGap;
                }
                dc.drawBitmap(0, 0, gBitmap);
            } else {
                // Fallback: per-bar fillRectangle loops
                dc.setPenWidth(1);
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
    private function drawBarsToBitmap(barsScheme as Lang.Number) as Void {
        var ref = graphBitmapRef;
        if (ref == null) { return; }
        var bitmap = ref.get() as Gfx.BufferedBitmap;
        var bdc = bitmap.getDc();
        // Clear to transparent
        bdc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
        bdc.clear();
        bdc.setPenWidth(1);
        // Draw each zone bucket with scheme colors (bitmap is full-screen, no y offset needed)
        drawAllBarBuckets(bdc, Graphics.COLOR_TRANSPARENT, 0, barsScheme, getBarWidth());
        graphBitmapVersion = cachedBarVersion;
    }


    //! Generate time-varying synthetic HR data that scrolls with the clock.
    //! Uses overlapping triangle waves + pseudo-random jitter to produce
    //! realistic-looking patterns that cover all HR zones.
    //! Included only in debug builds (excluded by :debugHrData annotation in production).
    (:debugHrData)
    private function generateDebugHrData() as Lang.Array {
        var zones = heartRateZones;
        if (zones == null || zones.size() < 6) { return []; }
        var z0 = zones[0] as Lang.Number;
        var z5 = zones[5] as Lang.Number;
        var range = z5 - z0;

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

            var hr = z0 + range * pct / 100;
            if (hr < z0 - 10) { hr = z0 - 10; }
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
    }

    // Terminate any active timers and prepare for slow updates.
    // AMOLED: draw <10% pixels in onUpdate or display will turn off.
    function onEnterSleep() as Void {
        isLowPower = true;
    }
}
