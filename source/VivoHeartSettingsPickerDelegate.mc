//
// Handles picker submenu selection. Saves to App.Properties and pops back.
//
using Toybox.Application as App;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

//! Delegate for list picker – saves selected value to Properties and pops
class VivoHeartSettingsPickerDelegate extends Ui.Menu2InputDelegate {

    private var _propertyKey as Lang.String;

    function initialize(propertyKey as Lang.String) {
        Menu2InputDelegate.initialize();
        _propertyKey = propertyKey;
    }

    function onSelect(item as Ui.MenuItem) as Void {
        var value = item.getId();
        if (value instanceof Lang.Number) {
            try {
                App.Properties.setValue(_propertyKey, value);
                Ui.requestUpdate();
            } catch (e) { }
        }
        Ui.popView(Ui.SLIDE_IMMEDIATE);
    }
}
