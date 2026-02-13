//
// Input delegate for the settings view. Menu is pushed in onShow,
// so this mainly handles back/escape when the menu is popped.
//
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

//! Delegate for the settings view (underlying the menu)
class VivoHeartSettingsDelegate extends Ui.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        Ui.popView(Ui.SLIDE_IMMEDIATE);
        return true;
    }
}
