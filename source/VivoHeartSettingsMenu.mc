//
// On-device settings menu. Mirrors settings.xml / properties.xml.
// Uses App.Properties so values stay in sync with GCM, Express, and simulator.
//
using Toybox.Application as App;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

//! Main settings Menu2 – four list-style options matching settings.xml
class VivoHeartSettingsMenu extends Ui.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "VivoHeart"});

        var fontScheme = getProp("FontColorScheme", 2);
        var barsScheme = getProp("BarsColorScheme", 2);
        var barsPos = getProp("BarsPosition", 0);
        var barsGap = getProp("BarsGap", 1);
        var timePos = getProp("TimePosition", 0);
        var timeLayout = getProp("TimeLayout", 0);
        var minutesColor = getProp("MinutesColorMode", 0);
        var barsHeight = getProp("BarsHeight", 1);

        addItem(new Ui.MenuItem("Font Color Scheme", fontSchemeLabel(fontScheme), "FontColorScheme", {}));
        addItem(new Ui.MenuItem("Bars Color Scheme", barsSchemeLabel(barsScheme), "BarsColorScheme", {}));
        addItem(new Ui.MenuItem("Display Order", barsPosLabel(barsPos), "BarsPosition", {}));
        addItem(new Ui.MenuItem("Bar Gaps", barsGapLabel(barsGap), "BarsGap", {}));
        addItem(new Ui.MenuItem("Bar Height", barsHeightLabel(barsHeight), "BarsHeight", {}));
        addItem(new Ui.MenuItem("Time Position", timePosLabel(timePos), "TimePosition", {}));
        addItem(new Ui.MenuItem("Time Layout", timeLayoutLabel(timeLayout), "TimeLayout", {}));
        addItem(new Ui.MenuItem("Minutes Color", minutesColorLabel(minutesColor), "MinutesColorMode", {}));
    }

    private function getProp(key as Lang.String, defaultVal as Lang.Number) as Lang.Number {
        try {
            var v = App.Properties.getValue(key);
            if (v != null && v instanceof Lang.Number) {
                return v as Lang.Number;
            }
        } catch (e) { }
        return defaultVal;
    }

    private function fontSchemeLabel(idx as Lang.Number) as Lang.String {
        var labels = ["White", "Greyscale", "Garmin", "Viridis", "Magma"];
        return idx >= 0 && idx < labels.size() ? labels[idx] : "Garmin";
    }

    private function barsSchemeLabel(idx as Lang.Number) as Lang.String {
        return fontSchemeLabel(idx);
    }

    private function barsPosLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? "Bars on Top" : "Time on Top";
    }

    private function barsGapLabel(idx as Lang.Number) as Lang.String {
        return (idx == 0) ? "None" : "Default";
    }

    private function timePosLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? "Centered" : "Top";
    }

    private function timeLayoutLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? "Side by Side" : "Stacked";
    }

    private function minutesColorLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? "Match Hours" : "Darker Shade";
    }

    private function barsHeightLabel(idx as Lang.Number) as Lang.String {
        var labels = ["50%", "68%", "80%", "90%", "100%"];
        return idx >= 0 && idx < labels.size() ? labels[idx] : "68%";
    }
}
