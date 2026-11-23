# VivoHeart Garmin IQ Watchface

![Connect IQ SDK](https://img.shields.io/badge/Connect_IQ_SDK-8.4.1-blue?style=flat-square)
![Devices](https://img.shields.io/badge/Devices-34-blue?style=flat-square)
![Languages](https://img.shields.io/badge/Languages-35-green?style=flat-square)

<!-- ![Downloads](https://img.shields.io/badge/CIQ_Store_downloads-38-green?style=flat-square) -->
<!-- ![Github badge](https://developer.garmin.com/static/connect-iq_badge-dark-35b152d2074fb5abd7394662f78d8a4f.svg) -->
 
## Introduction


I've always been a big fan of how the Vivoactive HR displayed its heartrate graph. To me, past efforts felt informative, motivational, and truly earned when they appeared on my watchface. There is a special joy in seeing a large spike due to a run. The repo aims to recreate that charming style with a basic watchface to have the heartrate history visible at all times on round watches.

## Features

- Show the time
- Show 4-6 h of HR history on the main page
- Switch between multiple color schemes: White, Greyscale, Garmin, Viridis, Magma (Font and Bars independent)

## Installation Instructions

- Download from the Garmin IQ Store and you're ready to go!
- Copy the `.prg` file manually to `GARMIN\APPS` on your watch.

## Customization

Configure in Garmin Connect app or Connect IQ Store settings:
- **Font Color Scheme** – White, Greyscale, Garmin, Viridis, or Magma (time display; default: Garmin)
- **Bars Color Scheme** – White, Greyscale, Garmin, Viridis, or Magma (HR history graph; default: Garmin)
- **Bars Position** – Time on Top or Bars on Top (default: Time on Top)
- **Bar Gaps** – None or Default (spacing between HR bars; default: Default)
- **Bar Height** – 50%, 68%, 80%, 90%, or 100% (default: 68%)
- **Font Size** – Small, Default, Large, or Extra Large (default: Default)
- **Font** – ProtoMolecule, OCR Extended, Rockwell Extra Bold, or Sans Bold (default: ProtoMolecule)
- **Font Antialias** – Off or On (default: On)
- **Time Position** – Top or Centered (default: Centered)
- **Time Layout** – Stacked or Side by Side (default: Side by Side)
- **Minutes Color Mode** – Darker Shade or Match Hours (default: Darker Shade)

## Compatibility

Round AMOLED watches at four resolutions. Fonts are designed at 454 px; `deploy.ps1` renders scaled copies for the smaller screens, and the bar count follows the screen width (86 / 79 / 74 / 68 bars, always 6 h).

| Resolution | Device IDs | Models |
|-----------|-----------|--------|
| 454×454 | `epix2pro51mm` `fenix847mm` `fr965` `fr970` `fr57047mm` `venu3` `approachs7047mm` `descentmk351mm` | epix Pro 51 mm, fēnix 8 47/51 mm, Forerunner 965 / 970 / 570 47 mm, Venu 3, Approach S70 47 mm, Descent Mk3i 51 mm |
| 416×416 | `epix2` `epix2pro47mm` `fenix843mm` `fenixe` `fr265` `venu2` `venu2plus` `d2mach1` `d2airx10` `instinct3amoled50mm` | epix Gen 2, epix Pro 47 mm, fēnix 8 43 mm, fēnix E, Forerunner 265, Venu 2 / 2 Plus, D2 Mach 1, D2 Air X10, Instinct 3 AMOLED 50 mm |
| 390×390 | `epix2pro42mm` `fr165` `fr165m` `fr57042mm` `venu3s` `vivoactive5` `vivoactive6` `marq2` `marq2aviator` `approachs50` `approachs7042mm` `descentg2` `descentmk343mm` `instinct3amoled45mm` | epix Pro 42 mm, Forerunner 165 / 570 42 mm, Venu 3S, vívoactive 5 / 6, MARQ Gen 2, Approach S50 / S70 42 mm, Descent G2 / Mk3 43 mm, Instinct 3 AMOLED 45 mm |
| 360×360 | `fr265s` `venu2s` | Forerunner 265S, Venu 2S |

`.\deploy.ps1 -ListDevices` prints the list from `manifest.xml`.

## Performance

Profiled on an epix Pro 51 mm (firmware 27.18) with the benchmark build, µs per call:

| Path | develop (direct draw) | Now |
|------|------:|------:|
| 1 Hz high-power frame | 34,450 | 9,700 |
| Always-on frame (once a minute) | 34,500 | 7,650 |
| Bars on top, 1 Hz frame | 34,000 | 16,650 |
| HR refresh fetch (every ~4 min) | 134,000 | 2,800 |
| Full 6 h fetch (startup only) | 134,000 | 142,000 |
| New HR data: bars re-rendered (every ~4 min) | 77,000 | 81,000 |

What the watch showed per operation: a full-screen blit costs 0.3 ms (opaque) or 1.3 ms (alpha), the time text 5 ms, and drawing the 86 bars 21–26 ms on screen or ~42 ms into a bitmap. So the bars are pre-rendered into a screen-sized bitmap (one for filled, one for always-on outlines) only when the data or a setting changes. With bars behind the time that bitmap is opaque, so its blit also clears the screen. HR history is kept in a ring buffer of absolute time slots, so each refresh reads only the minutes since the last one.

The simulator gets this badly wrong (blits ~33 ms, bars ~8 ms), so don't tune from simulator numbers. On a USB-connected watch:

```powershell
.\scripts\Sideload-Test.ps1 -Kind bench          # installs "VH Bench" (own app id) + empty log file
# select VH Bench, raise your wrist every ~10 s for a minute, reconnect
.\scripts\Sideload-Test.ps1 -Kind bench -Fetch   # prints the BENCH lines
```

`-Kind diag` installs "VH Diag" instead, which logs every startup step for crash hunting. `scripts/Run-Benchmark.ps1` runs the same bench in the simulator.

## Screenshots

| Watchface | Localized Settings |
|-----------|-------------------|
| <img src="images/Screenshot 2026-02-14 143945.png" alt="VivoHeart watchface" width="200"/> | <img src="images/Screenshot 2026-02-14 144104.png" alt="Localized settings" width="200"/> |

## Support

If you encounter any issues or have questions about the VivoHeart watchface, please open an issue on our [GitHub Issues page](https://github.com/r-neuschulz/VivoHeart/issues). For feature requests or contributions, feel free to submit a pull request. 

I'll occasionally check comments on the Garmin IQ Store, too.

## Acknowledgements

- Thanks to [TitanicTurtle](https://apps.garmin.com/en-US/developer/b71882df-2664-4584-893a-e15a21471c4b/apps) for the guidance and support on my first steps
- Shoutout to [Jim_m_58](https://forums.garmin.com/members/jim_5f00_m_5f00_58) for their continuous help and support
- Appreciation to [darrencrotton/SnapshotHR](https://github.com/darrencroton/SnapshotHR) for the initial inspiration, and open sourcing their project
- Time display font: [Protomolecule](https://github.com/ThinkDualBrain/Protomolecule) by Brian J. Hall (free for non-commercial use; inspired by The Expanse) 