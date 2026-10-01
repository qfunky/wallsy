<div align="center">

# Wallsy

**A Spotify-style native macOS client for [Navidrome](https://www.navidrome.org/)**

Built with SwiftUI · Apple Silicon only · macOS 14+

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Arch](https://img.shields.io/badge/arch-arm64-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## Features

🎵 **Minimal macOS interface** — charcoal and muted emerald theme, sidebar navigation, home shelves, bottom player bar, compact track lists, adjustable interface zoom (70–130%, ⌘+/⌘−)

▶️ **Player** — gapless streaming via AVPlayer, crossfade (0–12 s, configurable), queue with Play Next / Add to Queue, shuffle, repeat (off / all / one), wrap-around track navigation, media keys and the macOS Now Playing widget with artwork

📚 **Library** — full track list with instant multi-select (⌘/⇧-click), indexed artist browser, search, Liked Songs synced with the server, listening statistics (top tracks / artists / albums, play counts)

🎛 **Playlists** — create from multi-selection or drag-and-drop onto the sidebar, reorder tracks by dragging, remove tracks, custom cover images, create empty playlists via right-click

⬇️ **Offline mode** — download playlists to a local cache (original files, no transcoding), pause and resume downloads, retry transient failures, and keep partial files for resumption. Cached music plays without a network connection.

📥 **Spotify migration** — import multiple [Exportify](https://exportify.app) CSV playlists, match library tracks, optionally fetch missing tracks through [SpotFetch](https://github.com/MrElyazid/SpotFetch), retry only unmatched tracks, and turn a Liked Songs CSV into Navidrome favorites.

🧹 **Server duplicate scan** — scan the connected Navidrome library in Settings. Wallsy downloads only tracks with matching reported file sizes, compares their original bytes with SHA-256, and copies a review report with server song IDs and reported paths. Matching streams can also be two library entries pointing to one file.

🔐 **Sensible security** — password stored in the macOS Keychain only, recent-server history without passwords, Subsonic token auth (the password itself is never sent)

## Screenshots

<!-- Add screenshots here: drag images into this file on GitHub or put them in .github/ -->

## Installation

Grab the latest `Wallsy-*.dmg` from [Releases](../../releases), open it, and drag Wallsy to Applications.

**First launch:** the app is not notarized (no paid Apple Developer account), so macOS will refuse to open it. Either right-click → **Open** → Open, or run:

```bash
xattr -cr /Applications/Wallsy.app
```

If your Navidrome server is on the local network, macOS will ask for **Local Network** permission on first connection — allow it.

## Requirements

- Apple Silicon Mac (M1 or later), macOS 14 Sonoma or newer
- A Navidrome server (or any Subsonic-compatible server with API v1.16.1)
- For CSV matching: Python 3.9+ and `requests`. For auto-download, select a Python environment compatible with your [SpotFetch](https://github.com/MrElyazid/SpotFetch) checkout and install its dependencies (`yt-dlp`, `mutagen`, ffmpeg).

## Building from source

```bash
git clone https://github.com/qfunky/wallsy.git
cd wallsy
xcodebuild -project NaviPlay.xcodeproj -scheme NaviPlay -configuration Release build
```

Or open `NaviPlay.xcodeproj` in Xcode 16+ and press ⌘R. To produce a DMG:

```bash
./scripts/make_dmg.sh
```

## Importing Spotify playlists

1. Export your playlists as CSV with [Exportify](https://exportify.app).
2. In Wallsy, open the **Import** tab.
3. Add the CSV files, point it at your Navidrome music folder and your SpotFetch checkout, pick a format, hit **Run Import**.

Matched tracks are assembled into a playlist immediately; missing ones are downloaded from YouTube, the library is rescanned, and the playlist is updated. The same tool works headless: `tools/wallsy_import.py --help`.

Wallsy saves an import report per CSV and server. It downloads only tracks that do not match the Navidrome library; when every CSV track is already on the server, no files are written to the selected music folder. That folder must be writable from the Mac and scanned by Navidrome (use a mounted server share when Navidrome runs elsewhere). The import summary reports files actually created and tracks still missing. Use **Retry missing** after adding files or fixing download dependencies; already matched tracks keep their original positions. A file named `Liked Songs.csv` or `Saved Tracks.csv` can also populate Navidrome favorites. No Spotify account connection is required.

The bundled importer runs on macOS's Python 3.9. If that interpreter prints an `urllib3` LibreSSL warning, choose a Python environment built with OpenSSL in the Import tab, or use `urllib3<2` in that environment. For downloading, use the Python environment that has SpotFetch's dependencies installed.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Play / Pause | ⇧⌘P (or media keys) |
| Search library | ⌘F |
| Home / Liked Songs | ⌘1 / ⌘2 |
| Toggle queue | ⌘J |
| Next / Previous track | ⌘→ / ⌘← |
| Volume up / down | ⇧⌘↑ / ⇧⌘↓ |
| Toggle shuffle | ⇧⌘S |
| Cycle repeat mode | ⇧⌘R |
| Zoom in / out / reset | ⌘+ / ⌘− / ⌘0 |

## Architecture

```
NaviPlay/
├── Core/
│   ├── SubsonicClient.swift    # Subsonic REST client (token auth, proxy-resilient)
│   ├── PlayerController.swift  # Dual-AVPlayer engine with crossfade
│   ├── DownloadManager.swift   # Offline cache with metadata index
│   ├── AppState.swift          # Session, library, offline mode, covers
│   ├── ImportRunner.swift      # Subprocess runner for the CSV importer
│   └── Keychain.swift
├── Views/                      # SwiftUI views (sidebar, player bar, home, etc.)
└── Resources/wallsy_import.py  # Bundled importer script
```

Wallsy speaks the **Subsonic API** (`v1.16.1`, JSON), so it also works with Airsonic, Gonic, and other Subsonic-compatible servers. Scrobbling is submitted at 50% of a track. Downloads use `format=raw` (original files).

The last queue and playback position are restored paused for the same server account. Navidrome's Subsonic API cannot remove audio files from server storage, so the duplicate scanner only prepares a review report. Check the real server paths before removing files; Navidrome may report virtual paths. Tracks without a reported file size cannot be checked by this scan.

> Note: custom playlist covers are stored locally — the Subsonic API has no endpoint for uploading playlist artwork.

## License

MIT — see [LICENSE](LICENSE).
