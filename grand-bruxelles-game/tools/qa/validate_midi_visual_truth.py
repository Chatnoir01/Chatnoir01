#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "data" / "visual_truth" / "midi"
refs = json.loads((BASE / "midi_station_parvis_reference_registry.json").read_text())
cams = json.loads((BASE / "midi_station_parvis_camera_plan.json").read_text())
gaps = json.loads((BASE / "midi_station_parvis_gap_matrix.json").read_text())

assert refs["zone_id"] == "midi_station_parvis"
assert cams["zone_id"] == refs["zone_id"] == gaps["zone_id"]
assert refs["production_base_sha"] == "245432e538bb52d454dd205c0b7e337fe4db093d"
assert refs["status"] == "HOLD"
assert cams["status"] == "HOLD"
assert gaps["status"] == "HOLD"
assert gaps["realism_complete"] is False
assert gaps["runtime_authorized"] is False
assert gaps["jouable_promotion_authorized"] is False

records = refs["references"]
assert len(records) >= 6
by_id = {x["reference_id"]: x for x in records}
assert len(by_id) == len(records)
assert by_id["midi_fonsny_2016_jacquesverlaeken"]["license"] == "CC BY-SA 4.0"
assert by_id["midi_station_building_2021_japplemedia"]["license"] == "CC BY-SA 4.0"
assert by_id["midi_wide_2023_haydn_blackey"]["license"] == "CC BY-SA 2.0"
assert by_id["midi_sncb_station_current"]["current_visual_truth"] is True

# Current visual truth must not be faked by relabeling old photographs.
for record in records:
    stamp = str(record.get("captured_or_published", ""))
    if stamp[:4].isdigit() and int(stamp[:4]) < 2025 and record.get("source_type") == "wikimedia_commons_photo":
        assert record.get("current_visual_truth") is False, record["reference_id"]

assert len(cams["views"]) == 4
for view in cams["views"]:
    assert view["promotion_blocking"] is True
    assert view["status"] != "GREEN"
    assert view["project_camera_xz"] is None
    assert view["project_target_xz"] is None

blockers = [g for g in gaps["gaps"] if g["severity"] == "BLOCKER"]
assert blockers
assert any(g["id"] == "VT-MIDI-013" and g["state"] == "MISSING" for g in blockers)
assert any(g["id"] == "VT-MIDI-014" and g["state"] == "UNREVIEWED" for g in blockers)

# RED proof: a future promotion must have current photo evidence on all four major faces.
current_player_photos = [r for r in records if r.get("current_visual_truth") and r.get("source_type") in {"wikimedia_commons_photo", "owned_photo"}]
assert len(current_player_photos) < 4, "Initial contract unexpectedly has enough current photo evidence; update this validator deliberately."

print("MIDI_VISUAL_TRUTH_CONTRACT_OK")
print("references", len(records), "views", len(cams["views"]), "blockers", len(blockers), "current_player_photos", len(current_player_photos))
