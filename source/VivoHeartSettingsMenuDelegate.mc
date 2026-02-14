//
// Handles main settings menu selection. Pushes a picker submenu for list options.
//
using Toybox.Application as App;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

//! Delegate for main settings menu – pushes picker when a list option is selected
class VivoHeartSettingsMenuDelegate extends Ui.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onBack() as Void {
        // Pop menu and underlying settings view so one back press fully exits settings
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }

    function onSelect(item as Ui.MenuItem) as Void {
        var id = item.getId();
        if (id != null) {
            var key = id.toString();
            if (key.equals("FontColorScheme") || key.equals("BarsColorScheme")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.White),
                    Ui.loadResource(Rez.Strings.Greyscale),
                    Ui.loadResource(Rez.Strings.Garmin),
                    Ui.loadResource(Rez.Strings.Viridis),
                    Ui.loadResource(Rez.Strings.Magma)
                ]);
            } else if (key.equals("BarsPosition")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.BarsBehind),
                    Ui.loadResource(Rez.Strings.BarsInFront)
                ]);
            } else if (key.equals("BarsGap")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.BarsGapNone),
                    Ui.loadResource(Rez.Strings.BarsGapDefault)
                ]);
            } else if (key.equals("TimePosition")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.TimePositionTop),
                    Ui.loadResource(Rez.Strings.TimePositionCentered)
                ]);
            } else if (key.equals("TimeLayout")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.TimeLayoutStacked),
                    Ui.loadResource(Rez.Strings.TimeLayoutSideBySide)
                ]);
            } else if (key.equals("MinutesColorMode")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.MinutesColorDarker),
                    Ui.loadResource(Rez.Strings.MinutesColorMatch)
                ]);
            } else if (key.equals("BarsHeight")) {
                pushPicker(key, [
                    Ui.loadResource(Rez.Strings.BarsHeight50),
                    Ui.loadResource(Rez.Strings.BarsHeight68),
                    Ui.loadResource(Rez.Strings.BarsHeight80),
                    Ui.loadResource(Rez.Strings.BarsHeight90),
                    Ui.loadResource(Rez.Strings.BarsHeight100)
                ]);
            }
        }
    }

    private function pushPicker(propertyKey as Lang.String, labels as Lang.Array) as Void {
        var picker = new Ui.Menu2({:title => Ui.loadResource(Rez.Strings.Select)});
        for (var i = 0; i < labels.size(); i++) {
            picker.addItem(new Ui.MenuItem(labels[i] as Lang.String, null, i, {}));
        }
        Ui.pushView(picker, new $.VivoHeartSettingsPickerDelegate(propertyKey), Ui.SLIDE_IMMEDIATE);
    }
}
