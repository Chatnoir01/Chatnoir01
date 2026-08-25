from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/qa/check_gate8_variant01_source_catalog_walk_exhaustion.py"
CONTRACT = ROOT / "data/qa/gate8_variant01_source_catalog_walk_exhaustion.json"

spec = importlib.util.spec_from_file_location("walk_exhaustion", TOOL)
mod = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(mod)


def _inventory() -> dict:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    clips = []
    for row in contract["normal_walk_semantic_candidates"] + contract["lower_swing_non_walk_examples"]:
        clips.append({
            "animation_name": row["animation_name"],
            "max_upper_arm_swing_deg": row["max_upper_arm_swing_deg"],
        })
    index = {row["animation_name"] for row in clips}
    filler = 0
    while len(clips) < contract["inventory_animation_count"]:
        name = f"Synthetic_{filler:02d}"
        filler += 1
        if name in index:
            continue
        clips.append({"animation_name": name, "max_upper_arm_swing_deg": 80.0 + filler})
    return {
        "format": "grand-bruxelles-gate8-variant01-source-arm-swing-inventory-v1",
        "diagnostic_state": "SOURCE_ARM_SWING_INVENTORY_COMPLETE",
        "failures": [],
        "animation_count": len(clips),
        "clips": clips,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "production_authorized": False,
        "activation_ready": False,
        "adoption_ready": False,
    }


def test_contract_accepts_complete_locked_review() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    result = mod.validate(_inventory(), contract)
    assert result["animation_count"] == 46
    assert result["normal_walk_below_threshold"] == []
    assert result["conclusion"] == "NO_LOWER_SWING_SEMANTIC_NORMAL_WALK_IN_PINNED_SOURCE"


def test_rejects_walk_swing_drift() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    inventory = _inventory()
    next(row for row in inventory["clips"] if row["animation_name"] == "Walk")["max_upper_arm_swing_deg"] = 40.0
    try:
        mod.validate(inventory, contract)
    except RuntimeError as exc:
        assert "authored swing drift for Walk" in str(exc)
    else:
        raise AssertionError("Walk swing drift must fail closed")


def test_rejects_alias_or_authorization_opening() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    inventory = _inventory()
    inventory["walk_alias_selected"] = "Walk"
    try:
        mod.validate(inventory, contract)
    except RuntimeError as exc:
        assert "unexpectedly selected an alias" in str(exc)
    else:
        raise AssertionError("alias selection must fail closed")


def main() -> None:
    tests = (
        test_contract_accepts_complete_locked_review,
        test_rejects_walk_swing_drift,
        test_rejects_alias_or_authorization_opening,
    )
    for test in tests:
        test()
    print(f"GATE8_SOURCE_CATALOG_REGRESSIONS_OK tests={len(tests)}")


if __name__ == "__main__":
    main()
