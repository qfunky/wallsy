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

import argparse
import csv
import hashlib
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
        body = self.call("search3", {"query": query, "songCount": count,
                                     "albumCount": 0, "artistCount": 0})
        return body.get("searchResult3", {}).get("song", []) or []

    def playlists(self) -> list:
        return self.call("getPlaylists").get("playlists", {}).get("playlist", []) or []

    def create_or_replace_playlist(self, name: str, song_ids: list):
        existing = next((p for p in self.playlists() if p["name"] == name), None)
        repeated = [("songId", sid) for sid in song_ids]
        if existing:
            self.call("createPlaylist", {"playlistId": existing["id"]}, repeated)
        else:
            self.call("createPlaylist", {"name": name}, repeated)

    def start_scan(self):
        self.call("startScan")

    def wait_for_scan(self, timeout: int = 600):
        start = time.time()
        while time.time() - start < timeout:
            status = self.call("getScanStatus").get("scanStatus", {})
            if not status.get("scanning", False):
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
    want_ms = track.get("duration_ms")

    best, best_score = None, 0.0
    for c in candidates:
        got_title = normalize(c.get("title", ""))
        got_artist = normalize(c.get("artist", ""))
        score = 0.0
        if got_title == want_title:
            score += 2
        elif want_title and (want_title in got_title or got_title in want_title):
            score += 1.2
        if got_artist == want_artist:
            score += 2
        elif want_artist and (want_artist in got_artist or got_artist in want_artist):
            score += 1.2
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
    args = ap.parse_args()

    if not args.password:
        sys.exit("[!] No password: pass --password or set WALLSY_PASSWORD.")
    api = Subsonic(args.server, args.user, args.password, args.proxy)

    downloader = None
    if not args.no_download:
        if not args.music_dir:
            sys.exit("[!] --music-dir is required for downloading (or pass --no-download).")
        sys.path.insert(0, args.spotfetch)
        try:
            from functions import download_from_query  # SpotFetch
            downloader = download_from_query
        except ImportError as e:
            sys.exit(f"[!] Cannot import SpotFetch from {args.spotfetch}: {e}")

    for csv_path in args.csvs:
        path = Path(csv_path)
        playlist_name = path.stem.replace("_", " ").strip()
        tracks = read_exportify_csv(path)
        print(f"\n=== {playlist_name}: {len(tracks)} tracks in CSV")

        found_ids, missing = [], []
        for t in tracks:
            sid = find_song(api, t)
            if sid:
                found_ids.append(sid)
            else:
                missing.append(t)
        print(f"    matched {len(found_ids)}, missing {len(missing)}")

        if missing and downloader:
            out_dir = os.path.join(args.music_dir, "Wallsy Imports", playlist_name)
            os.makedirs(out_dir, exist_ok=True)
            for t in missing:
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
            for t in missing:
                sid = find_song(api, t)
                if sid:
                    found_ids.append(sid)
                else:
                    still_missing.append(t)
            missing = still_missing

        api.create_or_replace_playlist(playlist_name, found_ids)
        print(f"    ✔ playlist “{playlist_name}” updated: {len(found_ids)} tracks")
        if missing:
            print("    Tracks not found (check/download manually):")
            for t in missing:
                print(f"      • {t['artist']} — {t['title']}")


if __name__ == "__main__":
    main()
