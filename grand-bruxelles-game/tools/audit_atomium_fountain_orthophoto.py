#!/usr/bin/env python3
"""Reproduce the current Atomium circular-basin witness from official orthophoto.

The audit verifies the frozen WMS response, detects the strong circular basin edge
inside a pre-registered ROI, converts it to EPSG:31370/project coordinates and
measures its offset from the Commons-camera -> Atomium-anchor axis. It does not
infer jets, wall height, material, or historical 2006 fountain identity.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PROBE_DIR = ROOT / "artifacts/qa/atomium_foreground_ortho"
PROBE_JSON = PROBE_DIR / "probe.json"
CROP_PATH = PROBE_DIR / "ortho_crop.jpg"
EVIDENCE = ROOT / "data/sources/laeken_jette/atomium_fountain_orthophoto_evidence.json"
OUTPUT = PROBE_DIR / "basin_witness.png"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _fail(message: str) -> None:
    raise RuntimeError(f"ATOMIUM_FOUNTAIN_ORTHO_AUDIT_FAIL: {message}")


def _point_line_distance(point: np.ndarray, a: np.ndarray, b: np.ndarray) -> float:
    ab = b - a
    denom = float(np.dot(ab, ab))
    if denom <= 0.0:
        _fail("zero camera-to-Atomium axis")
    t = float(np.dot(point - a, ab) / denom)
    projection = a + t * ab
    return float(np.linalg.norm(point - projection))


def main() -> int:
    probe = _load(PROBE_JSON)
    evidence = _load(EVIDENCE)
    source = evidence["source"]
    witness = evidence["circular_basin_witness"]
    alignment = evidence["reference_alignment_audit"]

    if probe.get("source_mode") != "official_wms_live":
        _fail("geometry audit requires the frozen live-WMS crop, not the lower-resolution fallback")
    if probe.get("source_response_sha256") != source["wms_response_sha256"]:
        _fail("official WMS response SHA changed; inspect source before accepting a new geometry witness")
    if probe.get("bbox_epsg31370") != source["capture_bbox_epsg31370"]:
        _fail("crop bbox drifted")
    if probe.get("raster_size_px") != source["capture_size_px"]:
        _fail("crop raster dimensions drifted")

    image = cv2.imread(str(CROP_PATH), cv2.IMREAD_COLOR)
    if image is None:
        _fail("orthophoto crop missing")
    x0, y0, x1, y1 = [int(v) for v in witness["roi_px"]]
    roi = image[y0:y1, x0:x1]
    if roi.size == 0:
        _fail("registered basin ROI is empty")
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    gray = cv2.medianBlur(gray, 5)
    circles = cv2.HoughCircles(
        gray,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=50,
        param1=120,
        param2=50,
        minRadius=80,
        maxRadius=220,
    )
    if circles is None or circles.shape[1] == 0:
        _fail("no circular basin candidate detected")

    expected_x, expected_y = [float(v) for v in witness["circle_center_px"]]
    expected_r = float(witness["circle_radius_px"])
    candidates = []
    for cx, cy, radius in circles[0]:
        gx = float(cx) + x0
        gy = float(cy) + y0
        score = math.hypot(gx - expected_x, gy - expected_y) + abs(float(radius) - expected_r)
        candidates.append((score, gx, gy, float(radius)))
    candidates.sort()
    _, cx, cy, radius = candidates[0]
    if math.hypot(cx - expected_x, cy - expected_y) > 2.0:
        _fail(f"basin center drifted: {(cx, cy)}")
    if abs(radius - expected_r) > 2.0:
        _fail(f"basin radius drifted: {radius}")

    min_e, min_n, max_e, max_n = [float(v) for v in source["capture_bbox_epsg31370"]]
    width, height = [int(v) for v in source["capture_size_px"]]
    res_x = (max_e - min_e) / width
    res_y = (max_n - min_n) / height
    e = min_e + (cx + 0.5) * res_x
    n = max_n - (cy + 0.5) * res_y
    radius_m = radius * 0.5 * (res_x + res_y)
    exp_e, exp_n = [float(v) for v in witness["center_epsg31370"]]
    if math.hypot(e - exp_e, n - exp_n) > 0.5:
        _fail(f"EPSG center drifted: {(e, n)}")
    if abs(radius_m - float(witness["radius_m"])) > 0.5:
        _fail(f"metric radius drifted: {radius_m}")

    origin_e, origin_n = [float(v) for v in witness["game_origin_epsg31370"]]
    game = np.array([e - origin_e, -(n - origin_n)], dtype=np.float64)
    expected_game = np.array([float(v) for v in witness["game_center_xz"]], dtype=np.float64)
    if float(np.linalg.norm(game - expected_game)) > 0.5:
        _fail(f"project transform drifted: {game.tolist()}")

    camera_e, camera_n = [float(v) for v in alignment["commons_camera_epsg31370"]]
    atomium_e, atomium_n = [float(v) for v in alignment["atomium_anchor_epsg31370"]]
    lateral = _point_line_distance(
        np.array([e, n], dtype=np.float64),
        np.array([camera_e, camera_n], dtype=np.float64),
        np.array([atomium_e, atomium_n], dtype=np.float64),
    )
    if abs(lateral - float(alignment["basin_center_lateral_distance_from_camera_to_atomium_anchor_axis_m"])) > 0.75:
        _fail(f"reference-axis offset drifted: {lateral}")
    if lateral < 80.0:
        _fail("historical composition blocker was accidentally erased")

    overlay = image.copy()
    cv2.circle(overlay, (round(cx), round(cy)), round(radius), (0, 0, 255), 5)
    cv2.circle(overlay, (round(cx), round(cy)), 5, (0, 255, 255), -1)
    cv2.imwrite(str(OUTPUT), overlay)
    print(
        "ATOMIUM_FOUNTAIN_ORTHO_AUDIT_OK: "
        f"center_px=({cx:.2f},{cy:.2f}) radius_px={radius:.2f} "
        f"center_epsg=({e:.3f},{n:.3f}) radius_m={radius_m:.3f} "
        f"game_xz=({game[0]:.3f},{game[1]:.3f}) axis_offset_m={lateral:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
