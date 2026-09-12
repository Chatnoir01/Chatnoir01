#!/usr/bin/env python3
"""Fail-closed grammar check for numeric OSM tags consumed by the game transform.

The transform is the single source of truth for accepted numeric syntax. This
helper can self-test that shared grammar and, when given an actual raw Overpass
JSON document, reject ambiguous numeric tags before conversion.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from transform_osm_to_game import valid_osm_numeric_tag

NUMERIC_TAGS = {
    "lanes": False,
    "layer": False,
    "height": True,
    "building:levels": False,
}


def valid_numeric_tag(key: str, raw: str) -> bool:
    return valid_osm_numeric_tag(raw, allow_meters=NUMERIC_TAGS[key])


def validate(payload: dict) -> None:
    """Validate numeric tags in a raw Overpass payload.

    Deliberately refuses transformed grand-bruxelles-osm-v1 artifacts: those no
    longer contain raw OSM tags, so validating them here would provide false
    provenance assurance.
    """
    if payload.get("format") == "grand-bruxelles-osm-v1":
        raise ValueError("expected raw Overpass JSON, not transformed grand-bruxelles-osm-v1 data")
    elements = payload.get("elements")
    if not isinstance(elements, list):
        raise ValueError("raw Overpass elements must be a list")
    for index, element in enumerate(elements):
        if not isinstance(element, dict):
            continue
        tags = element.get("tags")
        if not isinstance(tags, dict):
            continue
        for key in NUMERIC_TAGS:
            if key not in tags:
                continue
            raw = tags[key]
            if not isinstance(raw, str) or not valid_numeric_tag(key, raw):
                raise ValueError(f"element {index} invalid {key} numeric syntax: {raw!r}")


def self_test() -> None:
    accepted = {
        "lanes": ["1", "2.5", "+3", "1e1"],
        "layer": ["0", "-1", "+2"],
        "height": ["12", "12.5", "12 m", "1.2e1m"],
        "building:levels": ["1", "3.5"],
    }
    rejected = {
        "lanes": ["1_0", "+1_0", "1_0.5", "1e1_0", "0x10", "1 lane", "nan", "inf"],
        "layer": ["1_0", "--1", "1 layer"],
        "height": ["1_0", "1_0 m", "+1_0m", "1e1_0m", "12ft", "0x10m", "nan m"],
        "building:levels": ["1_0", "three", "0x3"],
    }
    for key, values in accepted.items():
        for value in values:
            assert valid_numeric_tag(key, value), (key, value)
    for key, values in rejected.items():
        for value in values:
            assert not valid_numeric_tag(key, value), (key, value)
    print("osm_numeric_tag_grammar_self_test=true shared_transform_grammar=true")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, nargs="?", help="raw Overpass JSON; omit for --self-test only")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if not args.self_test and args.source is None:
        parser.error("provide a raw Overpass source and/or --self-test")
    if args.self_test:
        self_test()
    if args.source is not None:
        payload = json.loads(args.source.read_text(encoding="utf-8"))
        validate(payload)
        print("osm_numeric_tag_grammar_raw_overpass_valid=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
