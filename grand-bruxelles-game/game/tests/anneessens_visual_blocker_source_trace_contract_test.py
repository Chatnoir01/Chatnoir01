#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "data/osm/vertical_slice_01.game.json"
RECEIPT = ROOT / "data/qa/anneessens_visual_blocker_source_trace.json"
EXPECTED_SOURCE_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
EXPECTED_FRAME_SHA256 = "7e67a819676618bac240210c5544e5970a84ca1f7d95d110d05fb07543eadf07"
EXPECTED_RUNTIME_SHA256 = "76b82e40cef2442fef96585a540bc844500382496fe6461808f55379332b25266"
EXPECTED_FOOTPRINT = [
    [-285.331, -198.761],
    [-274.885, -190.701],
    [-277.514, -187.262],
    [-289.696, -171.354],
    [-300.057, -179.224],
]


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> None:
    if not RECEIPT.is_file():
        fail(f"missing Anneessens visual-blocker source-trace receipt: {RECEIPT}")

    raw = SOURCE.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_SOURCE_SHA256:
        fail(f"source digest drift: {digest}")

    source = json.loads(raw)
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))

    if receipt.get("schema") != "anneessens-visual-blocker-source-trace-v1":
        fail("unexpected source-trace schema")

    buildings = source.get("buildings", [])
    blocker = next((b for b in buildings if int(b.get("osm_id", -1)) == 256376389), None)
    if blocker is None:
        fail("source building 256376389 missing")
    if blocker.get("kind") != "apartments" or blocker.get("name") != "":
        fail("source building semantics drift")
    if float(blocker.get("height", -1)) != 14.0 or float(blocker.get("area", -1)) != 319.93:
        fail("source building dimensions drift")
    if blocker.get("footprint") != EXPECTED_FOOTPRINT:
        fail("source building footprint drift")

    roads = source.get("roads", [])
    road = next((r for r in roads if int(r.get("osm_id", -1)) == 1382734012), None)
    if road is None or road.get("name") != "Place Anneessens - Anneessensplein":
        fail("Anneessens source road identity drift")

    if receipt.get("source", {}).get("path") != "res://data/osm/vertical_slice_01.game.json":
        fail("receipt source path drift")
    if receipt.get("source", {}).get("sha256") != EXPECTED_SOURCE_SHA256:
        fail("receipt source digest drift")

    observed = receipt.get("runtime_trace", {}).get("samples", [])
    if [x.get("screen") for x in observed] != [[760, 360], [900, 360], [1100, 360]]:
        fail("runtime trace sample coordinates drift")
    if observed[0].get("hit") is not False:
        fail("leftmost blocker probe must remain a miss in frozen evidence")
    for sample, distance in zip(observed[1:], [16.970, 17.767]):
        if sample.get("hit") is not True:
            fail("right-side blocker probe must be a hit")
        if sample.get("collider_name") != "Building_256376389_0":
            fail("visual blocker collider identity drift")
        if sample.get("collider_class") != "CSGPolygon3D":
            fail("visual blocker collider class drift")
        if "BrusselsOSM/GeneratedBuildings/Building_256376389_0" not in sample.get("collider_path", ""):
            fail("visual blocker collider ownership path drift")
        if abs(float(sample.get("distance_m", -1)) - distance) > 0.001:
            fail("visual blocker distance drift")

    evidence = receipt.get("evidence", {})
    if evidence.get("workflow_run_id") != 33611926985 or evidence.get("artifact_id") != 9839372629:
        fail("witness run/artifact provenance drift")
    if evidence.get("artifact_digest") != "sha256:fe506c9350c08b82e0760cc64614e4d2de4b4af4738726d72cb0f43935fcc15e":
        fail("artifact digest drift")
    if evidence.get("frame_sha256") != EXPECTED_FRAME_SHA256 or evidence.get("runtime_log_sha256") != EXPECTED_RUNTIME_SHA256:
        fail("frame/runtime evidence digest drift")
    if evidence.get("frame_width") != 1280 or evidence.get("frame_height") != 720:
        fail("full-frame dimensions drift")

    verdict = receipt.get("verdict", {})
    required_false = [
        "geometry_change_authorized",
        "camera_rescue_authorized",
        "visual_acceptance",
        "destination_advertisable",
        "jouable_authorized",
    ]
    for key in required_false:
        if verdict.get(key) is not False:
            fail(f"fail-closed verdict violated: {key}")
    if verdict.get("source_identity_established") is not True:
        fail("source identity must be established")

    print("ANNEESSENS_VISUAL_BLOCKER_SOURCE_TRACE_GREEN: blocker_osm_id=256376389 road_osm_id=1382734012 source_identity_established=true geometry_change_authorized=false camera_rescue_authorized=false visual_acceptance=false destination_advertisable=false jouable_authorized=false")


if __name__ == "__main__":
    main()
