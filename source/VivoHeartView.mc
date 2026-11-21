using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang as Lang;
using Toybox.Application as App;
using Toybox.UserProfile as Up;
using Toybox.Activity as Activity;
using Toybox.ActivityMonitor as Act;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;

//! Rendering model (see README "Performance"):
//!  - HR samples are binned straight into fixed per-slot arrays during the sensor fetch
//!    (no intermediate lists), one slot per bar.
//!  - Bar geometry is rebuilt into exact-size per-zone arrays only when the slot data,
//!    bar height setting or layout changes.
//!  - Everything is drawn straight to the screen dc. No BufferedBitmaps: profiling showed
//!    drawing into one costs far more than drawing the ~86 bars + time directly
//!    (scripts/Run-Benchmark.ps1, op_* lines), and a full-screen blit alone costs about as
//!    much as the whole direct frame.
//!  - Always-on (low-power) frames are drawn directly: they run once a minute and must
//!    stay under the AMOLED lit-pixel limit, so they use outlines only.
class VivoHeartView extends Ui.WatchFace {

    //! Instance variable to store heart rate zones and font
    protected var heartRateZones as Lang.Array or Null;
    protected var bigNumProtomolecule as Gfx.FontDefinition or Gfx.FontReference or Ui.FontResource = Graphics.FONT_LARGE;
    private var bigNumProtomoleculeOutline as Gfx.FontDefinition or Gfx.FontReference or Ui.FontResource = Graphics.FONT_MEDIUM;
    protected var bigNumProtomoleculeOutlineThick as Gfx.FontDefinition or Gfx.FontReference or Ui.FontResource = Graphics.FONT_MEDIUM;
    protected var width as Lang.Number = 0;
    protected var height as Lang.Number = 0;

    // Pre-cached layout positions (computed once in onLayout)
    private var centerX as Lang.Number = 0;

    // Graph layout (computed in onLayout / when BarsHeight changes)
    private var graphBottom as Lang.Number = 0;
    private var graphHeight as Lang.Number = 0;
    private const BAR_PITCH = 5;                 // px per bar (2 px bar + 3 px gap by default)
    private const GRAPH_WIDTH_RATIO = 0.95;      // 454 px -> 86 bars, 416 -> 79, 390 -> 74, 360 -> 68
    protected var numBars as Lang.Number = 86;
    protected var barIntervalMs as Lang.Number = 0;
    protected const PERIOD_SEC = 6 * 3600;

    // Layout ratios (fraction of screen dimension)
    private const HOUR_Y_RATIO_TOP = 0.20;       // hour when position=top
    private const MINUTE_Y_RATIO_TOP = 0.53;     // minute when position=top
    private const HOUR_Y_RATIO_CENTER = 0.335;   // hour when position=centered (block centered)
    private const MINUTE_Y_RATIO_CENTER = 0.665; // minute when position=centered
    private const SIDEBYSIDE_Y_RATIO_TOP = 0.354;    // single line when position=top (~70px below stacked top)
    private const SIDEBYSIDE_Y_RATIO_CENTER = 0.5;   // single line when position=centered

    // HR slot data: one entry per bar, oldest on the left. null = no sample in that slot.
    protected var slotValues as Lang.Array = [] as Lang.Array;
    private var slotDist as Lang.Array = [] as Lang.Array;   // scratch: distance of chosen sample to slot centre
    protected var hasSlotData as Lang.Boolean = false;
    protected var cachedDataSampleCount as Lang.Number = 0;  // bumped whenever slotValues changes
    protected var lastFetchTime as Lang.Number = 0;

    //! When true, skip sensor fetch on the next onUpdate to unblock the first wake frame
    protected var deferFetch as Lang.Boolean = false;

    // Bar geometry, rebuilt only when slot data / height / layout change.
    // barTop[i] = top y of bar i, or -1 when the slot is empty. zoneBars[z] = flat [x, y, h, ...].
    private var cachedBarVersion as Lang.Number = -1;
    private var barTop as Lang.Array = [] as Lang.Array;
    private var zoneBars as Lang.Array = [[], [], [], [], [], []] as Lang.Array;
    private var lastComputedHeightPct as Lang.Number = -1;

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
    protected var hasSensorHistory as Lang.Boolean = false;
    private var hasActivityInfo as Lang.Boolean = false;

