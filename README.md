# OST Astro Arcade

Touch kiosk with astronomy games of the **OST** student observatory ("Overwhelmingly Small
Telescope"), Universität Potsdam, Campus Golm. It replaces `astro_mini_games` (Kivy) and
`asteroid_game` (C++/GLES2 + Python).

- Engine: **Godot 4.7.2** (Forward+, Vulkan); one program (hub + games as scenes)
- Target: NiPoGi E3B mini PC (Ryzen 5 7430U, Vega 7) with an iiyama T2755QSC (2560×1440 touch),
  running Ubuntu Server 24.04 + cage as kiosk
- Offline data pipeline: Python 3.12 via `uv` in `tools/` (no Python at runtime)

## Layout

| Path | Content |
|---|---|
| `godot/` | Godot project (`core/`, `ui/`, `hub/`, `games/`, `shared/astro/`, `assets/`, `tests/`, `tools/`) |
| `godot/spikes/` | Phase-0 tech tests: multi-touch, PBR + glow, 300k GPU stars |
| `tools/` | Python pipeline (catalogs, scenarios, image prep, brand assets) |
| `blender/` | `.blend` sources and bpy scripts |
| `kiosk/` | Ubuntu kiosk setup, systemd units, deploy |
| `docs/` | Credits/licenses, external-app contract, reference photos |

## Setup

```bash
bash tools/setup_dev_tools.sh          # Godot, Blender LTS, uv -> ~/.local/opt
cd tools && uv sync                    # Python 3.12 env for the pipeline
godot --headless --path godot --import # first import
```

## Everyday commands

```bash
# Unit tests (headless, exit code = failures; optional name filter after --)
godot --headless --path godot -s res://tests/run_tests.gd

# Screenshots at kiosk resolution (needs a GPU/window); prints average FPS
godot --path godot -s res://tools/capture.gd -- res://spikes/galaxy_particles.tscn captures/galaxy 1500 3

# UI states for review (hub, en, es, attract, leaderboard, info, admin, dialog, idle, placeholder)
OST_DATA_DIR=/tmp/ost_capture SCENARIO=attract godot --path godot -s res://tools/capture.gd -- res://tools/scenario.tscn captures/attract

# After adding a new `class_name` script, re-run the import once so Godot registers it.

# Rebuild logo textures from the T-shirt artwork
cd tools && uv run brand/make_logo.py
```

Every third-party asset must be listed in [docs/CREDITS.md](docs/CREDITS.md).
