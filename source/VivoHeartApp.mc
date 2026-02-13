using Toybox.Application as App;
using Toybox.Lang as Lang;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;

class VivoHeartApp extends App.AppBase {

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
        return [ new VivoHeartView() ];
    }

    // Return the settings view for "Customize" / "Trigger App Settings"
    function getSettingsView() as [Ui.Views] or [Ui.Views, Ui.InputDelegates] or Null {
        return [ new VivoHeartSettingsView(), new VivoHeartSettingsDelegate() ];
    }
    
    //! Called when settings change (GCM, Express, simulator).
    //! Requests a watch face redraw so the new values take effect immediately.
    function onSettingsChanged() as Void {
        Ui.requestUpdate();
    }

    function onAppInstall() as Void {
    }
    
    function onAppUpdate() as Void {
    }
}
