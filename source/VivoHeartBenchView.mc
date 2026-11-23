using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang as Lang;
using Toybox.Time as Time;
using Toybox.Activity as Activity;
using Toybox.ActivityMonitor as Act;

//! Benchmark harness. Compiled only by monkey.bench.jungle (annotation :bench).
//! Times each render path over many iterations and prints one line per
//! scenario via System.println (console under monkeydo, GARMIN/APPS/LOGS/<APP>.TXT
//! on a device). Uses a fixed synthetic 6 h HR set so runs are comparable.
(:bench)
class VivoHeartBenchView extends VivoHeartView {

    // 1 warm-up frame (cache fills, bitmap allocation) + 1 measured frame per scenario.
    // Kept small for real watches, where 1 Hz updates last only ~10 s per wrist raise and
    // then drop to one per minute.
    private const FRAMES_PER_SCENARIO = 2;
    private var iterations as Lang.Number = 20;   // per onUpdate; scaled per scenario below
    private var frame as Lang.Number = 0;
    private var totals as Lang.Array = [] as Lang.Array;
    private var counts as Lang.Array = [] as Lang.Array;
    private var names as Lang.Array = [
        "steady_frame",       // 1 Hz high-power frame, nothing changed
        "minute_change",      // time strings + any per-minute work invalidated
        "data_refresh",       // new HR samples: cached bars re-rendered + frame
        "bars_on_top",        // steady frame with BarsPosition = bars on top
        "low_power_frame",    // always-on frame
        "hr_lookup_actmon",   // ActivityMonitor.getHeartRateHistory(1)
        "hr_lookup_activity", // Activity.getActivityInfo().currentHeartRate
        "sensor_fetch_6h",    // full fetch: empty ring, 6 h of SensorHistory
        "sensor_fetch_incr",  // incremental fetch: one slot rolled over
        "op_screen_clear",
        "op_screen_bars",
        "op_screen_text",     // thick outline + fill, hour + minute
        "op_bmp_clear",       // opaque screen-sized bitmap
        "op_bmp_bars",
        "op_bmp_text",
        "op_blit_frame",
        "op_argb_clear",      // full-alpha bitmap, same size (old graph bitmap format)
        "op_argb_bars",
        "op_argb_text",
        "op_argb_blit"
    ] as Lang.Array;
    private var argbRef as Gfx.BufferedBitmapReference or Null = null;
    private var opaqueRef as Gfx.BufferedBitmapReference or Null = null;
    private var synthData as Lang.Array = [] as Lang.Array;
    private var synthTimes as Lang.Array = [] as Lang.Array;
    private var done as Lang.Boolean = false;
    private var sink as Lang.Number or Null = null;  // keeps lookups from being dead code

    function initialize() {
        VivoHeartView.initialize();
        for (var i = 0; i < names.size(); i++) { totals.add(0); counts.add(0); }
    }

    //! Deterministic 6 h HR series: one sample every 120 s (SensorHistory cadence on
    //! recent devices), triangle waves across all zones.
    private function buildSynthetic() as Void {
        var zones = heartRateZones;
        if (zones == null) { return; }
        var z0 = zones[0] as Lang.Number;
        var z5 = zones[5] as Lang.Number;
        var lo = z0 - 40; if (lo < 40) { lo = 40; }
        var nowSec = Time.now().value();
        var n = 6 * 3600 / 120;
        synthData = new [n] as Lang.Array;
        synthTimes = new [n] as Lang.Array;
        for (var i = 0; i < n; i++) {
            var p = i % 37;
            var tri = (p < 19) ? (p * 100 / 18) : ((37 - p) * 100 / 18);
            synthData[i] = lo + (z5 - lo) * tri / 100;
            synthTimes[i] = nowSec - (n - i) * 120;
        }
    }

    //! Bin the synthetic series into the ring once (same nearest-to-centre rule as the fetch).
    private function loadSynthetic() as Void {
        var n = numBars;
        var ss = slotSec;
        var half = ss / 2;
        var cur = Time.now().value() / ss;
        var first = cur - n + 1;
        for (var i = 0; i < n; i++) { slotValues[i] = null; slotDist[i] = ss; }
        lastDataSlot = -1;
        for (var j = 0; j < synthData.size(); j++) {
            var t = synthTimes[j] as Lang.Number;
            var abs = t / ss;
            if (abs < first || abs > cur) { continue; }
            var d = t - abs * ss - half;
            if (d < 0) { d = -d; }
            var k = abs % n;
            if (d < (slotDist[k] as Lang.Number)) {
                slotDist[k] = d; slotValues[k] = synthData[j];
                if (abs > lastDataSlot) { lastDataSlot = abs; }
            }
        }
        newestSlot = cur;
        cachedDataSampleCount++;
    }

    private function inject() as Void {
        lastFetchTime = Sys.getTimer();  // suppress production fetch
        deferFetch = false;
    }

