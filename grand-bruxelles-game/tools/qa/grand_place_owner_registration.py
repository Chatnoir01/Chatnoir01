#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "data/qa/grand_place_owner_registration_contract.json"
LOD2_DIR = ROOT / "data/urbis/grand_place_lod2"
EXPECTED = {"1639974.game.json", "1655673.game.json", "1786758.game.json"}


def fail(msg: str) -> None:
    raise SystemExit(f"GRAND_PLACE_OWNER_REGISTRATION_FAIL: {msg}")


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("base_main") != "0807581e4a711d21b535a7def66f089da037a2f4":
        fail("unexpected base_main")
    actual = {p.name for p in LOD2_DIR.glob("*.game.json")}
    if actual != EXPECTED:
        fail(f"persisted LoD2 owner set changed: {sorted(actual)}")
    candidate = contract["candidate_owner_1786758"]
    geom = json.loads((LOD2_DIR / "1786758.game.json").read_text(encoding="utf-8"))
    evidence = geom.get("evidence", {})
    if evidence.get("face_count") != 82:
        fail("1786758 face_count drift")
    counts = evidence.get("face_type_counts", {})
    if counts.get("WALLSURFACE") != 19 or counts.get("ROOFSURFACE") != 62 or counts.get("GROUNDSURFACE") != 1:
        fail("1786758 surface counts drift")
    if candidate.get("semantic_name") is not None:
        fail("1786758 semantic identity must remain unresolved")
    if candidate.get("heritage_candidate_context", {}).get("semantic_crosswalk_to_1786758_proven") is not False:
        fail("heritage candidate must not be promoted to UrbIS crosswalk")
    rules = contract.get("hard_rules", {})
    for key in ["proximity_inference_allowed", "heritage_name_without_urbis_crosswalk_allowed", "runtime_changed", "geometry_changed", "implementation_authorized", "camera_rescue", "threshold_rescue"]:
        if rules.get(key) is not False:
            fail(f"hard rule {key} must stay false")
    print("GRAND_PLACE_OWNER_REGISTRATION_OK")


if __name__ == "__main__":
    main()