    //! True when in low-power / Always On Display mode (after onEnterSleep)
    protected var isLowPower as Lang.Boolean = false;

    // Cached user settings – loaded once in initialize() and refreshed in loadSettings().
    private var settingFontColorScheme as Lang.Number = SCHEME_GARMIN;
    private var settingBarsColorScheme as Lang.Number = SCHEME_GARMIN;
    protected var settingBarsPosition as Lang.Number = 0;  // 0 = bars behind time, 1 = bars in front
    private var settingBarsGap as Lang.Number = 1;         // 0 = bars touch, 1 = default gaps
    private var settingTimePosition as Lang.Number = 1;    // 0 = top, 1 = centered
    private var settingTimeLayout as Lang.Number = 1;      // 0 = stacked, 1 = side by side
    private var settingMinutesColorMode as Lang.Number = 0; // 0 = darker shade, 1 = match hours
    private var settingBarsHeightPercent as Lang.Number = 68;
    private var settingFontSize as Lang.Number = 1;  // 0=Small, 1=Default, 2=Large, 3=Extra Large
    private var settingFontFamily as Lang.Number = 0;  // 0=ProtoMolecule, 1=OCR Extended, 2=Rockwell Extra Bold, 3=Sans Bold
    private var settingFontAntialias as Lang.Number = 1;  // 0=Off, 1=On
    private var cachedIs24Hour as Lang.Boolean = true;  // from System.getDeviceSettings(); refreshed in loadSettings()/onExitSleep()

    //! Bar width: full pitch when no gaps (bars touch), 2 px with default gaps
    private function getBarWidth() as Lang.Number {
        return (settingBarsGap == 0) ? BAR_PITCH : 2;
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
        settingFontFamily = readNumericSetting("FontFamily", 0, 3, 0);
        settingFontAntialias = readNumericSetting("FontAntialias", 0, 1, 1);
        // Cache device-level is24Hour (avoids allocating DeviceSettings every frame)
        cachedIs24Hour = System.getDeviceSettings().is24Hour;
        // Reload fonts when FontSize setting changes
        loadFontsForCurrentSize();
    }

