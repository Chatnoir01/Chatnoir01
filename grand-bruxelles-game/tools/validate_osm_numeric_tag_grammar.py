#!/usr/bin/env python3
"""Fail-closed grammar check for numeric OSM tags consumed by the game transform."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

NUMERIC_TAGS = {"lanes", "layer", "height", "building:levels"}
PLAIN_NUMBER = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
METER_NUMBER = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?(?:\s*m)?$", re.IGNORECASE)


def valid_numeric_tag(key: str, raw: str) -> bool:
    text = raw.strip()
    pattern = METER_NUMBER if key == "height" else PLAIN_NUMBER
    return bool(pattern.fullmatch(text))


def validate(payload: dict) -> None:
    elements = payload.get("elements")
    if not isinstance(elements, list):
        raise ValueError("elements must be a list")
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
        "lanes": ["1_0", "0x10", "1 lane", "nan", "inf"],
        "layer": ["1_0", "--1", "1 layer"],
        "height": ["1_0", "12ft", "0x10m", "nan m"],
        "building:levels": ["1_0", "three", "0x3"],
    }
    for key, values in accepted.items():
        for value in values:
            assert valid_numeric_tag(key, value), (key, value)
    for key, values in rejected.items():
        for value in values:
            assert not valid_numeric_tag(key, value), (key, value)
    print("osm_numeric_tag_grammar_self_test=true")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    payload = json.loads(args.source.read_text(encoding="utf-8"))
    validate(payload)
    print("osm_numeric_tag_grammar_valid=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
