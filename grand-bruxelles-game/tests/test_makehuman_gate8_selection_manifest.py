#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SELECTION = ROOT / "assets/characters/civilians/civ1/gate8_system_asset_selection.json"
EXPECTED_SOURCE_SHA256 = "b542127a8e25547c7c29c19f2d1d2adb9a664c80396ecd694095dbc8028a0107"
EXPECTED_SOURCE_SIZE = 280_737_770
EXPECTED_ASSET_COUNT = 30
MAX_SUBSET_BYTES = 100 * 1024 * 1024
REQUIRED_GROUPS = {
    "skins",
    "hair",
    "clothes",
    "eyebrows",
    "eyelashes",
    "teeth",
    "eyes",
    "eyes_materials",
}


def main() -> int:
    data = json.loads(SELECTION.read_text(encoding="utf-8"))
    source = data["source"]
    groups = data["groups"]

    assert data["schema_version"] == 1
    assert source["sha256"] == EXPECTED_SOURCE_SHA256
    assert source["size_bytes"] == EXPECTED_SOURCE_SIZE
    assert source["license"] == "CC0"
    assert set(groups) == REQUIRED_GROUPS
    assert data["limits"]["max_subset_bytes"] == MAX_SUBSET_BYTES

    assets = [asset for group in groups.values() for asset in group]
    assert len(assets) == EXPECTED_ASSET_COUNT, len(assets)
    assert len(assets) == len(set(assets)), "Gate-8 selection contains duplicate asset names"

    assert len(groups["skins"]) == 8
    assert len(groups["hair"]) >= 6
    assert len(groups["clothes"]) >= 7
    assert groups["eyes"] == ["low-poly"]
    assert groups["eyes_materials"] == ["brown"]
    assert groups["teeth"] == ["teeth_base"]

    print(
        "MAKEHUMAN_GATE8_SELECTION_OK "
        f"assets={len(assets)} max_subset_bytes={MAX_SUBSET_BYTES}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
