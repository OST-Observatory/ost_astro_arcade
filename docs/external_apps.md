# External apps in the OST Astro Arcade kiosk

The kiosk runs one Godot program, the **hub**, inside the Wayland kiosk compositor
[cage](https://github.com/cage-kiosk/cage). Apps maintained in their own repositories
(currently **NBodyTouch**) are started by the hub as separate processes. While such an app
runs, the hub idles in the background. When the app's process exits, the hub takes over
again.

For this to work on an unattended touch kiosk, an external app must follow these rules.

## Required

1. **Fullscreen at native resolution.** The display is 2560×1440 (iiyama T2755QSC, 27",
   PCAP multi-touch). The hub passes the size as arguments, e.g.
   `--width 2560 --height 1440`. cage shows the newest window fullscreen anyway, but the
   app should render at this size.
2. **Wayland.** No X11-only code paths and no KMS/DRM direct access, because cage owns the
   display. For raylib that means the SDL backend with `SDL_VIDEODRIVER=wayland`, which
   the hub sets.
3. **Touch input.** All functions must work with touch only. No keyboard and no mouse
   are connected.
4. **Exit on inactivity.** After the inactivity timeout, the app must **exit** with code
   0 instead of only resetting itself. Otherwise the kiosk would never return to the
   hub. Suggested for NBodyTouch: a new flag such as `--exit-on-timeout`, used together
   with the existing `--timeout <s>`. The hub passes `--timeout 180`.
5. **Visible way back.** A clearly visible "back/home" button (at least 96 px) that exits
   the app with code 0.
6. **No crash dialogs or terminal prompts.** On fatal errors, write to stderr and exit
   with a non-zero code. The hub logs the error and returns to the menu.

## Optional but nice

- **Language:** the hub sets `ASTRO_LANG=de|en|es`. Please start in that language if it is
  supported.
- **Usage statistics:** not needed. The hub measures session time itself, so please
  don't write to `usage.jsonl`. The old launcher counted every session twice because of
  this.
- **Quick start:** a first frame within about 3 s feels instant. The hub shows a loading
  animation until the app's window appears.

## How the hub calls the app (example)

```
SDL_VIDEODRIVER=wayland ASTRO_LANG=de \
  /opt/ost/external/nbody/nbody_dynamics \
  --root /opt/ost/external/nbody --width 2560 --height 1440 \
  --timeout 180 --exit-on-timeout --quiet
```

The hub enforces a hard limit (default 20 min) and terminates the app if it is exceeded.
That limit is only a safety net and does not replace rule 4.
