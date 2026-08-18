#!/usr/bin/env python3
"""Evidence-only Atomium plan-yaw registration against the frozen 2024 UrbIS ortho.

This deliberately resolves only yaw modulo 60 degrees. The orthophoto does not,
by itself, identify lower-vs-upper triangle parity or bipod foot coordinates.
No runtime geometry is emitted or authorized here.
"""
from __future__ import annotations

import hashlib
import io
import itertools
import json
import math
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data/qa/atomium_ortho_yaw_registration_contract.json"
OUT_DIR = ROOT / "artifacts/qa/atomium_ortho_yaw_registration"


def fail(message: str) -> None:
    raise RuntimeError(f"ATOMIUM_ORTHO_YAW_REGISTRATION_FAIL: {message}")


def load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"expected JSON object: {path}")
    return value


def project_path(res_path: str) -> Path:
    prefix = "res://"
    if not res_path.startswith(prefix):
        fail(f"topology path is not project-relative: {res_path!r}")
    path = (ROOT / res_path[len(prefix) :]).resolve()
    if ROOT.resolve() not in path.parents:
        fail("topology path escapes project root")
    return path


def fetch_exact_ortho(contract: dict) -> tuple[bytes, str]:
    source = contract["source"]
    bbox = source["bbox_epsg31370"]
    size = source["raster_size_px"]
    query = urlencode(
        {
            "Service": "WMS",
            "Version": "1.3.0",
            "Request": "GetMap",
            "Layers": source["layer"],
            "Styles": "",
            "CRS": source["crs"],
            "BBOX": ",".join(str(v) for v in bbox),
            "Width": int(size[0]),
            "Height": int(size[1]),
            "Format": "image/jpeg",
            "Transparent": "false",
        }
    )
    url = f"{source['service']}?{query}"
    req = Request(url, headers={"User-Agent": "Grand-Bruxelles-Game-QA/1.0"})
    try:
        with urlopen(req, timeout=30) as response:
            body = response.read()
            content_type = response.headers.get("Content-Type", "")
    except Exception as exc:  # source availability is a hard gate, not a geometry fallback
        fail(f"official 2024 WMS unavailable: {type(exc).__name__}: {exc}")
    if "image" not in content_type.lower() or len(body) < 50_000:
        fail(f"unexpected WMS response: type={content_type!r} bytes={len(body)}")
    digest = hashlib.sha256(body).hexdigest()
    expected = str(source["expected_response_sha256"])
    if digest != expected:
        fail(f"official 2024 raster SHA drifted: expected={expected} actual={digest}")
    image = Image.open(io.BytesIO(body))
    if list(image.size) != [int(size[0]), int(size[1])]:
        fail(f"official raster dimensions drifted: {image.size}")
    return body, url


def pairwise_distances(points: np.ndarray) -> np.ndarray:
    values: list[float] = []
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            values.append(float(np.linalg.norm(points[i] - points[j])))
    return np.asarray(values, dtype=np.float64)


def rigid_fit(source: np.ndarray, target: np.ndarray) -> tuple[float, np.ndarray, np.ndarray, np.ndarray]:
    """Fixed-scale, rotation+translation-only fit. Reflection is forbidden."""
    source_center = source.mean(axis=0)
    target_center = target.mean(axis=0)
    a = source - source_center
    b = target - target_center
    h = a.T @ b
    u, _s, vt = np.linalg.svd(h)
    rotation = vt.T @ u.T
    if np.linalg.det(rotation) < 0.0:
        vt[-1, :] *= -1.0
        rotation = vt.T @ u.T
    translation = target_center - source_center @ rotation.T
    predicted = source @ rotation.T + translation
    errors = np.linalg.norm(predicted - target, axis=1)
    angle_deg = math.degrees(math.atan2(rotation[1, 0], rotation[0, 0]))
    return angle_deg, translation, predicted, errors


def normalize_mod(value: float, period: float) -> float:
    result = value % period
    if result < 0.0:
        result += period
    return result


