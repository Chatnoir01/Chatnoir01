#!/usr/bin/env python3
"""Collect candidate Brussels reference images from Wikimedia Commons.

This tool stores metadata only. It does not approve an image for production use.
Every candidate must still be reviewed for license/attribution requirements and
added to assets/LICENSE_REGISTRY.csv before being used in the game.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

API_URL = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "GrandBruxellesGame/0.1 (reference-collector; GitHub Chatnoir01)"


def strip_html(value: str | None) -> str:
    if not value:
        return ""
    value = re.sub(r"<[^>]+>", " ", value)
    return " ".join(html.unescape(value).split())


def api_get(params: dict[str, Any]) -> dict[str, Any]:
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(
        f"{API_URL}?{query}",
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def collect(query: str, limit: int) -> list[dict[str, Any]]:
    payload = api_get(
        {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "generator": "search",
            "gsrsearch": query,
            "gsrnamespace": 6,
            "gsrlimit": max(1, min(limit, 20)),
            "prop": "imageinfo",
            "iiprop": "url|mime|size|extmetadata",
            "iiurlwidth": 1280,
        }
    )

    pages = payload.get("query", {}).get("pages", [])
    results: list[dict[str, Any]] = []

    for page in pages:
        infos = page.get("imageinfo") or []
        if not infos:
            continue
        info = infos[0]
        meta = info.get("extmetadata", {})

        def meta_value(name: str) -> str:
            raw = meta.get(name, {})
            return strip_html(raw.get("value") if isinstance(raw, dict) else "")

        results.append(
            {
                "title": page.get("title", ""),
                "page_id": page.get("pageid"),
                "description_url": info.get("descriptionurl", ""),
                "original_url": info.get("url", ""),
                "preview_url": info.get("thumburl", ""),
                "mime": info.get("mime", ""),
                "width": info.get("width"),
                "height": info.get("height"),
                "artist": meta_value("Artist"),
                "credit": meta_value("Credit"),
                "license_short_name": meta_value("LicenseShortName"),
                "license_url": meta_value("LicenseUrl"),
                "usage_terms": meta_value("UsageTerms"),
                "attribution_required": meta_value("AttributionRequired"),
                "copyrighted": meta_value("Copyrighted"),
                "image_description": meta_value("ImageDescription"),
            }
        )

    results.sort(key=lambda item: item["title"].casefold())
    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Search Wikimedia Commons for Brussels reference images."
    )
    parser.add_argument(
        "query",
        help='Search text, e.g. "Brussels Bourse exterior"',
    )
    parser.add_argument("--limit", type=int, default=12, help="1-20 results")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/reference_candidates.json"),
        help="Output JSON path",
    )
    args = parser.parse_args()

    try:
        results = collect(args.query, args.limit)
    except Exception as exc:  # network/API failure should be visible to the caller
        print(f"error: {exc}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(
            {
                "query": args.query,
                "count": len(results),
                "review_required": True,
                "results": results,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"saved {len(results)} candidates to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
