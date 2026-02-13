//
// On-device settings view. Pushes the settings menu immediately so
// "Trigger App Settings" / "Customize" shows the menu without an extra step.
//
using Toybox.Application as App;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.WatchUi as Ui;

//! Initial settings view – immediately pushes the main settings menu
class VivoHeartSettingsView extends Ui.View {

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        // Push settings menu immediately so user sees options right away
        Ui.pushView(new $.VivoHeartSettingsMenu(), new $.VivoHeartSettingsMenuDelegate(), Ui.SLIDE_IMMEDIATE);
    }

    function onUpdate(dc as Gfx.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }
}