    (:typecheck(false))
    function onUpdate(dc as Gfx.Dc) as Void {
        if (synthData.size() == 0) { buildSynthetic(); loadSynthetic(); }
        var scen = frame / FRAMES_PER_SCENARIO;
        if (frame == 0) {
            Sys.println("BENCH device=" + Sys.getDeviceSettings().partNumber + " fw=" + Sys.getDeviceSettings().firmwareVersion
                + " screen=" + width + "x" + height + " bars=" + numBars);
        }
        frame++;
        if (scen >= names.size()) {
            inject();
            isLowPower = false;
            VivoHeartView.onUpdate(dc);
            if (!done) { report(); done = true; }
            return;
        }
        var n = iterations;
        if (scen == 1 || scen == 2) { n = 5; }  // rebuilds are heavy; keep under watchdog
        if (scen == 7) { n = 2; }
        if (scen >= 5 && scen <= 6) { n = 2000; }
        if (scen == 8) { n = 5; }
        if (scen >= 9) { n = 10; }
        // Hold the bars-position setting for the whole scenario: switching it recreates
        // the cached bitmaps, which belongs in the warm-up frame, not the measurement.
        if (settingBarsPosition != ((scen == 3) ? 1 : 0)) {
            settingBarsPosition = (scen == 3) ? 1 : 0;
            settingsVersion++;
        }
        var fdc = null;
        var adc = null;
        if (scen >= 12 && scen <= 15) {
            if (opaqueRef == null) {
                opaqueRef = Graphics.createBufferedBitmap({:width => width, :height => height});
            }
            var fb = (opaqueRef as Gfx.BufferedBitmapReference).get();
            fdc = (fb as Gfx.BufferedBitmap).getDc();
        }
        if (scen >= 16) {
            if (argbRef == null) {
                argbRef = Graphics.createBufferedBitmap({:width => width, :height => height, :alphaBlending => Graphics.ALPHA_BLENDING_FULL});
            }
            adc = ((argbRef as Gfx.BufferedBitmapReference).get() as Gfx.BufferedBitmap).getDc();
        }
        var ts = "12";

        var t0 = Sys.getTimer();
        for (var i = 0; i < n; i++) {
            if (scen == 0) {
                inject(); isLowPower = false; VivoHeartView.onUpdate(dc);
            } else if (scen == 1) {
                inject(); isLowPower = false; lastCachedMin = -1; invalidateMinute(); VivoHeartView.onUpdate(dc);
            } else if (scen == 2) {
                inject(); isLowPower = false; cachedDataSampleCount++; VivoHeartView.onUpdate(dc);
            } else if (scen == 3) {
                inject(); isLowPower = false; VivoHeartView.onUpdate(dc);
            } else if (scen == 4) {
                inject(); isLowPower = true; VivoHeartView.onUpdate(dc);
            } else if (scen == 5) {
                var it = Act.getHeartRateHistory(1, true);
                var s = it.next();
                if (s != null) { sink = s.heartRate; }
            } else if (scen == 6) {
                var info = Activity.getActivityInfo();
                if (info != null) { sink = info.currentHeartRate; }
            } else if (scen == 7) {
                newestSlot = -1; deferFetch = false;
                doProductionFetch();
            } else if (scen == 8) {
                newestSlot = newestSlot - 1; deferFetch = false;
                doProductionFetch();
            } else if (scen == 9 || scen == 12 || scen == 16) {
                var cdc = (scen == 9) ? dc : (scen == 12) ? fdc : adc;
                cdc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
                cdc.clear();
            } else if (scen == 10 || scen == 13 || scen == 17) {
                renderBars((scen == 10) ? dc : (scen == 13) ? fdc : adc, false);
            } else if (scen == 11 || scen == 14 || scen == 18) {
                var tdc = (scen == 11) ? dc : (scen == 14) ? fdc : adc;
                tdc.setColor(0x050505, Gfx.COLOR_TRANSPARENT);
                drawTime(tdc, bigNumProtomoleculeOutlineThick, ts, ts, true, height / 2, 0, -1, -1);
                drawTime(tdc, bigNumProtomolecule, ts, ts, true, height / 2, 0, Gfx.COLOR_WHITE, Gfx.COLOR_LT_GRAY);
            } else if (scen == 15) {
                dc.drawBitmap(0, 0, (opaqueRef as Gfx.BufferedBitmapReference).get() as Gfx.BufferedBitmap);
            } else if (scen == 19) {
                dc.drawBitmap(0, 0, (argbRef as Gfx.BufferedBitmapReference).get() as Gfx.BufferedBitmap);
            }
        }
        var dt = Sys.getTimer() - t0;
        isLowPower = false;
        if (scen == 7 || scen == 8) { loadSynthetic(); inject(); }
        // Skip the first frame of each scenario (warm-up: cache fills, bitmap alloc)
        if (frame % FRAMES_PER_SCENARIO != 1) {
            totals[scen] = (totals[scen] as Lang.Number) + dt;
            counts[scen] = (counts[scen] as Lang.Number) + n;
        }
        // Write each result as soon as its scenario finishes, so a partial run still
        // leaves data in the device log.
        if (frame % FRAMES_PER_SCENARIO == 0) {
            var c = counts[scen] as Lang.Number;
            if (c > 0) {
                Sys.println("BENCH " + names[scen] + " us_per_call=" + ((totals[scen] as Lang.Number) * 1000 / c) + " n=" + c);
            }
        }
    }

    private function report() as Void {
        var st = Sys.getSystemStats();
        Sys.println("BENCH mem_used=" + st.usedMemory + " mem_total=" + st.totalMemory);
        Sys.println("BENCH DONE");
    }
}
