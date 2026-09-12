#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import transform_osm_to_game


def _expect_rejected(key: str, raw: str, *, allow_meters: bool = False) -> None:
    parsed = transform_osm_to_game.numeric_tag({key: raw}, key, allow_meters=allow_meters)
    assert parsed is None, f"{key}={raw!r} must fail numeric-tag grammar, got {parsed!r}"


def _expect_value(key: str, raw: str, expected: float, *, allow_meters: bool = False) -> None:
    parsed = transform_osm_to_game.numeric_tag({key: raw}, key, allow_meters=allow_meters)
    assert parsed == expected, (key, raw, parsed, expected)


def main() -> int:
    # Python float() accepts underscores as numeric separators. OSM intake must not:
    # those are implementation-language syntax, not the canonical source grammar.
    for key in ("lanes", "layer", "building:levels"):
        for raw in ("1_0", "+1_0", "1_0.5", "1e1_0"):
            _expect_rejected(key, raw)

    for raw in ("1_0", "1_0 m", "+1_0m", "1e1_0m"):
        _expect_rejected("height", raw, allow_meters=True)

    # Python regex \d and float() both accept Unicode decimal digits. Source-tag
    # grammar must remain ASCII so visually confusable numerals cannot normalize
    # into game geometry while bypassing the intended canonical spelling.
    unicode_numeric_forms = ("１２", "١٢", "१२")
    for key in ("lanes", "layer", "building:levels"):
        for raw in unicode_numeric_forms:
            _expect_rejected(key, raw)
    for raw in ("１２m", "١٢ m", "१२m"):
        _expect_rejected("height", raw, allow_meters=True)

    # Preserve already-supported canonical decimal/scientific forms.
    _expect_value("lanes", "3", 3.0)
    _expect_value("layer", "-1", -1.0)
    _expect_value("building:levels", "3.5", 3.5)
    _expect_value("height", "12", 12.0, allow_meters=True)
    _expect_value("height", "12 m", 12.0, allow_meters=True)
    _expect_value("height", "1.2e1m", 12.0, allow_meters=True)

    print(
        "TRANSFORM_OSM_NUMERIC_TAG_GRAMMAR_OK "
        "python_underscore_syntax_rejected=true unicode_decimal_digits_rejected=true "
        "canonical_numeric_forms_retained=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
