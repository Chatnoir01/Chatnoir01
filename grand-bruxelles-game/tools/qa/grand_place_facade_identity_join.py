#!/usr/bin/env python3
"""Join exact-unique Grand-Place address containment to the official heritage registry.

This tool consumes the crosswalk artifact produced by grand_place_address_crosswalk.py.
It never performs a spatial fallback. A heritage style/name is emitted only when an
exact-unique AddressNumbers point has a Grand-Place police number present in the
committed Urban Brussels registry. All other owners remain HOLD.
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

SCHEMA = "grand-bruxelles-grand-place-facade-owner-identity-v1"


def norm_number(value) -> str:
    if value is None:
        return ""
    text = str(value).strip().lower().replace(" ", "")
    return re.sub(r"[^0-9a-z]", "", text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--crosswalk", required=True)
    ap.add_argument("--heritage", required=True)
    ap.add_argument("--campaign", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    cross = json.loads(Path(args.crosswalk).read_text(encoding="utf-8"))
    heritage = json.loads(Path(args.heritage).read_text(encoding="utf-8"))
    campaign = json.loads(Path(args.campaign).read_text(encoding="utf-8"))

    if cross.get("schema") != "grand-bruxelles-grand-place-address-crosswalk-v1":
        raise SystemExit("crosswalk schema mismatch")
    if heritage.get("schema") != "grand-bruxelles-grand-place-heritage-address-registry-v1":
        raise SystemExit("heritage schema mismatch")
    target = set(campaign.get("target_owner_ids", []))
    if len(target) != 23:
        raise SystemExit("campaign target must contain exactly 23 owners")

    number_to_group = {}
    for group in heritage.get("address_groups", []):
        for raw in group.get("numbers", []):
            key = norm_number(raw)
            if not key or key in number_to_group:
                raise SystemExit(f"duplicate/invalid heritage number {raw}")
            number_to_group[key] = group

    address_by_id = {str(row.get("address_id", "")): row for row in cross.get("addresses", [])}
    owner_rows = []
    resolved = 0
    held = 0
    for item in cross.get("resolved_owners", []):
        owner = str(item.get("building_id", ""))
        if owner not in target:
            continue
        candidates = []
        for address_id in item.get("address_ids", []):
            row = address_by_id.get(str(address_id))
            if not row or row.get("status") != "exact_unique":
                continue
            street_fr = str(row.get("street_name_fr") or "")
            street_nl = str(row.get("street_name_nl") or "")
            # Fail closed: only Grand-Place/Grote Markt address points are eligible.
            if "grand" not in street_fr.lower() and "grote" not in street_nl.lower():
                continue
            number = norm_number(row.get("police_number"))
            group = number_to_group.get(number)
            if group:
                candidates.append((number, row, group))
        # One owner may legitimately contain several police numbers belonging to one
        # official property group (e.g. 13-19). Require all matches to agree.
        signatures = {(c[2].get("official_name"), c[2].get("style_family")) for c in candidates}
        if candidates and len(signatures) == 1:
            name, style = next(iter(signatures))
            nums = sorted({c[0] for c in candidates})
            owner_rows.append({
                "building_id": owner,
                "status": "exact_address_heritage_match",
                "grand_place_numbers": nums,
                "official_name": name,
                "style_family": style,
                "heritage_record_id": candidates[0][2].get("record_id"),
                "address_ids": sorted({str(c[1].get("address_id")) for c in candidates}),
                "runtime_authorized": False,
                "dimensions_surveyed": False,
            })
            resolved += 1
        else:
            owner_rows.append({
                "building_id": owner,
                "status": "hold",
                "candidate_match_count": len(candidates),
                "conflicting_signatures": sorted([list(s) for s in signatures]),
                "runtime_authorized": False,
            })
            held += 1

    seen = {r["building_id"] for r in owner_rows}
    for owner in sorted(target - seen, key=int):
        owner_rows.append({"building_id": owner, "status": "hold", "reason": "no exact contained Grand-Place address", "runtime_authorized": False})
        held += 1
    owner_rows.sort(key=lambda r: int(r["building_id"]))

    out = {
        "schema": SCHEMA,
        "status": "evidence_only",
        "runtime_authorized": False,
        "source_geometry_change_authorized": False,
        "counts": {"target_owners": 23, "identity_resolved": resolved, "hold": held},
        "owners": owner_rows,
        "hard_rules": {
            "only_exact_unique_address_containment": True,
            "nearest_neighbour_allowed": False,
            "conflicting_property_groups_authorize_identity": False,
            "hold_owner_authorizes_named_style": False,
        },
    }
    Path(args.output).write_text(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"GRAND_PLACE_FACADE_IDENTITY_OK target=23 resolved={resolved} hold={held}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
