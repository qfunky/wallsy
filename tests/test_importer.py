"""Offline checks for import continuation and large playlist batching."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "wallsy_import.py"
spec = importlib.util.spec_from_file_location("wallsy_import", SCRIPT)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)


class FakeServer:
    def __init__(self):
        self.available = {"A": "id-a", "C": "id-c"}
        self.queries = []
        self.playlist_ids = []

    def search_songs(self, query):
        self.queries.append(query)
        title = query.split()[0]
        sid = self.available.get(title)
        return [{"id": sid, "title": title, "artist": "Artist"}] if sid else []

    def create_or_replace_playlist(self, name, ids):
        self.playlist_ids = ids


class ImporterTests(unittest.TestCase):
    def test_empty_csv_cannot_replace_existing_playlist(self):
        with tempfile.TemporaryDirectory() as directory:
            csv = Path(directory) / "Existing.csv"
            csv.write_text("Track Name,Artist Name(s)\n", encoding="utf-8")
            server = FakeServer()
            argv = [str(SCRIPT), str(csv), "--server", "http://example.test",
                    "--user", "user", "--password", "secret", "--no-download",
                    "--report-dir", directory]
            with patch.object(importer, "Subsonic", return_value=server), \
                 patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit):
                    importer.main()
            self.assertEqual(server.playlist_ids, [])

    def test_matching_rejects_different_artist_even_with_same_duration(self):
        track = {"title": "Song", "artist": "Original", "duration_ms": 100000}
        candidate = {"id": "wrong", "title": "Song", "artist": "Other",
                     "duration": 100}
        self.assertIsNone(importer.best_match(track, [candidate]))

    def test_matching_rejects_partial_title_artist_and_wrong_duration(self):
        track = {"title": "Клей", "artist": "CUPSIZE", "duration_ms": 146000}
        candidates = [
            {"id": "partial-title", "title": "Клей навсегда", "artist": "CUPSIZE", "duration": 146},
            {"id": "partial-artist", "title": "Клей", "artist": "CUPSIZE2", "duration": 146},
            {"id": "wrong-duration", "title": "Клей", "artist": "CUPSIZE", "duration": 200},
        ]
        self.assertIsNone(importer.best_match(track, candidates))
        self.assertEqual(importer.best_match(track, [
            {"id": "credited", "title": "Клей", "artist": "CUPSIZE, Guest", "duration": 146}
        ]), "credited")

    def test_download_is_not_reported_when_spotfetch_creates_no_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv = root / "Playlist.csv"
            csv.write_text("Track Name,Artist Name(s)\nB,Artist\n", encoding="utf-8")
            spotfetch = root / "SpotFetch"
            spotfetch.mkdir()
            (spotfetch / "functions.py").write_text("", encoding="utf-8")
            server = FakeServer()
            fake_functions = types.SimpleNamespace(download_from_query=lambda *args, **kwargs: None)
            argv = [str(SCRIPT), str(csv), "--server", "http://example.test",
                    "--user", "user", "--password", "secret", "--music-dir", directory,
                    "--spotfetch", str(spotfetch), "--report-dir", directory]
            output = io.StringIO()
            with patch.object(importer, "Subsonic", return_value=server), \
                 patch.dict(sys.modules, {"functions": fake_functions}), \
                 patch.object(sys, "argv", argv), contextlib.redirect_stdout(output):
                result = importer.main()
            self.assertEqual(result, 2)
            self.assertIn("Downloaded 0 of 1", output.getvalue())
            self.assertIn("SpotFetch returned without creating an audio file", output.getvalue())

    def test_existing_server_track_skips_download_explicitly(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv = root / "Playlist.csv"
            csv.write_text("Track Name,Artist Name(s)\nA,Artist\n", encoding="utf-8")
            spotfetch = root / "SpotFetch"
            spotfetch.mkdir()
            (spotfetch / "functions.py").write_text("", encoding="utf-8")
            attempted = []
            fake_functions = types.SimpleNamespace(download_from_query=lambda *args, **kwargs: attempted.append(args))
            argv = [str(SCRIPT), str(csv), "--server", "http://example.test",
                    "--user", "user", "--password", "secret", "--music-dir", directory,
                    "--spotfetch", str(spotfetch), "--report-dir", directory]
            output = io.StringIO()
            with patch.object(importer, "Subsonic", return_value=FakeServer()), \
                 patch.dict(sys.modules, {"functions": fake_functions}), \
                 patch.object(sys, "argv", argv), contextlib.redirect_stdout(output):
                result = importer.main()
            self.assertEqual(result, 0)
            self.assertFalse(attempted)
            self.assertIn("Download skipped: every CSV track matched", output.getvalue())
            self.assertIn("0 downloaded", output.getvalue())

    def test_downloaded_file_is_incomplete_until_navidrome_finds_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            csv = root / "Playlist.csv"
            csv.write_text("Track Name,Artist Name(s)\nB,Artist\n", encoding="utf-8")
            spotfetch = root / "SpotFetch"
            spotfetch.mkdir()
            (spotfetch / "functions.py").write_text("", encoding="utf-8")

            def download(song, format, output_path, **kwargs):
                Path(output_path, "B.mp3").write_bytes(b"audio")

            server = FakeServer()
            server.start_scan = lambda: None
            server.wait_for_scan = lambda: None
            fake_functions = types.SimpleNamespace(download_from_query=download)
            argv = [str(SCRIPT), str(csv), "--server", "http://example.test",
                    "--user", "user", "--password", "secret", "--music-dir", directory,
                    "--spotfetch", str(spotfetch), "--report-dir", directory]
            output = io.StringIO()
            with patch.object(importer, "Subsonic", return_value=server), \
                 patch.dict(sys.modules, {"functions": fake_functions}), \
                 patch.object(sys, "argv", argv), contextlib.redirect_stdout(output):
                result = importer.main()
            self.assertEqual(result, 2)
            self.assertIn("1 downloaded, 1 still missing", output.getvalue())

    def test_retry_only_missing_keeps_original_order(self):
        with tempfile.TemporaryDirectory() as directory:
            csv = Path(directory) / "Playlist.csv"
            csv.write_text(
                "Track Name,Artist Name(s),Duration (ms)\n"
                "A,Artist,100000\nB,Artist,100000\nC,Artist,100000\n",
                encoding="utf-8",
            )
            server = FakeServer()
            argv = [str(SCRIPT), str(csv), "--server", "http://example.test",
                    "--user", "user", "--password", "secret", "--no-download",
                    "--report-dir", directory]
            with patch.object(importer, "Subsonic", return_value=server), \
                 patch.object(sys, "argv", argv), contextlib.redirect_stdout(io.StringIO()):
                importer.main()
            self.assertEqual(server.playlist_ids, ["id-a", "id-c"])

            server.available["B"] = "id-b"
            server.queries.clear()
            with patch.object(importer, "Subsonic", return_value=server), \
                 patch.object(sys, "argv", argv + ["--retry-missing"]), \
                 contextlib.redirect_stdout(io.StringIO()):
                importer.main()
            self.assertEqual(server.playlist_ids, ["id-a", "id-b", "id-c"])
            self.assertTrue(all(query.startswith("B") for query in server.queries))
            reports = list(Path(directory).glob("*.json"))
            self.assertEqual(len(reports), 1)
            self.assertEqual(len(json.loads(reports[0].read_text())["matched"]), 3)

    def test_large_playlist_is_split_into_short_requests(self):
        api = object.__new__(importer.Subsonic)
        calls = []
        api.playlists = lambda: [{"id": "playlist", "name": "Large"}]
        api.call = lambda endpoint, params=None, repeated=None: calls.append(
            (endpoint, params, repeated)
        ) or {}
        api.create_or_replace_playlist("Large", [str(i) for i in range(160)])
        self.assertEqual([entry[0] for entry in calls],
                         ["createPlaylist", "updatePlaylist", "updatePlaylist"])
        self.assertEqual([len(entry[2]) for entry in calls], [75, 75, 10])


if __name__ == "__main__":
    unittest.main()
