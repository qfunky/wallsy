#!/usr/bin/env python3
"""
Wallsy playlist importer.

Builds Navidrome playlists from Exportify CSV files (Spotify exports).
Tracks missing from the library are downloaded from YouTube via SpotFetch,
Navidrome is rescanned, and the playlist is updated.

Usage:
  python3 wallsy_import.py playlist1.csv [playlist2.csv ...] \
      --server http://your-server:4533 --user qfunk --password 'PASS' \
      --music-dir /path/to/navidrome/music \
      [--spotfetch ~/Documents/Projects/spotiloader/SpotFetch] \
      [--format mp3] [--platform ytmusic] [--cookies cookies.txt] \
      [--no-download] [--proxy http://127.0.0.1:1056]

Requires: requests (pip install requests). For downloading also yt-dlp etc. —
run inside SpotFetch's virtualenv or `pip install -r SpotFetch/requirements.txt`.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import secrets
import sys
import time
import unicodedata
from pathlib import Path

import requests

API_VERSION = "1.16.1"
CLIENT = "WallsyImport"


# ---------------------------------------------------------------- Subsonic API

class Subsonic:
    def __init__(self, server: str, user: str, password: str, proxy: str | None):
        self.server = server.rstrip("/")
        self.user = user
        self.password = password
        self.session = requests.Session()
        self._search_cache = {}
        if proxy:
            self.session.proxies = {"http": proxy, "https": proxy}
        else:
            self._autodetect_proxy()

    def _autodetect_proxy(self):
        """Try direct; if unreachable, fall back to the local tailscale HTTP proxy."""
        try:
            self.session.get(self._url("ping"), timeout=4)
            return
        except requests.RequestException:
            pass
        fallback = "http://127.0.0.1:1056"
        self.session.proxies = {"http": fallback, "https": fallback}
        try:
            self.session.get(self._url("ping"), timeout=6)
            print(f"[i] Using proxy {fallback} to reach the server.")
        except requests.RequestException:
            sys.exit("[!] Server unreachable directly and via 127.0.0.1:1056. "
                     "Run ts-start or pass --proxy.")

    def _url(self, endpoint: str) -> str:
        return f"{self.server}/rest/{endpoint}"

    def _auth(self) -> dict:
        salt = secrets.token_hex(8)
        token = hashlib.md5((self.password + salt).encode()).hexdigest()
        return {"u": self.user, "t": token, "s": salt,
                "v": API_VERSION, "c": CLIENT, "f": "json"}

    def call(self, endpoint: str, params: dict | None = None, repeated: list | None = None) -> dict:
        query = list(self._auth().items()) + list((params or {}).items()) + (repeated or [])
        r = self.session.get(self._url(endpoint), params=query, timeout=60)
        r.raise_for_status()
        body = r.json()["subsonic-response"]
        if body.get("status") != "ok":
            raise RuntimeError(f"{endpoint}: {body.get('error', {}).get('message', 'unknown error')}")
        return body

    def search_songs(self, query: str, count: int = 12) -> list:
        key = (query, count)
        if key in self._search_cache:
            return self._search_cache[key]
        body = self.call("search3", {"query": query, "songCount": count,
                                     "albumCount": 0, "artistCount": 0})
        songs = body.get("searchResult3", {}).get("song", []) or []
        self._search_cache[key] = songs
        return songs

    def playlists(self) -> list:
        return self.call("getPlaylists").get("playlists", {}).get("playlist", []) or []

    def create_or_replace_playlist(self, name: str, song_ids: list):
        existing = next((p for p in self.playlists() if p["name"] == name), None)
        # Keep requests short enough for servers and reverse proxies that limit
        # URL length. createPlaylist replaces the existing contents in Navidrome.
        repeated = [("songId", sid) for sid in song_ids[:75]]
        if existing:
            self.call("createPlaylist", {"playlistId": existing["id"]}, repeated)
            playlist_id = existing["id"]
        else:
            response = self.call("createPlaylist", {"name": name}, repeated)
            playlist_id = response.get("playlist", {}).get("id")
            if not playlist_id:
                playlist_id = next(p["id"] for p in self.playlists() if p["name"] == name)
        for offset in range(75, len(song_ids), 75):
            self.call("updatePlaylist", {"playlistId": playlist_id},
                      [("songIdToAdd", sid) for sid in song_ids[offset:offset + 75]])

    def star_songs(self, song_ids: list):
        for offset in range(0, len(song_ids), 75):
            self.call("star", repeated=[("id", sid) for sid in song_ids[offset:offset + 75]])

    def start_scan(self):
        self.call("startScan")

    def wait_for_scan(self, timeout: int = 600):
        start = time.time()
        while time.time() - start < timeout:
            status = self.call("getScanStatus").get("scanStatus", {})
            if not status.get("scanning", False):
                self._search_cache.clear()
                return
            time.sleep(3)
        print("[!] Scan timed out; continuing anyway.")


# ---------------------------------------------------------------- matching

NOISE = re.compile(
    r"\s*[\(\[][^)\]]*(remaster|remastered|feat\.|with |bonus|deluxe|edit|version|mono|stereo|live)[^)\]]*[\)\]]"
    r"|\s*-\s*\d{4}\s*remaster(ed)?.*$"
    r"|\s*-\s*(remaster(ed)?|single version|radio edit|mono|stereo).*$",
    re.IGNORECASE,
)

def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text or "")
    text = NOISE.sub("", text)
    text = re.sub(r"[^\w\s]", " ", text.lower())
    return re.sub(r"\s+", " ", text).strip()


def best_match(track: dict, candidates: list) -> str | None:
    """Returns the matched song id or None."""
    want_title = normalize(track["title"])
    want_artist = normalize(track["artist"])
    want_album = normalize(track.get("album", ""))
    want_ms = track.get("duration_ms")

    best, best_score = None, 0.0
    for c in candidates:
        got_title = normalize(c.get("title", ""))
        got_artist = normalize(c.get("artist", ""))
        score = 0.0
        title_score = 0.0
        artist_score = 0.0
        if got_title == want_title:
            title_score = 2
        elif want_title and (want_title in got_title or got_title in want_title):
            title_score = 1.2
        if got_artist == want_artist:
            artist_score = 2
        elif want_artist and (want_artist in got_artist or got_artist in want_artist):
            artist_score = 1.2
        # Duration alone must never turn a different artist into a match.
        if not title_score or not artist_score:
            continue
        score += title_score + artist_score
        if want_album and normalize(c.get("album", "")) == want_album:
            score += 0.4
        if want_ms and c.get("duration"):
            if abs(c["duration"] - want_ms / 1000) <= 15:
                score += 0.5
        if score > best_score:
            best, best_score = c, score
    return best["id"] if best is not None and best_score >= 2.4 else None


def find_song(api: Subsonic, track: dict) -> str | None:
    for query in (f"{track['title']} {track['artist']}", track["title"]):
        match = best_match(track, api.search_songs(query))
        if match:
            return match
    return None


# ---------------------------------------------------------------- CSV

def read_exportify_csv(path: Path) -> list:
    tracks = []
    with open(path, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            title = (row.get("Track Name") or "").strip()
            artists = (row.get("Artist Name(s)") or "").strip()
            if not title or not artists:
                continue
            primary = artists.split(";")[0].strip()
            duration = row.get("Duration (ms)")
            tracks.append({
                "title": title,
                "artist": primary,
                "all_artists": artists.replace(";", ", "),
                "album": (row.get("Album Name") or "").strip(),
                "duration_ms": int(duration) if duration and duration.isdigit() else None,
            })
    return tracks


def emit(event: str, **details):
    """Machine-readable progress for the macOS app; ordinary logs stay readable."""
    print("WALLSY_EVENT " + json.dumps({"event": event, **details}), flush=True)


def report_path(csv_path: Path, report_dir: Path) -> Path:
    key = hashlib.sha256(str(csv_path.resolve()).encode()).hexdigest()[:20]
    return report_dir / f"{key}.json"


def save_report(path: Path, report: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description="Import Exportify CSVs as Navidrome playlists.")
    ap.add_argument("csvs", nargs="+", help="CSV files (Exportify format)")
    ap.add_argument("--server", required=True)
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", default=os.environ.get("WALLSY_PASSWORD"),
                    help="or set WALLSY_PASSWORD env var (safer: not visible in ps)")
    ap.add_argument("--music-dir", help="Navidrome music folder (downloads land here)")
    ap.add_argument("--spotfetch", default=os.path.expanduser("~/Documents/Projects/spotiloader/SpotFetch"))
    ap.add_argument("--format", default="mp3", choices=["mp3", "m4a", "flac"])
    ap.add_argument("--platform", default="youtube", choices=["youtube", "ytmusic"])
    ap.add_argument("--cookies", default=None)
    ap.add_argument("--no-download", action="store_true", help="Only match, never download")
    ap.add_argument("--proxy", default=None, help="HTTP proxy for the server, e.g. http://127.0.0.1:1056")
    ap.add_argument("--report-dir", type=Path,
                    default=Path.home() / "Library/Application Support/Wallsy/Imports")
    ap.add_argument("--retry-missing", action="store_true",
                    help="Retry only unmatched tracks from an earlier import")
    ap.add_argument("--star-liked", action="store_true",
                    help="Star matched tracks from Liked Songs or Saved Tracks CSVs")
    args = ap.parse_args()

    if not args.password:
        sys.exit("[!] No password: pass --password or set WALLSY_PASSWORD.")

    csv_paths = [Path(value) for value in args.csvs]
    for path in csv_paths:
        if not path.is_file():
            sys.exit(f"[!] CSV file not found: {path}")
        with path.open(encoding="utf-8-sig", newline="") as source:
            header = set(next(csv.reader(source), []))
        if not {"Track Name", "Artist Name(s)"}.issubset(header):
            sys.exit(f"[!] {path.name} is not an Exportify playlist CSV (missing Track Name / Artist Name(s)).")

    downloader = None
    if not args.no_download:
        if not args.music_dir:
            sys.exit("[!] --music-dir is required for downloading (or pass --no-download).")
        if not os.path.isdir(args.music_dir) or not os.access(args.music_dir, os.W_OK):
            sys.exit(f"[!] Music folder is missing or not writable: {args.music_dir}")
        if not (Path(args.spotfetch) / "functions.py").is_file():
            sys.exit(f"[!] SpotFetch functions.py not found in {args.spotfetch}")
        sys.path.insert(0, args.spotfetch)
        try:
            from functions import download_from_query  # SpotFetch
            downloader = download_from_query
        except ImportError as e:
            sys.exit(f"[!] Cannot import SpotFetch: {e}. Select its .venv/bin/python3 in Wallsy.")

    api = Subsonic(args.server, args.user, args.password, args.proxy)

    total_missing = 0
    for path in csv_paths:
        playlist_name = path.stem.replace("_", " ").strip()
        tracks = read_exportify_csv(path)
        if not tracks:
            sys.exit(f"[!] {path.name} contains no usable tracks; no playlist was changed.")
        print(f"\n=== {playlist_name}: {len(tracks)} tracks in CSV")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        state_file = report_path(path, args.report_dir)
        previous = {}
        if args.retry_missing and state_file.exists():
            try:
                previous = json.loads(state_file.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                pass
        if (previous.get("digest") == digest and previous.get("server") == args.server
                and previous.get("user") == args.user):
            matched = dict(previous.get("matched", {}))
        else:
            matched = {}
        report = {"csv": str(path.resolve()), "name": playlist_name,
                  "server": args.server, "user": args.user,
                  "digest": digest, "matched": matched}
        emit("playlist", name=playlist_name, total=len(tracks), completed=len(matched))

        missing = []
        processed = len(matched)
        for index, track in enumerate(tracks):
            if str(index) in matched:
                continue
            sid = find_song(api, track)
            if sid:
                matched[str(index)] = sid
            else:
                missing.append(index)
            processed += 1
            save_report(state_file, report)
            emit("progress", name=playlist_name, completed=processed,
                 total=len(tracks), title=track["title"])
        print(f"    matched {len(matched)}, missing {len(missing)}")

        if missing and downloader:
            out_dir = os.path.join(args.music_dir, "Wallsy Imports", playlist_name)
            os.makedirs(out_dir, exist_ok=True)
            for index in missing:
                t = tracks[index]
                print(f"    ↓ downloading: {t['artist']} — {t['title']}")
                try:
                    downloader(
                        {"track_name": t["title"], "artist_name": t["all_artists"]},
                        args.format, output_path=out_dir,
                        cookiefile=args.cookies, platform=args.platform,
                    )
                except Exception as e:
                    print(f"      [!] failed: {e}")

            print("    rescanning library…")
            api.start_scan()
            api.wait_for_scan()

            still_missing = []
            for index in missing:
                sid = find_song(api, tracks[index])
                if sid:
                    matched[str(index)] = sid
                else:
                    still_missing.append(index)
                save_report(state_file, report)
            missing = still_missing

        found_ids = [matched[str(index)] for index in range(len(tracks)) if str(index) in matched]
        if found_ids:
            api.create_or_replace_playlist(playlist_name, found_ids)
            if args.star_liked and normalize(playlist_name) in {"liked songs", "saved tracks", "your liked songs"}:
                api.star_songs(list(dict.fromkeys(found_ids)))
                print(f"    ♥ starred {len(set(found_ids))} matched tracks")
            print(f"    ✔ playlist “{playlist_name}” updated: {len(found_ids)} tracks")
        else:
            print(f"    [!] No tracks matched; playlist “{playlist_name}” was not changed.")
        total_missing += len(missing)
        emit("complete", name=playlist_name, matched=len(found_ids), missing=len(missing))
        if missing:
            print("    Tracks not found (check/download manually):")
            for index in missing:
                t = tracks[index]
                print(f"      • {t['artist']} — {t['title']}")

    emit("finished", missing=total_missing)


if __name__ == "__main__":
    main()