    //! Load fill and outline fonts for the current FontFamily, FontSize, and FontAntialias settings.
    private function loadFontsForCurrentSize() as Void {
        var sz = settingFontSize;
        var fam = settingFontFamily;
        var aa = settingFontAntialias;
        var fillRes;
        var outRes;
        var outThickRes;

        if (fam == 0) {
            // ProtoMolecule: fill + outline + outline_thick
            fillRes = (sz == 0) ? Rez.Fonts.protomoleculefont_s : (sz == 2) ? Rez.Fonts.protomoleculefont_l : (sz == 3) ? Rez.Fonts.protomoleculefont_xl : Rez.Fonts.protomoleculefont;
            if (aa == 0) { fillRes = (sz == 0) ? Rez.Fonts.protomoleculefont_s_noaa : (sz == 2) ? Rez.Fonts.protomoleculefont_l_noaa : (sz == 3) ? Rez.Fonts.protomoleculefont_xl_noaa : Rez.Fonts.protomoleculefont_noaa; }
            outRes = (sz == 0) ? Rez.Fonts.protomoleculefontoutline_s : (sz == 2) ? Rez.Fonts.protomoleculefontoutline_l : (sz == 3) ? Rez.Fonts.protomoleculefontoutline_xl : Rez.Fonts.protomoleculefontoutline;
            if (aa == 0) { outRes = (sz == 0) ? Rez.Fonts.protomoleculefontoutline_s_noaa : (sz == 2) ? Rez.Fonts.protomoleculefontoutline_l_noaa : (sz == 3) ? Rez.Fonts.protomoleculefontoutline_xl_noaa : Rez.Fonts.protomoleculefontoutline_noaa; }
            outThickRes = (sz == 0) ? Rez.Fonts.protomoleculefontoutlinethick_s : (sz == 2) ? Rez.Fonts.protomoleculefontoutlinethick_l : (sz == 3) ? Rez.Fonts.protomoleculefontoutlinethick_xl : Rez.Fonts.protomoleculefontoutlinethick;
            if (aa == 0) { outThickRes = (sz == 0) ? Rez.Fonts.protomoleculefontoutlinethick_s_noaa : (sz == 2) ? Rez.Fonts.protomoleculefontoutlinethick_l_noaa : (sz == 3) ? Rez.Fonts.protomoleculefontoutlinethick_xl_noaa : Rez.Fonts.protomoleculefontoutlinethick_noaa; }
        } else {
            // OCR Extended, Rockwell Extra Bold, Sans Bold: fill + outline + outline_thick
            fillRes = (fam == 1) ? ((sz == 0) ? Rez.Fonts.ocrextendedfont_s : (sz == 2) ? Rez.Fonts.ocrextendedfont_l : (sz == 3) ? Rez.Fonts.ocrextendedfont_xl : Rez.Fonts.ocrextendedfont)
                : (fam == 2) ? ((sz == 0) ? Rez.Fonts.rockwellextraboldfont_s : (sz == 2) ? Rez.Fonts.rockwellextraboldfont_l : (sz == 3) ? Rez.Fonts.rockwellextraboldfont_xl : Rez.Fonts.rockwellextraboldfont)
                : ((sz == 0) ? Rez.Fonts.sansboldfont_s : (sz == 2) ? Rez.Fonts.sansboldfont_l : (sz == 3) ? Rez.Fonts.sansboldfont_xl : Rez.Fonts.sansboldfont);
            if (aa == 0) {
                fillRes = (fam == 1) ? ((sz == 0) ? Rez.Fonts.ocrextendedfont_s_noaa : (sz == 2) ? Rez.Fonts.ocrextendedfont_l_noaa : (sz == 3) ? Rez.Fonts.ocrextendedfont_xl_noaa : Rez.Fonts.ocrextendedfont_noaa)
                    : (fam == 2) ? ((sz == 0) ? Rez.Fonts.rockwellextraboldfont_s_noaa : (sz == 2) ? Rez.Fonts.rockwellextraboldfont_l_noaa : (sz == 3) ? Rez.Fonts.rockwellextraboldfont_xl_noaa : Rez.Fonts.rockwellextraboldfont_noaa)
                    : ((sz == 0) ? Rez.Fonts.sansboldfont_s_noaa : (sz == 2) ? Rez.Fonts.sansboldfont_l_noaa : (sz == 3) ? Rez.Fonts.sansboldfont_xl_noaa : Rez.Fonts.sansboldfont_noaa);
            }
            outRes = (fam == 1) ? ((sz == 0) ? Rez.Fonts.ocrextendedfontoutline_s : (sz == 2) ? Rez.Fonts.ocrextendedfontoutline_l : (sz == 3) ? Rez.Fonts.ocrextendedfontoutline_xl : Rez.Fonts.ocrextendedfontoutline)
                : (fam == 2) ? ((sz == 0) ? Rez.Fonts.rockwellextraboldfontoutline_s : (sz == 2) ? Rez.Fonts.rockwellextraboldfontoutline_l : (sz == 3) ? Rez.Fonts.rockwellextraboldfontoutline_xl : Rez.Fonts.rockwellextraboldfontoutline)
                : ((sz == 0) ? Rez.Fonts.sansboldfontoutline_s : (sz == 2) ? Rez.Fonts.sansboldfontoutline_l : (sz == 3) ? Rez.Fonts.sansboldfontoutline_xl : Rez.Fonts.sansboldfontoutline);
            if (aa == 0) {
                outRes = (fam == 1) ? ((sz == 0) ? Rez.Fonts.ocrextendedfontoutline_s_noaa : (sz == 2) ? Rez.Fonts.ocrextendedfontoutline_l_noaa : (sz == 3) ? Rez.Fonts.ocrextendedfontoutline_xl_noaa : Rez.Fonts.ocrextendedfontoutline_noaa)
                    : (fam == 2) ? ((sz == 0) ? Rez.Fonts.rockwellextraboldfontoutline_s_noaa : (sz == 2) ? Rez.Fonts.rockwellextraboldfontoutline_l_noaa : (sz == 3) ? Rez.Fonts.rockwellextraboldfontoutline_xl_noaa : Rez.Fonts.rockwellextraboldfontoutline_noaa)
                    : ((sz == 0) ? Rez.Fonts.sansboldfontoutline_s_noaa : (sz == 2) ? Rez.Fonts.sansboldfontoutline_l_noaa : (sz == 3) ? Rez.Fonts.sansboldfontoutline_xl_noaa : Rez.Fonts.sansboldfontoutline_noaa);
            }
            outThickRes = (fam == 1) ? ((sz == 0) ? Rez.Fonts.ocrextendedfontoutlinethick_s : (sz == 2) ? Rez.Fonts.ocrextendedfontoutlinethick_l : (sz == 3) ? Rez.Fonts.ocrextendedfontoutlinethick_xl : Rez.Fonts.ocrextendedfontoutlinethick)
                : (fam == 2) ? ((sz == 0) ? Rez.Fonts.rockwellextraboldfontoutlinethick_s : (sz == 2) ? Rez.Fonts.rockwellextraboldfontoutlinethick_l : (sz == 3) ? Rez.Fonts.rockwellextraboldfontoutlinethick_xl : Rez.Fonts.rockwellextraboldfontoutlinethick)
                : ((sz == 0) ? Rez.Fonts.sansboldfontoutlinethick_s : (sz == 2) ? Rez.Fonts.sansboldfontoutlinethick_l : (sz == 3) ? Rez.Fonts.sansboldfontoutlinethick_xl : Rez.Fonts.sansboldfontoutlinethick);
            if (aa == 0) {
                outThickRes = (fam == 1) ? ((sz == 0) ? Rez.Fonts.ocrextendedfontoutlinethick_s_noaa : (sz == 2) ? Rez.Fonts.ocrextendedfontoutlinethick_l_noaa : (sz == 3) ? Rez.Fonts.ocrextendedfontoutlinethick_xl_noaa : Rez.Fonts.ocrextendedfontoutlinethick_noaa)
                    : (fam == 2) ? ((sz == 0) ? Rez.Fonts.rockwellextraboldfontoutlinethick_s_noaa : (sz == 2) ? Rez.Fonts.rockwellextraboldfontoutlinethick_l_noaa : (sz == 3) ? Rez.Fonts.rockwellextraboldfontoutlinethick_xl_noaa : Rez.Fonts.rockwellextraboldfontoutlinethick_noaa)
                    : ((sz == 0) ? Rez.Fonts.sansboldfontoutlinethick_s_noaa : (sz == 2) ? Rez.Fonts.sansboldfontoutlinethick_l_noaa : (sz == 3) ? Rez.Fonts.sansboldfontoutlinethick_xl_noaa : Rez.Fonts.sansboldfontoutlinethick_noaa);
            }
        }

        var loadedFont = Ui.loadResource(fillRes);
        if (loadedFont != null) { bigNumProtomolecule = loadedFont as Gfx.FontReference; }
        var loadedOutline = Ui.loadResource(outRes);
        if (loadedOutline != null) { bigNumProtomoleculeOutline = loadedOutline as Gfx.FontReference; }
        var loadedOutlineThick = Ui.loadResource(outThickRes);
        if (loadedOutlineThick != null) { bigNumProtomoleculeOutlineThick = loadedOutlineThick as Gfx.FontReference; }
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
    protected var lastCachedMin as Lang.Number = -1;
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

    //! Current HR for time colouring. Live sensor value first (cheapest, most current),
    //! then the newest ActivityMonitor sample, then the newest graph slot.
    (:production)
    private function getCurrentHeartRateForDisplay() as Lang.Number or Null {
        if (hasActivityInfo) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                var live = info.currentHeartRate;
                if (live != null && live > 0) { return live; }
            }
        }
        if (Toybox has :ActivityMonitor && Toybox.ActivityMonitor has :getHeartRateHistory) {
            var iter = Act.getHeartRateHistory(1, true);  // 1 sample, newest first
            var sample = iter.next();
            if (sample != null && sample.heartRate != null && sample.heartRate != Act.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        for (var i = slotValues.size() - 1; i >= 0; i--) {
            if (slotValues[i] != null) { return slotValues[i] as Lang.Number; }
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

    function onLayout(dc as Gfx.Dc) as Void {
        width = dc.getWidth();
        height = dc.getHeight();
        centerX = width / 2;

        graphBottom = height;
        lastComputedHeightPct = settingBarsHeightPercent;
        graphHeight = height * lastComputedHeightPct / 100;

        // Bar count follows screen width at a fixed pitch so bars look the same on every
        // resolution; the time window stays PERIOD_SEC, so each bar covers PERIOD_SEC/numBars.
        var n = (width * GRAPH_WIDTH_RATIO).toNumber() / BAR_PITCH;
        if (n < 1) { n = 1; }
        if (n != numBars || slotValues.size() != n) {
            numBars = n;
            slotValues = new [n] as Lang.Array;
            slotDist = new [n] as Lang.Array;
            barTop = new [n] as Lang.Array;
            hasSlotData = false;
            lastFetchTime = 0;
        }
        barIntervalMs = PERIOD_SEC * 1000 / numBars;

        hasActivityInfo = (Toybox has :Activity) && (Toybox.Activity has :getActivityInfo);

        cachedBarVersion = -1;
    }

    function onShow() as Void {
    }

    //! Force per-minute state (time strings) to be rebuilt on the next frame.
    function invalidateMinute() as Void {
        lastCachedMin = -1;
    }

    (:typecheck(false))
    function onUpdate(dc as Gfx.Dc) as Void {
        var clock = System.getClockTime();
        var hour = clock.hour;
        var min = clock.min;
        var is24Hour = cachedIs24Hour;
        if (hour != lastCachedHour || is24Hour != lastIs24Hour) {
            var displayHour = hour;
            if (!is24Hour) {
                // 12-hour conversion: 0 becomes 12, 13-23 become 1-11; zero-pad to 02d
                displayHour = hour % 12;
                if (displayHour == 0) { displayHour = 12; }
            }
            cachedHourStr = displayHour.format("%02d");
            lastCachedHour = hour;
            lastIs24Hour = is24Hour;
        }
        if (min != lastCachedMin) {
            cachedMinStr = min.format("%02d");
            lastCachedMin = min;
        }

        var hasZones = (heartRateZones != null && heartRateZones.size() > 5);
        var hasBars = hasZones && ensureBars();

        if (isLowPower) {
            drawScene(dc, true, hasBars, OUTLINE_COLOR, OUTLINE_COLOR);
            return;
        }

        // Time colours from current HR (same zone scale as the graph)
        var hourColor = Graphics.COLOR_WHITE;
        var minColor = Graphics.COLOR_LT_GRAY;
        if (hasZones) {
            var currentHr = getCurrentHeartRateForDisplay();
            if (currentHr != null) {
                var zoneIdx = getZoneIndex(currentHr, heartRateZones);
                hourColor = getColorForZone(settingFontColorScheme, zoneIdx, false);
                minColor = (settingMinutesColorMode == 1) ? hourColor : getColorForZone(settingFontColorScheme, zoneIdx, true);
            }
        }

        drawScene(dc, false, hasBars, hourColor, minColor);
    }

    //! Draw the full scene onto the screen dc.
    //! lowPower: outline-only time and bars (AMOLED always-on limits).
    private function drawScene(dc as Gfx.Dc, lowPower as Lang.Boolean, hasBars as Lang.Boolean,
                               hourColor as Lang.Number, minColor as Lang.Number) as Void {
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        var barsInFront = (settingBarsPosition == 1);
        if (hasBars && !barsInFront) { drawBars(dc, lowPower); }

        var hourStr = cachedHourStr;
        var minStr = cachedMinStr;
        var sideBySide = (settingTimeLayout == 1);
        var centered = (settingTimePosition == 1);
        var yA;  // hour (stacked) or both (side by side)
        var yB = 0;
        if (sideBySide) {
            yA = (height * (centered ? SIDEBYSIDE_Y_RATIO_CENTER : SIDEBYSIDE_Y_RATIO_TOP)).toNumber();
        } else {
            yA = (height * (centered ? HOUR_Y_RATIO_CENTER : HOUR_Y_RATIO_TOP)).toNumber();
            yB = (height * (centered ? MINUTE_Y_RATIO_CENTER : MINUTE_Y_RATIO_TOP)).toNumber();
        }

        // Outline (border) always behind fill
        var outFont = lowPower ? bigNumProtomoleculeOutline : bigNumProtomoleculeOutlineThick;
        dc.setColor(lowPower ? Graphics.COLOR_DK_GRAY : OUTLINE_COLOR, Graphics.COLOR_TRANSPARENT);
        drawTime(dc, outFont, hourStr, minStr, sideBySide, yA, yB, -1, -1);
        drawTime(dc, bigNumProtomolecule, hourStr, minStr, sideBySide, yA, yB, hourColor, minColor);

        if (hasBars && barsInFront) { drawBars(dc, lowPower); }
    }

    //! Draw hour + minute. Colours of -1 keep the dc's current colour.
    protected function drawTime(dc as Gfx.Dc, font as Gfx.FontType, hourStr as Lang.String, minStr as Lang.String,
                              sideBySide as Lang.Boolean, yA as Lang.Number, yB as Lang.Number,
                              hourColor as Lang.Number, minColor as Lang.Number) as Void {
        if (hourColor != -1) { dc.setColor(hourColor, Graphics.COLOR_TRANSPARENT); }
        if (sideBySide) {
            dc.drawText(centerX - 2, yA, font, hourStr, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(centerX, yA, font, hourStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (minColor != -1 && minColor != hourColor) { dc.setColor(minColor, Graphics.COLOR_TRANSPARENT); }
        if (sideBySide) {
            dc.drawText(centerX + 2, yA, font, minStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(centerX, yB, font, minStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Filled bars per zone colour (high power) or grey outlines (low power).
    protected function drawBars(dc as Gfx.Dc, lowPower as Lang.Boolean) as Void {
        var barW = getBarWidth();
        if (lowPower) {
            dc.setPenWidth(1);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_BLACK);
            for (var i = 0; i < numBars; i++) {
                var top = barTop[i] as Lang.Number;
                if (top >= 0) { dc.drawRectangle(i * BAR_PITCH, top, barW, graphBottom - top); }
            }
            return;
        }
        var scheme = settingBarsColorScheme;
        for (var z = 0; z < 6; z++) {
            var bars = zoneBars[z] as Lang.Array;
            var sz = bars.size();
            if (sz == 0) { continue; }
            dc.setColor(getColorForZone(scheme, z, false), Graphics.COLOR_BLACK);
            for (var i = 0; i < sz; i += 3) {
                dc.fillRectangle(bars[i] as Lang.Number, bars[i + 1] as Lang.Number, barW, bars[i + 2] as Lang.Number);
            }
        }
    }

    //! Make sure slot data is fresh (throttled) and bar geometry matches it.
    //! Returns true when there is something to draw.
    private function ensureBars() as Lang.Boolean {
        refreshSlotData();
        if (!hasSlotData) { return false; }
        var heightPct = settingBarsHeightPercent;
        if (heightPct != lastComputedHeightPct) {
            lastComputedHeightPct = heightPct;
            graphHeight = height * heightPct / 100;
            cachedBarVersion = -1;
        }
        if (cachedBarVersion != cachedDataSampleCount) {
            rebuildBars();
        }
        return true;
    }

    //! Slot values -> bar tops and exact-size per-zone [x, y, h] arrays (no .add growth).
    protected function rebuildBars() as Void {
        var zones = heartRateZones as Lang.Array;
        var zmax = zones[5] as Lang.Number;
        if (zmax <= 0) { zmax = 200; }  // guard against corrupted profile
        var z0 = zones[0] as Lang.Number;
        var z1 = zones[1] as Lang.Number;
        var z2 = zones[2] as Lang.Number;
        var z3 = zones[3] as Lang.Number;
        var z4 = zones[4] as Lang.Number;
        var counts = [0, 0, 0, 0, 0, 0];
        var zoneOf = new [numBars];
        for (var i = 0; i < numBars; i++) {
            var hr = slotValues[i];
            barTop[i] = -1;
            if (hr == null) { continue; }
            var y = graphBottom - (hr * graphHeight / zmax);
            if (y >= graphBottom) { continue; }
            barTop[i] = y;
            var z = (hr < z0) ? 0 : (hr <= z1) ? 1 : (hr <= z2) ? 2 : (hr <= z3) ? 3 : (hr <= z4) ? 4 : 5;
            zoneOf[i] = z;
            counts[z] = counts[z] + 1;
        }
        var fill = [0, 0, 0, 0, 0, 0];
        for (var z = 0; z < 6; z++) { zoneBars[z] = new [(counts[z] as Lang.Number) * 3]; }
        for (var i = 0; i < numBars; i++) {
            var top = barTop[i] as Lang.Number;
            if (top < 0) { continue; }
            var z = zoneOf[i] as Lang.Number;
            var arr = zoneBars[z] as Lang.Array;
            var k = fill[z] as Lang.Number;
            arr[k] = i * BAR_PITCH;
            arr[k + 1] = top;
            arr[k + 2] = graphBottom - top;
            fill[z] = k + 3;
        }
        cachedBarVersion = cachedDataSampleCount;
    }

    //! Production: throttled SensorHistory fetch, binned straight into slotValues.
    (:production)
    private function refreshSlotData() as Void {
        var now = System.getTimer();
        if (hasSlotData && (now - lastFetchTime < barIntervalMs)) { return; }
        if (!hasSensorHistory) { return; }
        if (deferFetch && hasSlotData) {
            // Draw the first wake frame from the cache; fetch on the next update.
            deferFetch = false;
            Ui.requestUpdate();
            return;
        }
        deferFetch = false;
        doProductionFetch();
    }

    //! Fetch the last PERIOD_SEC of HR history and keep, per slot, the sample closest to the
    //! slot centre. Single pass, no intermediate arrays.
    (:production)
    protected function doProductionFetch() as Void {
        var now = System.getTimer();
        lastFetchTime = now;
        try {
            var iter = Toybox.SensorHistory.getHeartRateHistory({:period => PERIOD_SEC, :order => SensorHistory.ORDER_OLDEST_FIRST});
            var n = numBars;
            var slotSec = PERIOD_SEC / n;
            var half = slotSec / 2;
            var periodStart = Time.now().value() - PERIOD_SEC;
            var vals = slotValues;
            var dist = slotDist;
            for (var i = 0; i < n; i++) { vals[i] = null; dist[i] = slotSec; }
            var any = false;
            var sample = iter.next();
            while (sample != null) {
                var hr = sample.data;
                var when = sample.when;
                if (hr != null && when != null) {
                    var off = when.value() - periodStart;
                    if (off >= 0) {
                        var idx = off / slotSec;
                        if (idx < n) {
                            var d = off - idx * slotSec - half;
                            if (d < 0) { d = -d; }
                            if (d < (dist[idx] as Lang.Number)) {
                                dist[idx] = d;
                                vals[idx] = hr;
                                any = true;
                            }
                        }
                    }
                }
                sample = iter.next();
            }
            if (any || hasSlotData) {
                hasSlotData = any;
                cachedDataSampleCount++;
            }
        } catch (ex) {
        }
    }

    //! Debug: synthetic HR data, regenerated once per minute.
    (:debugHrData)
    private var lastDebugMinute as Lang.Number = -1;

    (:debugHrData)
    private function refreshSlotData() as Void {
        var ct = System.getClockTime();
        var m = ct.hour * 60 + ct.min;
        if (m == lastDebugMinute && hasSlotData) { return; }
        lastDebugMinute = m;
        var data = generateDebugHrData();
        if (data.size() == numBars) {
            for (var i = 0; i < numBars; i++) { slotValues[i] = data[i]; }
            hasSlotData = true;
            cachedDataSampleCount++;
        }
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
        // Each bar spans PERIOD_SEC / numBars (~4-5 minutes)
        var barSpan = PERIOD_SEC / 60 / numBars;
        if (barSpan < 1) { barSpan = 1; }

        var data = new [numBars];
        for (var i = 0; i < numBars; i++) {
            // Absolute minute this bar represents (oldest on the left)
            var t = minuteNow - (numBars - 1 - i) * barSpan;

            // --- Slow triangle wave (period ~127 min ≈ 2 hr) ---
            var sp = t % 127;
            if (sp < 0) { sp = sp + 127; }
            var slow = (sp < 64) ? (sp * 100 / 63) : ((127 - sp) * 100 / 63);

            // --- Medium triangle wave (period ~41 min) ---
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

    function onHide() as Void {
    }

    // The user has just looked at their watch.
    function onExitSleep() as Void {
        isLowPower = false;
        deferFetch = true;  // draw first wake frame with stale cache, fetch on next update
        cachedIs24Hour = System.getDeviceSettings().is24Hour;  // refresh on wake
    }

    // AMOLED: draw <10% pixels in onUpdate or display will turn off.
    function onEnterSleep() as Void {
        isLowPower = true;
    }
}
