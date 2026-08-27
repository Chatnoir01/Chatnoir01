#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WITNESS = ROOT / "game/tests/brussels_road_material_player_witness_test.gd"
CONTRACT = ROOT / "data/qa/corridor_road_source_chain.contract.json"

REQUIRED_TARGETS = {
    359177328: "Maurice Lemonnier",
    408211693: "Fonsny",
    411724192: "Auguste Orts",
    13842686: "Amigo",
}


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    assert contract["schema"] == "grand-bruxelles-corridor-road-source-chain-contract-v4"
    source_rel = contract["source_document"]
    source = ROOT / source_rel
    assert source.is_file(), source

    actual_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    locked_sha = contract["source_sha256"]
    assert actual_sha == locked_sha, (actual_sha, locked_sha)

    representatives = {int(item["osm_id"]): item for item in contract["representatives"]}
    for osm_id in REQUIRED_TARGETS:
        assert osm_id in representatives, (osm_id, sorted(representatives))

    witness = WITNESS.read_text(encoding="utf-8")
    path_match = re.search(r'^const SOURCE_PATH := "res://([^\"]+)"$', witness, re.MULTILINE)
    sha_match = re.search(r'^const SOURCE_SHA256 := "([0-9a-f]{64})"$', witness, re.MULTILINE)
    assert path_match, "road material witness SOURCE_PATH missing"
    assert sha_match, "road material witness SOURCE_SHA256 missing"
    assert path_match.group(1) == source_rel, (path_match.group(1), source_rel)
    assert sha_match.group(1) == locked_sha, (sha_match.group(1), locked_sha)

    assert "FileAccess.get_sha256(SOURCE_PATH).to_lower() != SOURCE_SHA256" in witness
    assert 'GB_ROAD_WITNESS_OSM_ID' in witness, "witness must select corridor target through the shared generic harness"
    for osm_id, name_fragment in REQUIRED_TARGETS.items():
        assert str(osm_id) in witness, f"road material witness missing OSM target {osm_id}"
        assert name_fragment in witness, f"road material witness missing name guard {name_fragment}"

    print(
        "ROAD_MATERIAL_SOURCE_LOCK_OK "
        f"source={source_rel} sha256={locked_sha} osm_ids={sorted(REQUIRED_TARGETS)} canonical_contract=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