def main() -> int:
    contract = load_json(CONTRACT_PATH)
    if contract.get("schema") != "grand-bruxelles-atomium-ortho-yaw-registration-v1":
        fail("registration contract schema drifted")
    limits = contract["interpretation_limits"]
    if limits.get("yaw_resolution") != "modulo_60_degrees_only":
        fail("yaw interpretation was broadened")
    if any(
        bool(limits.get(key, True))
        for key in (
            "exact_global_yaw_resolved",
            "lower_vs_upper_triangle_parity_resolved",
            "support_foot_coordinates_resolved",
            "support_geometry_authorized",
            "runtime_authorized",
        )
    ):
        fail("evidence-only interpretation limits were promoted")

    policy = contract["topology_policy"]
    if any(
        bool(policy.get(key, True))
        for key in (
            "free_scale_allowed",
            "reflection_allowed",
            "perspective_warp_allowed",
            "manual_circle_centres_allowed",
            "post_failure_parameter_changes_allowed",
        )
    ):
        fail("registration policy allows forbidden fitting freedom")

    topology = load_json(project_path(str(contract["topology_source"])))
    status = topology.get("status", {})
    if bool(status.get("support_pillars_resolved", True)) or bool(status.get("orientation_resolved", True)):
        fail("production topology unexpectedly claims support/orientation resolution")
    dims = topology.get("authoritative_dimensions", {})
    if int(dims.get("sphere_count", -1)) != 9 or int(dims.get("support_pillar_count", -1)) != 3:
        fail("Atomium topology count contract drifted")
    centres_raw = topology.get("core_sphere_centres_m", [])
    if not isinstance(centres_raw, list) or len(centres_raw) != 9:
        fail("Atomium sphere-centre topology missing")

    same_height_indices = [int(v) for v in policy["same_height_triangle_indices"]]
    if same_height_indices != [1, 2, 3]:
        fail("same-height source triad changed")
    source_triangle_m = np.asarray(
        [[float(centres_raw[i][0]), float(centres_raw[i][2])] for i in same_height_indices],
        dtype=np.float64,
    )
    source_sides_m = pairwise_distances(source_triangle_m)
    expected_side_m = float(source_sides_m.mean())
    if float(source_sides_m.max() - source_sides_m.min()) > 0.001:
        fail("source same-height triad is no longer equilateral")

    body, source_url = fetch_exact_ortho(contract)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ortho_path = OUT_DIR / "ortho_2024.jpg"
    ortho_path.write_bytes(body)

    bgr = cv2.imdecode(np.frombuffer(body, dtype=np.uint8), cv2.IMREAD_COLOR)
    if bgr is None:
        fail("OpenCV could not decode official raster")
    detector = contract["detector"]
    x0, y0, x1, y1 = [int(v) for v in detector["roi_xyxy_px"]]
    if not (0 <= x0 < x1 <= bgr.shape[1] and 0 <= y0 < y1 <= bgr.shape[0]):
        fail("detector ROI outside official raster")
    roi = cv2.cvtColor(bgr[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY)
    kernel = tuple(int(v) for v in detector["gaussian_kernel"])
    blurred = cv2.GaussianBlur(roi, kernel, float(detector["gaussian_sigma"]))
    raw_circles = cv2.HoughCircles(
        blurred,
        cv2.HOUGH_GRADIENT,
        dp=float(detector["hough_dp"]),
        minDist=float(detector["hough_min_dist_px"]),
        param1=float(detector["hough_param1"]),
        param2=float(detector["hough_param2"]),
        minRadius=int(detector["hough_min_radius_px"]),
        maxRadius=int(detector["hough_max_radius_px"]),
    )
    if raw_circles is None:
        fail("deterministic Hough detector found zero circles")
    candidates = np.asarray(raw_circles[0], dtype=np.float64)
    candidates[:, 0] += x0
    candidates[:, 1] += y0

    acceptance = contract["acceptance"]
    candidate_count = len(candidates)
    if candidate_count < int(acceptance["candidate_count_min"]) or candidate_count > int(acceptance["candidate_count_max"]):
        fail(f"Hough candidate count outside frozen range: {candidate_count}")

    resolution = float(contract["source"]["ground_resolution_m_per_px"])
    expected_side_px = expected_side_m / resolution
    scored: list[dict] = []
    for combo in itertools.combinations(range(candidate_count), 3):
        points = candidates[list(combo), :2]
        sides_px = pairwise_distances(points)
        residual_px = sides_px - expected_side_px
        rms_px = float(np.sqrt(np.mean(residual_px * residual_px)))
        max_error_px = float(np.max(np.abs(residual_px)))
        scored.append(
            {
                "indices": combo,
                "points": points,
                "sides_px": sides_px,
                "rms_px": rms_px,
                "max_error_px": max_error_px,
            }
        )
    scored.sort(key=lambda row: (row["rms_px"], row["max_error_px"], row["indices"]))
    if len(scored) < 2:
        fail("not enough candidate triangles for uniqueness gate")
    best = scored[0]
    second = scored[1]
    side_rms_m = float(best["rms_px"] * resolution)
    side_max_m = float(best["max_error_px"] * resolution)
    second_rms_m = float(second["rms_px"] * resolution)
    second_margin_m = second_rms_m - side_rms_m

    if side_rms_m > float(acceptance["triangle_side_rms_m_max"]):
        fail(f"best source-scale triad side RMS too large: {side_rms_m:.6f} m")
    if side_max_m > float(acceptance["triangle_side_max_error_m_max"]):
        fail(f"best source-scale triad max side error too large: {side_max_m:.6f} m")
    if second_margin_m < float(acceptance["second_best_triangle_margin_m_min"]):
        fail(f"detected source triad is not unique enough: margin={second_margin_m:.6f} m")

    source_triangle_px = source_triangle_m / resolution
    fit_rows: list[dict] = []
    best_points = np.asarray(best["points"], dtype=np.float64)
    for perm in itertools.permutations(range(3)):
        target = best_points[list(perm)]
        angle_deg, translation, predicted, errors_px = rigid_fit(source_triangle_px, target)
        fit_rows.append(
            {
                "permutation": perm,
                "angle_deg": angle_deg,
                "angle_mod120_deg": normalize_mod(angle_deg, 120.0),
                "translation_px": translation,
                "predicted": predicted,
                "errors_px": errors_px,
                "rms_px": float(np.sqrt(np.mean(errors_px * errors_px))),
                "max_error_px": float(np.max(errors_px)),
            }
        )
    fit_rows.sort(key=lambda row: (row["rms_px"], row["max_error_px"], row["permutation"]))
    fit = fit_rows[0]
    fit_rms_m = float(fit["rms_px"] * resolution)
    fit_max_m = float(fit["max_error_px"] * resolution)
    if fit_rms_m > float(acceptance["triangle_rigid_fit_rms_m_max"]):
        fail(f"fixed-scale rigid triad fit RMS too large: {fit_rms_m:.6f} m")
    if fit_max_m > float(acceptance["triangle_rigid_fit_max_error_m_max"]):
        fail(f"fixed-scale rigid triad fit max error too large: {fit_max_m:.6f} m")

    lower_hypothesis_mod120 = float(fit["angle_mod120_deg"])
    upper_hypothesis_mod120 = normalize_mod(lower_hypothesis_mod120 - 60.0, 120.0)
    yaw_mod60 = normalize_mod(lower_hypothesis_mod120, 60.0)
    orientation_candidates_mod120 = sorted([lower_hypothesis_mod120, upper_hypothesis_mod120])

    selected_indices = [int(v) for v in best["indices"]]
    selected = candidates[selected_indices]
    overlay = bgr.copy()
    cv2.rectangle(overlay, (x0, y0), (x1 - 1, y1 - 1), (255, 255, 0), 2)
    for index, (x, y, r) in enumerate(candidates):
        colour = (0, 255, 255)
        thickness = 2
        if index in selected_indices:
            colour = (0, 255, 0)
            thickness = 4
        cv2.circle(overlay, (int(round(x)), int(round(y))), int(round(r)), colour, thickness)
        cv2.putText(overlay, str(index), (int(round(x)) + 6, int(round(y)) - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.6, colour, 2)
    selected_points = selected[:, :2]
    for i in range(3):
        p0 = tuple(int(round(v)) for v in selected_points[i])
        p1 = tuple(int(round(v)) for v in selected_points[(i + 1) % 3])
        cv2.line(overlay, p0, p1, (0, 255, 0), 4)
    label = f"yaw mod 60 = {yaw_mod60:.3f} deg | RMS {fit_rms_m:.3f} m | parity unresolved"
    cv2.rectangle(overlay, (20, 20), (1020, 68), (0, 0, 0), -1)
    cv2.putText(overlay, label, (32, 53), cv2.FONT_HERSHEY_SIMPLEX, 0.85, (255, 255, 255), 2)
    overlay_path = OUT_DIR / "orientation_overlay.png"
    if not cv2.imwrite(str(overlay_path), overlay):
        fail("could not write orientation overlay")

    report = {
        "schema": "grand-bruxelles-atomium-ortho-yaw-registration-result-v1",
        "source": {
            "url": source_url,
            "sha256": hashlib.sha256(body).hexdigest(),
            "raster_size_px": [int(bgr.shape[1]), int(bgr.shape[0])],
            "ground_resolution_m_per_px": resolution,
        },
        "topology": {
            "source_path": str(contract["topology_source"]),
            "same_height_triangle_indices": same_height_indices,
            "expected_side_m": expected_side_m,
            "scale_fitted": False,
            "reflection_used": False,
            "perspective_warp_used": False,
        },
        "detector": {
            "candidate_count": candidate_count,
            "candidates_xy_radius_px": [[float(v) for v in row] for row in candidates.tolist()],
            "selected_indices": selected_indices,
            "selected_xy_radius_px": [[float(v) for v in row] for row in selected.tolist()],
        },
        "metrics": {
            "observed_side_lengths_m": [float(v * resolution) for v in best["sides_px"].tolist()],
            "triangle_side_rms_m": side_rms_m,
            "triangle_side_max_error_m": side_max_m,
            "second_best_triangle_rms_m": second_rms_m,
            "second_best_margin_m": second_margin_m,
            "rigid_fit_rms_m": fit_rms_m,
            "rigid_fit_max_error_m": fit_max_m,
        },
        "orientation": {
            "yaw_modulo_60_deg": yaw_mod60,
            "orientation_candidates_mod120_deg": orientation_candidates_mod120,
            "lower_vs_upper_triangle_parity_resolved": False,
            "exact_global_yaw_resolved": False,
        },
        "authorization": {
            "support_foot_coordinates_resolved": False,
            "support_geometry_authorized": False,
            "runtime_authorized": False,
        },
        "acceptance": {"passed": True, "frozen_contract": contract["acceptance"]},
    }
    (OUT_DIR / "orientation_report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "ATOMIUM_ORTHO_YAW_REGISTRATION_METRICS: "
        f"candidates={candidate_count} selected={selected_indices} expected_side={expected_side_m:.6f}m "
        f"side_rms={side_rms_m:.6f}m side_max={side_max_m:.6f}m "
        f"second_margin={second_margin_m:.6f}m fit_rms={fit_rms_m:.6f}m fit_max={fit_max_m:.6f}m "
        f"yaw_mod60={yaw_mod60:.6f}deg candidates_mod120={orientation_candidates_mod120}"
    )
    print(
        "ATOMIUM_ORTHO_YAW_REGISTRATION_OK: "
        "exact_global_yaw_resolved=false parity_resolved=false support_geometry_authorized=false runtime_authorized=false"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(str(exc))
        raise
