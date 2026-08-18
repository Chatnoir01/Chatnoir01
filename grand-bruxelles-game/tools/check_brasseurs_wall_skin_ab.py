#!/usr/bin/env python3
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "data" / "qa" / "grand_place_brasseurs_wall_skin_source.json"
METRICS_PATH = Path("/tmp/brasseurs-wall-ab-metrics.json")


def fail(message: str) -> None:
    print(f"BRASSEURS_WALL_SKIN_AB_FAIL: {message}")
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: check_brasseurs_wall_skin_ab.py BEFORE AFTER")
    before_path = Path(sys.argv[1])
    after_path = Path(sys.argv[2])
    if not before_path.is_file() or not after_path.is_file():
        fail("BEFORE/AFTER image missing")
    if not SOURCE_PATH.is_file():
        fail("frozen source/gate contract missing")

    source = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    gate = source.get("visual_gate", {})
    if not gate.get("thresholds_frozen_before_first_candidate_render", False):
        fail("threshold-freeze invariant missing")
    if gate.get("camera_contract_path") != "res://data/qa/grand_place_clean_player_witness.json":
        fail("camera contract path drifted")

    expected_size = (int(gate.get("width", 0)), int(gate.get("height", 0)))
    min_ratio3 = float(gate.get("min_ratio_gt3_rgb", -1.0))
    min_ratio8 = float(gate.get("min_ratio_gt8_rgb", -1.0))
    min_bbox_w = int(gate.get("min_bbox_width_px", 0))
    min_bbox_h = int(gate.get("min_bbox_height_px", 0))
    if expected_size != (1280, 720):
        fail(f"unexpected frozen size {expected_size}")
    if abs(min_ratio3 - 0.02) > 1e-9 or abs(min_ratio8 - 0.01) > 1e-9:
        fail("frozen ratio thresholds drifted")
    if (min_bbox_w, min_bbox_h) != (300, 260):
        fail("frozen bbox thresholds drifted")

    before = Image.open(before_path).convert("RGB")
    after = Image.open(after_path).convert("RGB")
    if before.size != expected_size or after.size != expected_size:
        fail(f"image size mismatch before={before.size} after={after.size} expected={expected_size}")

    before_px = before.load()
    after_px = after.load()
    width, height = expected_size
    changed3 = 0
    changed8 = 0
    min_x, min_y = width, height
    max_x = max_y = -1

    for y in range(height):
        for x in range(width):
            a = before_px[x, y]
            b = after_px[x, y]
            delta = max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
            if delta > 3:
                changed3 += 1
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
            if delta > 8:
                changed8 += 1

    total = width * height
    ratio3 = changed3 / total
    ratio8 = changed8 / total
    bbox_w = (max_x - min_x + 1) if max_x >= min_x else 0
    bbox_h = (max_y - min_y + 1) if max_y >= min_y else 0

    metrics = {
        "schema": "grand-bruxelles-brasseurs-wall-skin-ab-metrics-v1",
        "before": str(before_path),
        "after": str(after_path),
        "size": [width, height],
        "changed_gt3_rgb_pixels": changed3,
        "changed_gt8_rgb_pixels": changed8,
        "ratio_gt3_rgb": ratio3,
        "ratio_gt8_rgb": ratio8,
        "bbox": [min_x, min_y, max_x, max_y] if bbox_w else None,
        "bbox_width_px": bbox_w,
        "bbox_height_px": bbox_h,
        "frozen_thresholds": {
            "min_ratio_gt3_rgb": min_ratio3,
            "min_ratio_gt8_rgb": min_ratio8,
            "min_bbox_width_px": min_bbox_w,
            "min_bbox_height_px": min_bbox_h,
        },
        "shadow_disabled": True,
        "details": 0,
        "outward_offset_m": 0.0,
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2, sort_keys=True), encoding="utf-8")

    print(
        "BRASSEURS_WALL_SKIN_AB_METRICS "
        f"ratio3={ratio3 * 100:.4f}% ratio8={ratio8 * 100:.4f}% "
        f"bbox={bbox_w}x{bbox_h} changed3={changed3} changed8={changed8}"
    )

    failures = []
    if ratio3 < min_ratio3:
        failures.append(f"ratio3 {ratio3 * 100:.4f}% < {min_ratio3 * 100:.2f}%")
    if ratio8 < min_ratio8:
        failures.append(f"ratio8 {ratio8 * 100:.4f}% < {min_ratio8 * 100:.2f}%")
    if bbox_w < min_bbox_w:
        failures.append(f"bbox width {bbox_w} < {min_bbox_w}")
    if bbox_h < min_bbox_h:
        failures.append(f"bbox height {bbox_h} < {min_bbox_h}")
    if failures:
        fail("; ".join(failures))

    print("BRASSEURS_WALL_SKIN_AB_OK: frozen impact gate passed; human full-frame verdict still required")


if __name__ == "__main__":
    main()
