using Toybox.Application as App;
using Toybox.Lang as Lang;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;

class VivoHeartApp extends App.AppBase {

    private var vivoHeartView as VivoHeartView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Lang.Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Lang.Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Ui.Views] or [Ui.Views, Ui.InputDelegates] {
        vivoHeartView = new VivoHeartView();
        return [ vivoHeartView ];
    }

    // Return the settings view for "Customize" / "Trigger App Settings"
    function getSettingsView() as [Ui.Views] or [Ui.Views, Ui.InputDelegates] or Null {
        return [ new VivoHeartSettingsView(), new VivoHeartSettingsDelegate() ];
    }
    
    //! Called when settings change (GCM, Express, simulator).
    //! Refreshes cached settings in the view, then requests a redraw.
    function onSettingsChanged() as Void {
        if (vivoHeartView != null) {
            (vivoHeartView as VivoHeartView).loadSettings();
        }
        Ui.requestUpdate();
    }

    function onAppInstall() as Void {
    }
    
    function onAppUpdate() as Void {
    }
}
