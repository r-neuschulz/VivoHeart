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
        Menu2.initialize({:title => Ui.loadResource(Rez.Strings.AppName)});

        var fontScheme = getProp("FontColorScheme", 2);
        var barsScheme = getProp("BarsColorScheme", 2);
        var barsPos = getProp("BarsPosition", 0);
        var barsGap = getProp("BarsGap", 1);
        var timePos = getProp("TimePosition", 0);
        var timeLayout = getProp("TimeLayout", 0);
        var minutesColor = getProp("MinutesColorMode", 0);
        var barsHeight = getProp("BarsHeight", 1);

        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.FontColorScheme), fontSchemeLabel(fontScheme), "FontColorScheme", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.BarsColorScheme), barsSchemeLabel(barsScheme), "BarsColorScheme", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.BarsPosition), barsPosLabel(barsPos), "BarsPosition", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.BarsGap), barsGapLabel(barsGap), "BarsGap", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.BarsHeight), barsHeightLabel(barsHeight), "BarsHeight", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.TimePosition), timePosLabel(timePos), "TimePosition", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.TimeLayout), timeLayoutLabel(timeLayout), "TimeLayout", {}));
        addItem(new Ui.MenuItem(Ui.loadResource(Rez.Strings.MinutesColorMode), minutesColorLabel(minutesColor), "MinutesColorMode", {}));
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
        var labels = [
            Ui.loadResource(Rez.Strings.White),
            Ui.loadResource(Rez.Strings.Greyscale),
            Ui.loadResource(Rez.Strings.Garmin),
            Ui.loadResource(Rez.Strings.Viridis),
            Ui.loadResource(Rez.Strings.Magma)
        ];
        return idx >= 0 && idx < labels.size() ? labels[idx] as Lang.String : Ui.loadResource(Rez.Strings.Garmin) as Lang.String;
    }

    private function barsSchemeLabel(idx as Lang.Number) as Lang.String {
        return fontSchemeLabel(idx);
    }

    private function barsPosLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? Ui.loadResource(Rez.Strings.BarsInFront) as Lang.String : Ui.loadResource(Rez.Strings.BarsBehind) as Lang.String;
    }

    private function barsGapLabel(idx as Lang.Number) as Lang.String {
        return (idx == 0) ? Ui.loadResource(Rez.Strings.BarsGapNone) as Lang.String : Ui.loadResource(Rez.Strings.BarsGapDefault) as Lang.String;
    }

    private function timePosLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? Ui.loadResource(Rez.Strings.TimePositionCentered) as Lang.String : Ui.loadResource(Rez.Strings.TimePositionTop) as Lang.String;
    }

    private function timeLayoutLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? Ui.loadResource(Rez.Strings.TimeLayoutSideBySide) as Lang.String : Ui.loadResource(Rez.Strings.TimeLayoutStacked) as Lang.String;
    }

    private function minutesColorLabel(idx as Lang.Number) as Lang.String {
        return (idx == 1) ? Ui.loadResource(Rez.Strings.MinutesColorMatch) as Lang.String : Ui.loadResource(Rez.Strings.MinutesColorDarker) as Lang.String;
    }

    private function barsHeightLabel(idx as Lang.Number) as Lang.String {
        var labels = [
            Ui.loadResource(Rez.Strings.BarsHeight50),
            Ui.loadResource(Rez.Strings.BarsHeight68),
            Ui.loadResource(Rez.Strings.BarsHeight80),
            Ui.loadResource(Rez.Strings.BarsHeight90),
            Ui.loadResource(Rez.Strings.BarsHeight100)
        ];
        return idx >= 0 && idx < labels.size() ? labels[idx] as Lang.String : Ui.loadResource(Rez.Strings.BarsHeight68) as Lang.String;
    }
}
