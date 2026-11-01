# Tablet app (Android)

The same Godot project, exported for Android tablets (landscape, arm64). Android starts it
in *app mode* (`Settings.app_mode`; on the desktop: `OST_APP=1`), which changes a few kiosk
defaults:

- language from the system (de/en/es, otherwise English)
- no idle countdown in the games (the hub's attract mode stays)
- no feedback button (it can be switched on in the admin menu)
- 3D quality "low" (FSR upscaling; the admin menu can raise it)
- no external apps (NBodyTouch), no watchdog heartbeat, "App beenden" instead of shutdown
- the back button closes a dialog, asks before leaving a game, and quits from the hub

Rendering uses Godot's *Mobile* renderer (`rendering_method.mobile`). The layout is made for
16:9; on 16:10 or 4:3 tablets it is shown with bars (`stretch/aspect.mobile="keep"`).

## One-time setup

```bash
android/setup.sh
```

This puts JDK 17 and the Android SDK into `~/.local/opt`, Godot's Android templates next to
the Linux ones, creates a debug keystore and writes the paths into Godot's editor settings.
The Android SDK licence is shown in the terminal and must be accepted there.

## Build and install

```bash
android/build.sh             # build/android/ost_space_lab.apk (debug-signed)
android/build.sh --install   # also install and start it on a tablet connected by USB
```

For `--install` turn on *Developer options → USB debugging* on the tablet. Without USB, copy
the APK to the tablet and open it there (allow "install unknown apps" for the file manager).

## Before sharing the app more widely

- Release signing: a release keystore of our own (keep it and its password safe; updates
  need the same key), then `--export-release`.
- The OST gallery images are CC BY-NC-SA: free, ad-free distribution only, credits in the
  app's info panel.
