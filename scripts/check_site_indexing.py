#!/usr/bin/env python3
"""Verify the canonical URL contract for the public Clawnsole site."""

from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
SITE_ORIGIN = "https://clawnsole.app"
SITEMAP_URL = f"{SITE_ORIGIN}/sitemap.xml"
EXPECTED_PAGES = {
    "index.html": f"{SITE_ORIGIN}/",
    "privacy/index.html": f"{SITE_ORIGIN}/privacy/",
    "tos/index.html": f"{SITE_ORIGIN}/tos/",
}


class CanonicalParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.urls: list[str] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if tag != "link":
            return

        values = dict(attrs)
        relations = (values.get("rel") or "").lower().split()
        if "canonical" in relations and values.get("href"):
            self.urls.append(values["href"] or "")


def check_html_canonicals() -> list[str]:
    errors: list[str] = []
    for relative_path, expected_url in EXPECTED_PAGES.items():
        parser = CanonicalParser()
        parser.feed((DOCS / relative_path).read_text(encoding="utf-8"))
        if parser.urls != [expected_url]:
            errors.append(
                f"{relative_path}: expected one canonical URL {expected_url!r}, "
                f"found {parser.urls!r}"
            )
    return errors


def check_sitemap() -> list[str]:
    root = ET.parse(DOCS / "sitemap.xml").getroot()
    namespace = {"sitemap": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    actual_urls = [
        element.text or ""
        for element in root.findall("sitemap:url/sitemap:loc", namespace)
    ]
    expected_urls = list(EXPECTED_PAGES.values())
    if actual_urls != expected_urls:
        return [
            f"sitemap.xml: expected canonical URLs {expected_urls!r}, "
            f"found {actual_urls!r}"
        ]
    return []


def check_robots() -> list[str]:
    directives = {
        line.strip()
        for line in (DOCS / "robots.txt").read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    required = {"User-agent: *", "Allow: /", f"Sitemap: {SITEMAP_URL}"}
    missing = sorted(required - directives)
    if missing:
        return [f"robots.txt: missing directives {missing!r}"]
    return []


def check_cname() -> list[str]:
    cname = (DOCS / "CNAME").read_text(encoding="utf-8").strip()
    expected = SITE_ORIGIN.removeprefix("https://")
    if cname != expected:
        return [f"CNAME: expected {expected!r}, found {cname!r}"]
    return []


def main() -> int:
    errors = (
        check_html_canonicals()
        + check_sitemap()
        + check_robots()
        + check_cname()
    )
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print(f"Verified {len(EXPECTED_PAGES)} canonical site URLs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
