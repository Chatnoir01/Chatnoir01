#!/usr/bin/env python3
"""Select a preferred UrbIS distribution and resolve nested Atom feeds.

Parent-entry tokens and actual-file tokens are intentionally distinct: an Atom entry may
advertise several formats at once (DWG,GPKG,SHP,SKP), while each resolved file is only one
format/municipality/date. `--prefer-latest` selects the newest YYYYMMDD-stamped file after
all candidate filters have been applied.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

USER_AGENT = "GrandBruxellesGame/0.8 distribution-selector (+github.com/Chatnoir01/Chatnoir01)"
DIRECT_SUFFIXES = (".zip", ".gpkg")
DATE_RE = re.compile(r"(?<!\d)(20\d{6})(?!\d)")


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def text_child(node: ET.Element, name: str) -> str | None:
    for child in node:
        if local_name(child.tag) == name and child.text:
            value = child.text.strip()
            if value:
                return value
    return None


def fetch_xml(url: str) -> ET.Element:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response:
        return ET.fromstring(response.read())


def xml_links(node: ET.Element) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    for element in node.iter():
        if local_name(element.tag) != "link":
            continue
        href = element.attrib.get("href")
        if not href:
            continue
        item = {"href": href}
        for key in ("rel", "type", "title", "hreflang", "length"):
            value = element.attrib.get(key)
            if value:
                item[key] = value
        result.append(item)
    return result


def is_direct(href: str) -> bool:
    clean = href.lower().split("?", 1)[0]
    return clean.endswith(DIRECT_SUFFIXES)


def is_xml(href: str, link_type: str = "") -> bool:
    clean = href.lower().split("?", 1)[0]
    return clean.endswith(".xml") or "atom" in link_type.lower() or "xml" in link_type.lower()


def direct_score(link: dict[str, str]) -> tuple[int, int]:
    href = link["href"].lower().split("?", 1)[0]
    suffix_score = 2 if href.endswith(".zip") else 1
    rel_score = 1 if link.get("rel", "").lower() in {"enclosure", "alternate", "section"} else 0
    return (suffix_score, rel_score)


def candidate_haystack(link: dict[str, str]) -> str:
    return " ".join(str(link.get(key, "")) for key in ("href", "title", "type", "rel")).casefold()


def candidate_date(link: dict[str, str]) -> str:
    matches = DATE_RE.findall(candidate_haystack(link))
    return max(matches) if matches else "00000000"


def filter_candidates(candidates: list[dict[str, str]], candidate_tokens: list[str]) -> list[dict[str, str]]:
    folded_tokens = [token.casefold() for token in candidate_tokens if token.strip()]
    if not folded_tokens:
        return list(candidates)
    return [candidate for candidate in candidates if all(token in candidate_haystack(candidate) for token in folded_tokens)]


def choose_candidate(candidates: list[dict[str, str]], prefer_latest: bool = False) -> dict[str, str] | None:
    if not candidates:
        return None
    ranked = list(candidates)
    if prefer_latest:
        ranked.sort(key=lambda link: (candidate_date(link), direct_score(link)), reverse=True)
    else:
        ranked.sort(key=direct_score, reverse=True)
    return ranked[0]


def resolve_links(initial_links: list[dict[str, str]], max_depth: int = 3) -> dict[str, Any]:
    queue: list[tuple[str, int]] = []
    visited: set[str] = set()
    chain: list[dict[str, Any]] = []
    direct: list[dict[str, str]] = [link for link in initial_links if is_direct(link["href"])]
    for link in initial_links:
        if is_xml(link["href"], link.get("type", "")):
            queue.append((link["href"], 1))
    while queue:
        url, depth = queue.pop(0)
        if url in visited or depth > max_depth:
            continue
        visited.add(url)
        try:
            root = fetch_xml(url)
        except Exception as exc:
            chain.append({"url": url, "depth": depth, "error": repr(exc)})
            continue
        links = xml_links(root)
        entries = [element for element in root.iter() if local_name(element.tag) == "entry"]
        chain.append({"url": url, "depth": depth, "title": text_child(root, "title"), "entry_count": len(entries), "link_count": len(links)})
        for link in links:
            if is_direct(link["href"]):
                direct.append(link)
            elif is_xml(link["href"], link.get("type", "")) and link["href"] not in visited:
                queue.append((link["href"], depth + 1))
    dedup: dict[str, dict[str, str]] = {link["href"]: link for link in direct}
    candidates = list(dedup.values())
    candidates.sort(key=direct_score, reverse=True)
    return {"direct_candidates": candidates, "resolution_chain": chain}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source-id", required=True)
    parser.add_argument("--token", action="append", default=[])
    parser.add_argument("--candidate-token", action="append", default=[])
    parser.add_argument("--prefer-latest", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    data = json.loads(args.input.read_text(encoding="utf-8"))
    feed = next((item for item in data.get("feeds", []) if item.get("source_id") == args.source_id), None)
    if feed is None:
        raise SystemExit(f"Source not found: {args.source_id}")
    tokens = [token.casefold() for token in args.token]
    matches: list[dict[str, Any]] = []
    for entry in feed.get("entries", []):
        title = str(entry.get("title") or "")
        if all(token in title.casefold() for token in tokens):
            matches.append(entry)
    if not matches:
        titles = [entry.get("title") for entry in feed.get("entries", [])]
        raise SystemExit(f"No entry matched tokens {args.token!r}. Titles: {titles!r}")
    matches.sort(key=lambda item: len(str(item.get("title") or "")))
    chosen_entry = matches[0]
    resolved = resolve_links(chosen_entry.get("links", []))
    all_candidates = resolved["direct_candidates"]
    candidates = filter_candidates(all_candidates, args.candidate_token)
    selected = choose_candidate(candidates, args.prefer_latest)
    if selected is None:
        raise SystemExit(
            "Matched distribution entry but no direct ZIP/GPKG link satisfied the candidate filters. "
            f"candidate_tokens={args.candidate_token!r}; all_candidates={[item.get('href') for item in all_candidates]!r}; "
            f"chain={resolved['resolution_chain']!r}"
        )
    output = {
        "schema": 3,
        "source_id": args.source_id,
        "tokens": args.token,
        "candidate_tokens": args.candidate_token,
        "prefer_latest": args.prefer_latest,
        "feed_url": feed.get("feed_url"),
        "matched_entry_title": chosen_entry.get("title"),
        "matched_entry_updated": chosen_entry.get("updated"),
        "matched_entry_links": chosen_entry.get("links", []),
        "selected": selected,
        "selected_embedded_date": candidate_date(selected),
        "direct_candidates": all_candidates,
        "filtered_candidates": candidates,
        "resolution_chain": resolved["resolution_chain"],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Selected:", selected["href"], "date=", output["selected_embedded_date"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
