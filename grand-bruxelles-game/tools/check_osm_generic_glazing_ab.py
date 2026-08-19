#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BEFORE = ROOT / "artifacts/visual/osm_generic_glazing_before.png"
AFTER = ROOT / "artifacts/visual/osm_generic_glazing_after.png"
WIDTH, HEIGHT = 1280, 720
MIN_GT3 = 0.0050
MIN_GT8 = 0.0020
MIN_BBOX_W = 300
MIN_BBOX_H = 120


def fail(message: str) -> None:
    raise SystemExit(f"BRUSSELS_OSM_GENERIC_GLAZING_VISUAL_FAIL: {message}")


def main() -> None:
    if not BEFORE.exists() or not AFTER.exists():
        fail("A/B evidence missing")
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    if before.size != (WIDTH, HEIGHT) or after.size != (WIDTH, HEIGHT):
        fail(f"expected {WIDTH}x{HEIGHT} evidence")

    p0 = before.load(); p1 = after.load()
    gt3 = gt8 = 0
    xs, ys = [], []
    total = WIDTH * HEIGHT
    for y in range(HEIGHT):
        for x in range(WIDTH):
            a = p0[x, y]; b = p1[x, y]
            delta = max(abs(a[i] - b[i]) for i in range(3))
            if delta > 3:
                gt3 += 1; xs.append(x); ys.append(y)
            if delta > 8:
                gt8 += 1
    frac3 = gt3 / total
    frac8 = gt8 / total
    if not xs:
        fail("zero changed pixels")
    bbox_w = max(xs) - min(xs) + 1
    bbox_h = max(ys) - min(ys) + 1
    print(f"BRUSSELS_OSM_GENERIC_GLAZING_METRICS: gt3={frac3:.6%} gt8={frac8:.6%} bbox={bbox_w}x{bbox_h}")
    if frac3 < MIN_GT3:
        fail(f">3 RGB coverage {frac3:.4%} below locked {MIN_GT3:.2%}")
    if frac8 < MIN_GT8:
        fail(f">8 RGB coverage {frac8:.4%} below locked {MIN_GT8:.2%}")
    if bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        fail(f"bbox {bbox_w}x{bbox_h} below locked {MIN_BBOX_W}x{MIN_BBOX_H}")
    print("BRUSSELS_OSM_GENERIC_GLAZING_VISUAL_OK")


if __name__ == "__main__":
    main()
