#!/usr/bin/env python3
import json
import sys
from pathlib import Path

ALLOWED_STATES = ["data_ready", "playable", "realism_validated"]
REQUIRED_TOP = {
    "format", "cell_id", "crs", "bbox", "maturity", "provenance",
    "geometry", "terrain", "heights", "collisions", "transport",
    "photo_match", "performance", "uncertainties"
}


def fail(message: str) -> None:
    raise ValueError(message)


def validate(data: dict) -> None:
    missing = sorted(REQUIRED_TOP - set(data))
    if missing:
        fail(f"missing top-level fields: {', '.join(missing)}")
    if data["format"] != "grand-bruxelles-cell-maturity-v1":
        fail("unexpected format")
    if data["crs"] != "EPSG:31370":
        fail("cell CRS must remain EPSG:31370")
    bbox = data["bbox"]
    if not (isinstance(bbox, list) and len(bbox) == 4 and all(isinstance(v, (int, float)) for v in bbox)):
        fail("bbox must contain four numeric Lambert72 coordinates")
    if bbox[2] <= bbox[0] or bbox[3] <= bbox[1]:
        fail("bbox must have positive width and height")

    maturity = data["maturity"]
    state = maturity.get("state")
    if state not in ALLOWED_STATES:
        fail("invalid maturity state")
    gates = maturity.get("gates")
    if not isinstance(gates, dict):
        fail("maturity.gates must be an object")

    geometry_ok = bool(data["geometry"].get("authoritative_geometry_ready"))
    provenance_ok = bool(data["provenance"].get("source_records_present"))
    if state in ("playable", "realism_validated"):
        for key in ("runtime_geometry", "collisions", "streaming"):
            if not bool(gates.get(key)):
                fail(f"{state} requires gate: {key}")
        if not geometry_ok or not provenance_ok:
            fail(f"{state} requires authoritative geometry and provenance")
    if state == "realism_validated":
        for key in ("terrain", "heights", "photo_match", "performance"):
            if not bool(gates.get(key)):
                fail(f"realism_validated requires gate: {key}")
        if data["uncertainties"]:
            fail("realism_validated cannot retain unresolved uncertainties")

    if data["heights"].get("status") == "invalidated":
        if bool(gates.get("heights")):
            fail("invalidated height evidence cannot satisfy the heights gate")
        if state == "realism_validated":
            fail("invalidated height evidence blocks realism validation")

    if bool(data["photo_match"].get("required")) and state == "realism_validated":
        if int(data["photo_match"].get("open_major_mismatches", 0)) != 0:
            fail("realism_validated requires zero major photo-match mismatches")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_cell_manifest.py <manifest.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        validate(data)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"CELL_MANIFEST_FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"CELL_MANIFEST_OK: {data['cell_id']} state={data['maturity']['state']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
