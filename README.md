# Help! Muizen in 't hotel (Open-Source LÖVE Reimplementation)

An independent, clean-room, open-source reimplementation of the classic 1996 Dutch PC/Mac CD-ROM game **"Help! Muizen in 't hotel"** (Dutch localization of *The Great Green Mouse Disaster*, originally built in Macromedia Director 4), written in Lua for **LÖVE 12.0** targeting **macOS/Desktop** and **Android tablets** (`love-android`).

---

## Legal & Copyright Disclaimer

* **No copyrighted assets are included in this repository.** Original `.DXR`, `.EXE`, `.MOV`, `.AIF`, `.WAV`, and `.BMP` files, as well as converted images, audio, video frames, `.love` archives, and `.apk` builds, are excluded via [.gitignore](file:///Users/273974/Developer/help-muizen-hotel/.gitignore).
* **You must supply your own legal copy** of the original game and run the local conversion script to generate `assets/` on your machine.
* All code in `src/` and `tools/` is an independent clean-room implementation.

---

## Design Philosophy

* **Faithful yet modern:** Preserves the original `640×480` artwork, Director palettes/transparency, animations, QuickTime intro/room clips, sound effects, and gameplay flow while replacing 1990s Win16/QuickTime 2.0 limitations with crisp aspect-preserving scaling, safe-area support, reliable audio queuing, and unified mouse + touch controls.
* **Pure-Python asset extraction:** [tools/director.py](file:///Users/273974/Developer/help-muizen-hotel/tools/director.py) decodes Macromedia Director 4 (`RIFX`/`XFIR` `MV93`) bitmaps, palettes, Macintosh `snd ` resources, score timelines, and projector movies directly, while [tools/convert_assets.py](file:///Users/273974/Developer/help-muizen-hotel/tools/convert_assets.py) transcodes audio and `.MOV` cutscenes with `ffmpeg`.

---

## Prerequisites

* **LÖVE 12.0** (also tested on LÖVE 11.5 via `love.getVersion()` guard in [conf.lua](file:///Users/273974/Developer/help-muizen-hotel/conf.lua))
* **Python 3** with **Pillow** (`pip install pillow`)
* **`ffmpeg` and `ffprobe`** on `PATH` (for converting `.AIF`/`.WAV` audio and `.MOV` Apple Graphics `smc` video)

---

## Preparing Your Original Copy (Hybrid CD-ROM Note)

The original 1996 CD-ROM is a **Toast 3.0 Hybrid Mac HFS + ISO 9660** image (`MUIZENCD`). Modern macOS often fails to mount the raw `.iso` (`Device not configured`) because Toast placed a legacy Apple Driver Descriptor Map (`ER`) and Apple Partition Map (`PM`) inside the first 32 KB pointing to a Classic `Apple_HFS` partition.

* **Mounting on modern macOS:** Copying the ISO 9660 volume span (`VolumeSpaceSize * 2048`) with the first `32768` bytes zeroed produces a standard mountable ISO 9660 image without modifying your original backup.
* **Extracting files:** When extracting from the ISO 9660 tree, skip ISO 9660 associated resource-fork entries (`flags & 0x04`) so they do not overwrite the data forks of `DUTHELP/*.MOV`, `DUTVIDEO/ENGINTRO.MOV`, and `MUIZEN.BMP`.

---

## Converting Local Assets

Run the multi-threaded asset converter against your extracted CD-ROM directory:

```bash
python3 tools/convert_assets.py --source <originele-map> --output assets
```

For example, if extracted into `backup/extracted`:

```bash
python3 tools/convert_assets.py --source backup/extracted --output assets
```

### Options

* `--source <dir>`: Path to the extracted original game files (case-insensitive lookup; default: `backup/extracted`).
* `--output <dir>`: Destination directory for converted `.png`, `.wav`, video frame sequences, `dxr/*/score.lua`, and `manifest.lua` (default: `assets`).
* `--workers <n>`: Number of parallel conversion threads (default: CPU count).
* `--skip-videos`: Skip `.MOV` frame/audio extraction for quick testing.
* `--video-quality <q>`: `ffmpeg` JPEG `q:v` quality (`2` = highest quality, `8` = smaller size; default: `4`).

### Asset Search Order

At startup, [src/core/assets.lua](file:///Users/273974/Developer/help-muizen-hotel/src/core/assets.lua) looks for `manifest.lua` in this order:

1. Environment variable `MUIZEN_ASSETS_DIR`
2. Gitignored `local_config.lua` (`assets_dir = "..."`; see [local_config.example.lua](file:///Users/273974/Developer/help-muizen-hotel/local_config.example.lua))
3. Project/bundled `assets/` via `love.filesystem`
4. LÖVE user save directory (`<save-dir>/assets/`), useful for side-loading on Android

If no assets are found, the game launches [src/states/missing_assets.lua](file:///Users/273974/Developer/help-muizen-hotel/src/states/missing_assets.lua) with instructions, checked paths, and Retry (`R`) / Quit (`Esc`) actions.

---

## Running & Controls

Launch from the repository root:

```bash
love .
```

### Global Controls

| Input | Action |
| :--- | :--- |
| **Mouse / Touch** | Point, hover (desktop), tap/click hotzones |
| **`F1`** | Toggle hotzone & virtual-coordinate debug overlay |
| **`F2`** | Toggle `linear` / `nearest` canvas scaling filter |
| **`F11`** | Toggle fullscreen |
| **`Esc`** | Context-aware back / save-and-quit dialog |
| **`R`** | Retry asset loading (on Missing Assets screen) |

---

## Project Status & Roadmap

* **Milestone 1 (Implemented):**
  * Asset converter (`tools/director.py`, `tools/convert_assets.py`)
  * Core engine (`viewport`, `assets`, `audio_queue`, `cursor`, `hotzone`, `scene_manager`, `video_player`, `director_stage`, `confirm_dialog`, `save`)
  * Missing-assets screen, CD-ROM Launcher, Intro video (`engintro`), Options/Start Menu (`GGMDMENU`), Hotel Hub with live Mouse-Detector TV scanner + Fat Lazy Cat hint video (`cathelp6`), and playable **De Galerij** (`GALERIJ.EXE`)
* **Milestone 2 (Next):** All 20 interactive hotel rooms (`ATTIC.DXR` + 19 standard rooms), hiding-spot animations, catching running mice, mousetrap bag (`10`/`5`/`0` traps), and room hints
* **Milestone 3:** Backstage instrument matching (`INSTRUM.DXR`), cumulative orchestra rehearsal (`ORCH.DXR`), finale (`THEEND.DXR` / `ENDSEQ.MOV`), and credits (`EXIT.DXR` / `CREDITS.DXR`)
* **Milestone 4:** Save/resume polish & edge-case tuning for touch/desktop
* **Milestone 5:** Bonus modes (**Het Muizendoolhof** & **Super Spel**) and Android packaging (`scripts/build_android.sh` with `love-android`, launcher icons, and `sensorLandscape` orientation lock)

---

## Android Tablet Packaging (Planned in Milestone 5)

The engine is already configured in [conf.lua](file:///Users/273974/Developer/help-muizen-hotel/conf.lua) and [main.lua](file:///Users/273974/Developer/help-muizen-hotel/main.lua) for Android tablets (`t.externalstorage = true`, `t.modules.touch = true`, fullscreen mobile launch, `love.window.getSafeArea()`, and touch-mode hover suppression). Packaging helpers (`scripts/build_android.sh` supporting bundled `.love` or `--no-assets` side-loading to `<save-dir>/assets/` and `--build-apk` via `love-android`) will be added in Milestone 5.
