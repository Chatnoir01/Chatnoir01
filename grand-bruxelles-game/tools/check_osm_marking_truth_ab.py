#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
BEFORE = ROOT / "artifacts/visual/osm_marking_truth_before.png"
AFTER = ROOT / "artifacts/visual/osm_marking_truth_after.png"
WIDTH, HEIGHT = 1280, 720
MIN_GT3 = 0.0020
MIN_GT8 = 0.0008
MIN_BBOX_W = 240
MIN_BBOX_H = 50


def fail(message: str) -> None:
    raise SystemExit(f"BRUSSELS_OSM_MARKING_TRUTH_AB_FAIL: {message}")


def main() -> None:
    if not BEFORE.exists() or not AFTER.exists():
        fail("capture missing")
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    if before.size != (WIDTH, HEIGHT) or after.size != (WIDTH, HEIGHT):
        fail(f"expected {WIDTH}x{HEIGHT}, got {before.size}/{after.size}")
    total = WIDTH * HEIGHT
    gt3 = 0
    gt8 = 0
    xs = []
    ys = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            a = before.getpixel((x, y))
            b = after.getpixel((x, y))
            delta = max(abs(a[i] - b[i]) for i in range(3))
            if delta > 3:
                gt3 += 1
                xs.append(x)
                ys.append(y)
            if delta > 8:
                gt8 += 1
    ratio3 = gt3 / total
    ratio8 = gt8 / total
    if ratio3 < MIN_GT3:
        fail(f">3 ratio {ratio3:.6f} < {MIN_GT3:.6f}")
    if ratio8 < MIN_GT8:
        fail(f">8 ratio {ratio8:.6f} < {MIN_GT8:.6f}")
    if not xs:
        fail("no changed bbox")
    bbox_w = max(xs) - min(xs) + 1
    bbox_h = max(ys) - min(ys) + 1
    if bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        fail(f"bbox {bbox_w}x{bbox_h} < {MIN_BBOX_W}x{MIN_BBOX_H}")
    print(
        "BRUSSELS_OSM_MARKING_TRUTH_AB_OK: "
        f">3={ratio3*100:.4f}% >8={ratio8*100:.4f}% bbox={bbox_w}x{bbox_h} "
        "thresholds_locked=true"
    )


if __name__ == "__main__":
    main()
