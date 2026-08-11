#!/usr/bin/env python3
"""Resolve the official UrbIS 3D Constructions EPSG:31370 GPKG download.

Datastore Brussels exposes download distributions through Atom feeds which may
contain one or more nested Atom resources before the final binary. This tool
walks that chain without guessing URLs and records every hop for auditability.

It does not download large binaries unless --download is supplied.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

ROOT_ATOM = "https://datastore.brussels/api/atom/bru_urbis/969ea321-c8cd-449a-8eed-d200101bda05/1"
USER_AGENT = "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)"
ATOM_NS = {"atom": "http://www.w3.org/2005/Atom"}


def fetch(url: str, *, timeout: int = 90, max_bytes: int | None = None) -> tuple[bytes, dict[str, str], str]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        final_url = response.geturl()
        headers = {key.lower(): value for key, value in response.headers.items()}
        if max_bytes is None:
            payload = response.read()
        else:
            payload = response.read(max_bytes)
    return payload, headers, final_url


def content_kind(payload: bytes, headers: dict[str, str]) -> str:
    content_type = headers.get("content-type", "").split(";", 1)[0].strip().lower()
    stripped = payload.lstrip()
    if payload.startswith(b"SQLite format 3\x00"):
        return "sqlite"
    if payload.startswith(b"PK\x03\x04"):
        return "zip"
    if "atom" in content_type or stripped.startswith(b"<?xml") or stripped.startswith(b"<feed"):
        try:
            root = ET.fromstring(payload)
            local = root.tag.rsplit("}", 1)[-1]
            if local in {"feed", "entry"}:
                return "atom"
        except ET.ParseError:
            pass
    return content_type or "unknown"


def atom_links(payload: bytes, base_url: str) -> list[dict[str, str]]:
    root = ET.fromstring(payload)
    links: list[dict[str, str]] = []

    def text(element: ET.Element | None) -> str:
        return "" if element is None or element.text is None else element.text.strip()

    entries = root.findall("atom:entry", ATOM_NS)
    if root.tag.rsplit("}", 1)[-1] == "entry":
        entries = [root]

    for entry in entries:
        title = text(entry.find("atom:title", ATOM_NS))
        entry_id = text(entry.find("atom:id", ATOM_NS))
        for link in entry.findall("atom:link", ATOM_NS):
            href = link.attrib.get("href", "").strip()
            if not href:
                continue
            links.append({
                "title": title,
                "entry_id": entry_id,
                "href": urllib.parse.urljoin(base_url, href),
                "rel": link.attrib.get("rel", ""),
                "type": link.attrib.get("type", ""),
                "length": link.attrib.get("length", ""),
            })
    return links


def score_link(link: dict[str, str], require_title_match: bool) -> int:
    title = link.get("title", "").lower()
    href = link.get("href", "").lower()
    media_type = link.get("type", "").lower()
    rel = link.get("rel", "").lower()
    score = 0
    if "31370" in title:
        score += 40
    if "gpkg" in title or "geopackage" in title:
        score += 40
    if require_title_match and score < 80:
        return -1000
    if rel == "enclosure":
        score += 20
    if "zip" in media_type or href.endswith(".zip"):
        score += 12
    if "geopackage" in media_type or href.endswith(".gpkg"):
        score += 15
    if "atom" in media_type or "/atom/" in href:
        score += 8
    if rel in {"self", "alternate"}:
        score += 3
    return score


def resolve(root_url: str, max_depth: int = 6) -> dict[str, Any]:
    chain: list[dict[str, Any]] = []
    current_url = root_url
    visited: set[str] = set()
    require_title_match = True

    for depth in range(max_depth + 1):
        if current_url in visited:
            raise RuntimeError(f"Atom resolution loop at {current_url}")
        visited.add(current_url)

        payload, headers, final_url = fetch(current_url, max_bytes=4 * 1024 * 1024)
        kind = content_kind(payload, headers)
        hop: dict[str, Any] = {
            "depth": depth,
            "requested_url": current_url,
            "final_url": final_url,
            "kind": kind,
            "content_type": headers.get("content-type", ""),
            "content_length": headers.get("content-length", ""),
        }
        chain.append(hop)

        if kind != "atom":
            return {
                "format": "grand-bruxelles-urbis-3d-resolution-v1",
                "root_atom": root_url,
                "resolved_url": final_url,
                "resolved_kind": kind,
                "chain": chain,
            }

        links = atom_links(payload, final_url)
        if not links:
            raise RuntimeError(f"No links found in Atom document {final_url}")

        ranked = sorted(
            ((score_link(link, require_title_match), link) for link in links),
            key=lambda item: item[0],
            reverse=True,
        )
        best_score, best = ranked[0]
        if best_score < 0:
            titles = sorted({link.get("title", "") for link in links if link.get("title")})
            raise RuntimeError(
                "Could not find EPSG:31370 GPKG distribution. Titles: " + " | ".join(titles[:30])
            )

        hop["candidate_count"] = len(links)
        hop["selected"] = best
        hop["selected_score"] = best_score
        current_url = best["href"]
        require_title_match = False

    raise RuntimeError(f"Resolution exceeded max depth {max_depth}")


def safe_filename(url: str, headers: dict[str, str]) -> str:
    disposition = headers.get("content-disposition", "")
    match = re.search(r"filename\*?=(?:UTF-8''|\")?([^\";]+)", disposition, flags=re.IGNORECASE)
    if match:
        name = urllib.parse.unquote(match.group(1)).strip().strip('"')
        if name:
            return Path(name).name
    path_name = Path(urllib.parse.urlparse(url).path).name
    return path_name or "urbis_3d_constructions.bin"


def download(url: str, output_dir: Path) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    output_dir.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(request, timeout=180) as response:
        final_url = response.geturl()
        headers = {key.lower(): value for key, value in response.headers.items()}
        filename = safe_filename(final_url, headers)
        output = output_dir / filename
        with output.open("wb") as handle:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                handle.write(chunk)
    prefix = output.read_bytes()[:64]
    return {
        "path": str(output),
        "bytes": output.stat().st_size,
        "kind": content_kind(prefix, headers),
        "content_type": headers.get("content-type", ""),
        "final_url": final_url,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=ROOT_ATOM)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-depth", type=int, default=6)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--download-dir", type=Path, default=Path("/tmp/urbis-3d"))
    args = parser.parse_args()

    result = resolve(args.root, max_depth=args.max_depth)
    if args.download:
        result["download"] = download(result["resolved_url"], args.download_dir)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
