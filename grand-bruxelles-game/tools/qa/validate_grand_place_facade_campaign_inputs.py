#!/usr/bin/env python3
"""Validate the immutable inputs for the Grand-Place facade crosswalk campaign."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "data/qa/grand_place_address_crosswalk.contract.json"
CAMPAIGN = ROOT / "data/qa/grand_place_facade_campaign.json"
HERITAGE = ROOT / "data/qa/grand_place_heritage_address_registry.json"


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    campaign = json.loads(CAMPAIGN.read_text(encoding="utf-8"))
    heritage = json.loads(HERITAGE.read_text(encoding="utf-8"))
    assert contract["schema"] == "grand-bruxelles-grand-place-address-crosswalk-contract-v1"
    assert contract["owner_count"] == 25
    assert contract["facade_target_owner_count"] == 23
    assert contract["runtime_authorized"] is False
    assert campaign["schema"] == "grand-bruxelles-grand-place-facade-campaign-v1"
    assert len(campaign["target_owner_ids"]) == 23
    assert len(set(campaign["target_owner_ids"])) == 23
    assert campaign["hard_rules"]["source_geometry_changed"] is False
    assert campaign["hard_rules"]["collision_changed"] is False
    assert campaign["hard_rules"]["finished_perfect_before_multiview_human_pass"] is False
    assert heritage["runtime_authorized"] is False
    assert heritage["building_id_crosswalk_authorized"] is False
    assert heritage["hard_rules"]["require_exact_address_crosswalk_before_owner_identity"] is True
    print("GRAND_PLACE_FACADE_CAMPAIGN_INPUTS_OK owners=23 crosswalk_owners=25")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
