using Toybox.System as Sys;
using Toybox.Lang as Lang;

//! Step logger for on-device crash hunting (monkey.diag.jungle, scripts/Sideload-Test.ps1 -Kind diag).
//! On a watch, System.println appends to GARMIN\APPS\LOGS\<PRG NAME>.TXT when that file
//! exists. Normal builds exclude :diag and get the empty variant below.
//! Call it only from rare paths (startup, layout, fetch, bar re-render): the argument string
//! is still built in normal builds, and string building is slow on watch interpreters.
(:diag)
module Diag {
    function log(msg as Lang.String) as Void {
        Sys.println(Sys.getTimer().toString() + " " + msg);
    }
}

(:nodiag)
module Diag {
    function log(msg as Lang.String) as Void {}
}
