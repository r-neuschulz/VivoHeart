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

    function onSelect(item as Ui.MenuItem) as Void {
        var id = item.getId();
        if (id != null) {
            var key = id.toString();
            if (key.equals("FontColorScheme") || key.equals("BarsColorScheme")) {
                pushPicker(key, ["White", "Greyscale", "Garmin", "Viridis", "Magma"]);
            } else if (key.equals("BarsPosition")) {
                pushPicker(key, ["Time on Top", "Bars on Top"]);
            } else if (key.equals("BarsGap")) {
                pushPicker(key, ["None", "Default"]);
            } else if (key.equals("TimePosition")) {
                pushPicker(key, ["Top", "Centered"]);
            } else if (key.equals("TimeLayout")) {
                pushPicker(key, ["Stacked", "Side by Side"]);
            } else if (key.equals("MinutesColorMode")) {
                pushPicker(key, ["Darker Shade", "Match Hours"]);
            } else if (key.equals("BarsHeight")) {
                pushPicker(key, ["50%", "68%", "80%", "90%", "100%"]);
            }
        }
    }

    private function pushPicker(propertyKey as Lang.String, labels as Lang.Array) as Void {
        var picker = new Ui.Menu2({:title => "Select"});
        for (var i = 0; i < labels.size(); i++) {
            picker.addItem(new Ui.MenuItem(labels[i] as Lang.String, null, i, {}));
        }
        Ui.pushView(picker, new $.VivoHeartSettingsPickerDelegate(propertyKey, labels.size()), Ui.SLIDE_IMMEDIATE);
    }
}
