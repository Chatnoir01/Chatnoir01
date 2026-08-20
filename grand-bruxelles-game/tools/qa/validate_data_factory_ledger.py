#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / "data/validation/data_factory_validation_ledger.json"

with LEDGER.open(encoding="utf-8") as f:
    d = json.load(f)

assert d["schema"] == "grand-bruxelles-data-factory-validation-v1"
assert d["production_base_sha"] == "245432e538bb52d454dd205c0b7e337fe4db093d"
assert d["main_untouched"] is True

counts = d["counts"]
assert counts["intake_branches_observed"] == 57
assert counts["legacy_asset_intakes_observed"] == 1
assert counts["new_intake_branches_in_current_wave"] == 12
assert counts["current_wave_sources_directly_reverified"] == len(d["current_wave"]) == 13
assert counts["older_intake_branches_total"] == 45
assert counts["older_intake_branches_not_directly_reverified_in_this_pass"] == 44
assert counts["new_intake_branches_in_current_wave"] + counts["older_intake_branches_total"] == counts["intake_branches_observed"]

seen = set()
for row in d["current_wave"]:
    key = (row["branch"], row["family"])
    assert key not in seen, key
    seen.add(key)
    assert row["branch"].startswith("intake/")
    assert row["runtime_authorized"] is False
    assert "SOURCE_VERIFIED" in row["status"]
    assert "ARTIFACT_UNVERIFIED" in row["status"]
    assert "READY_FOR_PROCESSING" not in row["status"]
    assert row.get("evidence"), key

assert d["actions_observability"]["push_runs_visible"] is False
assert "Never label an intake GREEN" in d["actions_observability"]["rule"]
assert "runtime/JOUABLE" in d["promotion_rule"]

print("DATA_FACTORY_VALIDATION_LEDGER_OK")
print("intake_branches", counts["intake_branches_observed"])
print("source_verified_current_wave", len(d["current_wave"]))
print("artifact_verified", 0)
print("ready_for_processing", 0)
