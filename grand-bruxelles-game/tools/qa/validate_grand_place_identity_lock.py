#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "data/qa/grand_place_facade_owner_identity.lock.json"
PROVENANCE_BASE = "c4b29c284df182091a1a4cdf19e1d2dc894f45e4"
EXPECTED_RESOLVED = {
    "1608847": ("6", "Le Cornet", "31123"),
    "1608851": ("7", "Le Renard", "31124"),
    "1635485": ("11", "La Rose", "31128"),
    "1639974": ("10", "La Maison des Brasseurs", "31127"),
    "1646728": ("12", "Le Mont Thabor", "30907"),
    "1654360": ("29", "Maison du Roi", "31143"),
}


def fail(message: str) -> None:
    raise SystemExit(f"GRAND_PLACE_IDENTITY_LOCK_FAIL: {message}")


def main() -> None:
    if not LOCK.is_file():
        fail(f"missing {LOCK.relative_to(ROOT)}")
    data = json.loads(LOCK.read_text(encoding="utf-8"))
    if data.get("schema") != "grand-bruxelles-grand-place-facade-owner-identity-lock-v2":
        fail("unexpected schema")
    if data.get("production_base_sha") != PROVENANCE_BASE:
        fail("identity-lock provenance base drifted from the proven crosswalk")

    proof = data.get("source_proof", {})
    required_proof = ["crosswalk_run_id", "crosswalk_artifact_id", "crosswalk_artifact_digest", "urbis_address_response_sha256"]
    if any(not proof.get(k) for k in required_proof):
        fail("source proof is incomplete")

    resolved = data.get("resolved", [])
    by_id = {str(item.get("building_id")): item for item in resolved}
    if set(by_id) != set(EXPECTED_RESOLVED):
        fail("resolved owner set changed")
    for building_id, (number, name, record) in EXPECTED_RESOLVED.items():
        item = by_id[building_id]
        actual = (str(item.get("grand_place_number")), item.get("official_name"), str(item.get("urban_record_id")))
        if actual != (number, name, record):
            fail(f"identity drift for owner {building_id}: {actual!r}")
        if not item.get("address_id", "").startswith("https://databrussels.be/id/address/"):
            fail(f"non-official address id for owner {building_id}")

    hold = [str(v) for v in data.get("hold_owner_ids", [])]
    if len(hold) != len(set(hold)) or set(hold) & set(by_id):
        fail("hold/resolved ownership is ambiguous")
    if len(hold) != 17:
        fail("hold owner count drift")

    rules = data.get("hard_rules", {})
    required_true = ["only_resolved_may_receive_named_presentation", "hold_remains_neutral"]
    forbidden_true = ["nearest_neighbour_allowed", "list_order_allowed", "runtime_geometry_authorized", "collision_change_authorized", "camera_rescue_authorized", "threshold_rescue_authorized"]
    if any(rules.get(k) is not True for k in required_true):
        fail("fail-closed presentation rules weakened")
    if any(rules.get(k) is not False for k in forbidden_true):
        fail("forbidden rescue or geometry authority enabled")

    print(f"GRAND_PLACE_IDENTITY_LOCK_GREEN resolved={len(resolved)} hold={len(hold)} provenance_base={PROVENANCE_BASE}")


if __name__ == "__main__":
    main()
