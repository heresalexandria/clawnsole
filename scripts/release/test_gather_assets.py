"""Exercise release completeness, download aliases, and checksum contents."""

import hashlib
from html.parser import HTMLParser
from pathlib import Path
import tempfile
import unittest
from urllib.parse import urlparse

from gather_assets import ASSET_SUFFIXES, DOWNLOAD_SUFFIXES, gather


class DownloadParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.downloads = set()

    def handle_starttag(self, tag, attrs):
        href = dict(attrs).get("href", "")
        if tag == "a" and "/releases/latest/download/" in href:
            self.downloads.add(Path(urlparse(href).path).name)


class GatherAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.incoming = self.root / "incoming"
        self.output = self.root / "release"
        self.incoming.mkdir()
        for suffix in ASSET_SUFFIXES:
            folder = self.incoming / f"build-{suffix}"
            folder.mkdir()
            (folder / f"Clawnsole-1.2.3-{suffix}").write_bytes(suffix.encode())

    def test_complete_release_aliases_and_checksums(self):
        # Unrelated artifacts and stale versions are never published.
        (self.incoming / "Clawnsole-1.2.2-linux-x64.deb").write_bytes(b"old")
        (self.incoming / "private.ipa").write_bytes(b"not a desktop asset")
        gather("1.2.3", self.incoming, self.output)
        expected = {f"Clawnsole-1.2.3-{s}" for s in ASSET_SUFFIXES}
        expected.update(f"Clawnsole-{s}" for s in DOWNLOAD_SUFFIXES)
        self.assertEqual({p.name for p in self.output.iterdir()}, expected | {"SHA256SUMS.txt"})
        checksums = {}
        for line in (self.output / "SHA256SUMS.txt").read_text().splitlines():
            digest, name = line.split("  ")
            checksums[name] = digest
            self.assertEqual(digest, hashlib.sha256((self.output / name).read_bytes()).hexdigest())
        self.assertEqual(set(checksums), expected)
        for suffix in DOWNLOAD_SUFFIXES:
            self.assertEqual(checksums[f"Clawnsole-{suffix}"], checksums[f"Clawnsole-1.2.3-{suffix}"])

    def test_missing_or_empty_architecture_prevents_publication(self):
        asset = next(self.incoming.rglob("Clawnsole-1.2.3-linux-arm64.deb"))
        asset.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "linux-arm64.deb"):
            gather("1.2.3", self.incoming, self.output)
        self.assertFalse(self.output.exists())
        asset.unlink()
        with self.assertRaisesRegex(ValueError, "linux-arm64.deb"):
            gather("1.2.3", self.incoming, self.output)

    def test_duplicate_asset_prevents_publication(self):
        (self.incoming / "Clawnsole-1.2.3-linux-x64.tar.gz").write_bytes(b"duplicate")
        with self.assertRaisesRegex(ValueError, "linux-x64.tar.gz"):
            gather("1.2.3", self.incoming, self.output)
        self.assertFalse(self.output.exists())

    def test_splash_downloads_are_published_aliases(self):
        parser = DownloadParser()
        root = Path(__file__).resolve().parents[2]
        parser.feed((root / "docs/index.html").read_text())
        self.assertEqual(parser.downloads, {f"Clawnsole-{s}" for s in DOWNLOAD_SUFFIXES})


if __name__ == "__main__":
    unittest.main()
