# Glasswood
**Living wallpaper for macOS, looping nature scenes with ambient sound.**

Glasswood replaces your static desktop picture with a looping video that sits behind your icons and keeps playing while you work. Pick a scene from the library, and it fills every connected monitor with matching ambient audio. Video and sound can be toggled independently, so you can keep the crackle of a campfire without the picture, or the picture without the sound.

---

## Features

- **True desktop wallpaper** — video renders at the macOS desktop window level, behind your icons and the Finder, not as a floating window
- **Multi-display** — every connected screen gets its own player automatically, no configuration
- **Independent video / audio toggles** — mute the scene without stopping it, or hide the video and keep the ambience
- **Self-contained** — scenes are bundled inside `Glasswood.app`; nothing outside the app bundle is read at runtime
- **Player bar** — current scene, play/pause, video and audio toggles, and volume, pinned to the bottom of the window
- **Native window behaviour** — resizable, minimizable, full screen with `⌃⌘F`, closes to the Dock without stopping playback

---

## Install

Grab the latest `Glasswood-Vx.y.z.dmg` from [Releases](../../releases), open it, and drag **Glasswood** into Applications. That's the whole install — the scenes are already inside the app, and there's nothing else to download or set up.

Requires macOS 12 Monterey or later.

The app is ad-hoc signed rather than notarized, so macOS will refuse to open it on first launch. Right-click the app → **Open** → **Open** to get past Gatekeeper. You only need to do this once.

---

## Building it yourself

Only needed if you want to change the scene library or the app itself — installing from the DMG above requires none of this.

You'll need the Xcode Command Line Tools (`xcode-select --install`), plus `yt-dlp` and `ffmpeg` (`brew install yt-dlp ffmpeg`) to build the scene library. The finished app has no runtime dependencies.

```bash
git clone https://github.com/pKostantine/Glasswood.git
cd Glasswood

./prep.sh              # download scene clips + generate thumbnails
./build.sh             # compile and bundle everything into Glasswood.app
./installer.sh 1.0.0   # → Glasswood-V1.0.0.dmg
```

`installer.sh` takes the version as its first argument and defaults to `1.0.0`.

### About the scenes

**No video files are included in this repository.** `prep.sh` downloads them to a local `assets/` directory, which is gitignored, and `build.sh` copies them into the app bundle at build time.

The default playlist is [Real Campfire](https://www.youtube.com/playlist?list=PLDLkA3FbT-pZJN_n1pjQuLh2I09mrp9lL) by [Campfire Master](https://www.youtube.com/@CampfireMaster) — his footage, not mine. Downloads are for personal desktop use; builds containing his clips shouldn't be redistributed. To use your own footage instead, edit `PLAYLIST` at the top of `prep.sh`, or drop your own `.mp4` files and thumbnails into `assets/` and write a matching `manifest.json`.

`prep.sh` pulls a five-minute segment starting at the 20-minute mark of each video, which skips channel intros and lands in steadier footage.

### Naming the scenes

`prep.sh` assigns names from a list at the top of the script, in playlist order. They won't necessarily match what's actually in each clip. After the first run, open the generated `assets/*.jpg` thumbnails and edit the `title` fields in `assets/manifest.json`, then re-run `build.sh`. The titles are what the library grid displays.

---

## Project structure

```
Glasswood.swift     Entire application — UI, wallpaper windows, playback
prep.sh             Downloads clips, extracts thumbnails, writes manifest.json
build.sh            Compiles, bundles scenes and icon, produces Glasswood.app
installer.sh        Packages the app into a versioned .dmg
icon.png            1024×1024 source image for the app icon
assets/             Generated. Clips, thumbnails, manifest.json — gitignored
```

Inside the built app, scenes live at `Glasswood.app/Contents/Resources/scenes/`.

### manifest.json

```json
[
  { "id": "scene_01", "title": "Ember Hollow", "video": "scene_01.mp4", "thumb": "scene_01.jpg" }
]
```

Entries whose video file is missing are skipped at launch rather than shown as broken cards.

---

## How it works

Each display gets a borderless `NSWindow` placed at `CGWindowLevelForKey(.desktopWindow)`, which puts it above the static desktop picture but below icons and every other window. The windows are set to `ignoresMouseEvents`, so clicks pass straight through to the desktop, and use `.canJoinAllSpaces` and `.stationary` so the scene persists across Spaces without sliding around during transitions.

Playback is `AVPlayer` reading a local file, with an `AVPlayerItemDidPlayToEndTime` observer that seeks back to zero for a gapless loop. Video and audio are controlled separately: the video toggle changes the player view's alpha while playback continues, so the audio never breaks.

The library window is plain AppKit with no storyboard. The hero banner is drawn in `NSBezierPath` and `NSGradient` rather than loaded from an image, so it scales cleanly and adds nothing to the bundle size.

---

## Troubleshooting

**"Glasswood is damaged and can't be opened"** — Gatekeeper quarantine. Run:

```bash
xattr -cr /Applications/Glasswood.app
```

**The library window is empty** — no scenes were bundled. Run `./prep.sh`, confirm `assets/` contains `.mp4` files and a `manifest.json`, then re-run `./build.sh`.

**Wallpaper disappears after Finder restarts** — quit and relaunch Glasswood, or reselect a scene from the library.

**`prep.sh` skips a video** — it's private, region-locked, or shorter than 25 minutes, so the 20:00–25:00 window doesn't exist. The script logs it and moves on; you'll get fewer scenes.

**No audio** — check the Audio toggle in the player bar, the volume slider, and that the source clip actually has an audio track.

---

## Credits

Default scene footage by [Campfire Master](https://www.youtube.com/@CampfireMaster). Inspired by [Portal](https://portal.app) for macOS.

## License

MIT — see [LICENSE](LICENSE). Covers the application source only. Any video content you add through `prep.sh` remains under its original rights holder's terms.
