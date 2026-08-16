#!/usr/bin/env python3
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/reference/laeken_jette/heysel_stadium_target_evidence.json"
CAMERAS = ROOT / "data/reference/laeken_jette/heysel_stadium_camera_candidates.json"
ANCHORS = ROOT / "data/reference/laeken_jette/anchors.json"


def fail(message: str) -> None:
    raise SystemExit(f"HEYSEL_CAMERA_CANDIDATES_FAIL: {message}")


def load(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"cannot read {path}: {exc}")


def close(a: float, b: float, tolerance: float = 1e-6) -> bool:
    return abs(a - b) <= tolerance


def main() -> None:
    evidence = load(EVIDENCE)
    cameras = load(CAMERAS)
    anchors = load(ANCHORS)

    if cameras.get("view_id") != "heysel_stadium_context_v1":
        fail("wrong view id")
    if "provisional" not in str(cameras.get("status", "")):
        fail("camera registry must remain explicitly provisional")

    atomium = next((a for a in anchors.get("anchors", []) if a.get("id") == "atomium"), None)
    if atomium is None:
        fail("Atomium anchor missing")
    anchor_x, anchor_z = map(float, atomium["game_xz"])

    target = evidence["authoritative_target"]
    target_x = float(target["full_urbis_union_game_xz"]["x"])
    target_z = float(target["full_urbis_union_game_xz"]["z"])
    target_y = float(target["terrain_elevation"]["relative_to_atomium_baseline_m"])

    geom = cameras.get("geometry", {})
    declared_target = geom.get("stadium_target_game_xz", [])
    if len(declared_target) != 2 or not close(float(declared_target[0]), target_x) or not close(float(declared_target[1]), target_z):
        fail("camera target does not match authoritative UrbIS stadium target")
    if not close(float(geom.get("stadium_target_ground_y_from_atomium_baseline_m", -9999.0)), target_y):
        fail("camera target Y does not match pinned DTM stadium elevation")

    distance = math.hypot(target_x - anchor_x, target_z - anchor_z)
    if not close(float(geom.get("horizontal_anchor_to_target_distance_m", -1.0)), distance, 1e-5):
        fail("declared Atomium-to-stadium distance is inconsistent")

    official_radius = float(geom.get("official_atomium_sphere_radius_m", -1.0))
    clearance = float(geom.get("render_clearance_m", -1.0))
    offset = float(geom.get("observation_offset_toward_target_m", -1.0))
    if not close(official_radius, 9.0):
        fail("official Atomium sphere radius must remain 9 m from the documented 18 m diameter")
    if not (0.1 <= clearance <= 1.0):
        fail("render clearance must remain a small technical margin")
    if not close(offset, official_radius + clearance):
        fail("camera offset must equal official sphere radius plus render clearance")

    ux = (target_x - anchor_x) / distance
    uz = (target_z - anchor_z) / distance
    expected_x = anchor_x + ux * offset
    expected_z = anchor_z + uz * offset
    declared_cam = geom.get("provisional_camera_game_xz", [])
    if len(declared_cam) != 2 or not close(float(declared_cam[0]), expected_x, 1e-6) or not close(float(declared_cam[1]), expected_z, 1e-6):
        fail("provisional camera X/Z is not the documented rendering-safe offset")

    candidates = cameras.get("candidates", [])
    if len(candidates) != 2:
        fail("expected exactly two camera candidates")
    levels = [float(c.get("observation_level_y_from_atomium_baseline_m", -1.0)) for c in candidates]
    if levels != [92.0, 36.0]:
        fail(f"candidate levels changed: {levels}")
    for candidate in candidates:
        if candidate.get("level_status") != "plausible_not_proven":
            fail("candidate level must not be promoted beyond plausible_not_proven")
        cxyz = candidate.get("camera_game_xyz", [])
        txyz = candidate.get("target_game_xyz", [])
        if len(cxyz) != 3 or len(txyz) != 3:
            fail("candidate camera/target coordinates invalid")
        if not close(float(cxyz[0]), expected_x) or not close(float(cxyz[2]), expected_z):
            fail("candidate X/Z does not match provisional observation point")
        if not close(float(cxyz[1]), float(candidate["observation_level_y_from_atomium_baseline_m"])):
            fail("candidate Y does not match its declared observation level")
        if not close(float(txyz[0]), target_x) or not close(float(txyz[1]), target_y) or not close(float(txyz[2]), target_z):
            fail("candidate target diverges from UrbIS+DTM evidence")
        if not close(float(candidate.get("fov_degrees", 0.0)), 50.0):
            fail("comparison FOV must remain the documented provisional 50 degrees")

    forbidden = set(cameras.get("must_not_infer", []))
    if "which Atomium observation level was used by the 2007 photographer" not in forbidden:
        fail("uncertainty guardrail missing")

    print(f"HEYSEL_CAMERA_CANDIDATES_OK: target=({target_x:.3f},{target_y:.3f},{target_z:.3f}) distance={distance:.3f} radius={official_radius:.1f} clearance={clearance:.1f} levels={levels}")


if __name__ == "__main__":
    main()
