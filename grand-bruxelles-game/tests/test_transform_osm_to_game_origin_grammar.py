#!/usr/bin/env python3
"""Regression for fail-closed CLI origin parsing in the OSM transform."""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "transform_osm_to_game.py"
spec = importlib.util.spec_from_file_location("transform_osm_to_game", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def expect_rejected(raw: str) -> None:
    try:
        module.parse_origin(raw)
    except argparse.ArgumentTypeError:
        return
    raise AssertionError(f"origin grammar must reject {raw!r}")


# Python float() accepts underscores even though they are not part of the
# explicit numeric grammar used for source-backed OSM numeric fields.
expect_rejected("5_0.8419,4.3480")
expect_rejected("50.8419,4_3480")
expect_rejected("5_0.8419,4_3480")

assert module.parse_origin("50.8419,4.3480") == (50.8419, 4.348)
assert module.parse_origin("+50.8419,+4.3480") == (50.8419, 4.348)
assert module.parse_origin("5.08419e1,4.348e0") == (50.8419, 4.348)

print("OSM origin numeric grammar regression: PASS")
