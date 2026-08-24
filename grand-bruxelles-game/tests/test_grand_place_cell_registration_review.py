#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "grand-bruxelles-game"
SCRIPT = GAME / "tools/qa/review_grand_place_cell_registration.py"
spec = importlib.util.spec_from_file_location("registration_review", SCRIPT)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def main() -> int:
    municipality_lock = GAME / "data/provenance/grand_place_road_cell_municipality.measurement.json"
    locked_path = GAME / "data/provenance/grand_place_cell_registration.review.json"
    generated = mod.review(ROOT, municipality_lock)
    locked = json.loads(locked_path.read_text(encoding="utf-8"))

    assert generated == locked
    assert generated["status"] == "SPATIAL_IDENTITY_MISMATCH_HOLD"
    assert generated["semantic_sha256"] == "bcdfd4bce0eefd422f39cd9aab1fc2387416c3688566bf524083d1f7e237b520"
    assert generated["target"]["cell_id"] == "bxl-e148000-n170000-s500"
    assert generated["target"]["treat_as_grand_place"] is False
    assert generated["expected_grand_place_target"]["cell_id"] == "bxl-e148500-n170500-s500"
    assert generated["expected_grand_place_target"]["authoritative_source_manifest_present"] is False
    assert generated["expected_grand_place_target"]["canonical_manifest_present"] is False
    assert generated["authoritative_source_evidence"]["manifest_sha256"] == "4c18e124adfbdb230fcd357c444f58c1d532db2812f77d6f97380676f60e00c7"
    assert generated["authoritative_source_evidence"]["source_digest"] == "bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb"
    for key in mod.RAILS:
        assert generated[key] is False, key

    print(
        "GRAND_PLACE_CELL_REGISTRATION_REVIEW_SPATIAL_HOLD_LOCKED_EXACT: "
        f"semantic_sha256={generated['semantic_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
