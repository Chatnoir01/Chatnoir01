#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "artifacts" / "visual"
BEFORE = ART / "osm_facade_roughness_before.png"
CONTROL = ART / "osm_facade_roughness_control.png"
AFTER = ART / "osm_facade_roughness_after.png"
EXPECTED = (1280, 720)


def fail(message: str) -> None:
    raise SystemExit(f"BRUSSELS_OSM_FACADE_ROUGHNESS_AB_FAIL: {message}")


def load(path: Path) -> Image.Image:
    if not path.is_file(): fail(f"missing {path.name}")
    image = Image.open(path).convert("RGB")
    if image.size != EXPECTED: fail(f"{path.name} size {image.size} != {EXPECTED}")
    return image


def metrics(a: Image.Image, b: Image.Image, threshold: int):
    diff = ImageChops.difference(a, b)
    mask = diff.convert("L").point(lambda p: 255 if p > threshold else 0)
    count = sum(1 for p in mask.getdata() if p)
    ratio = 100.0 * count / (EXPECTED[0] * EXPECTED[1])
    bbox = mask.getbbox()
    width = 0 if bbox is None else bbox[2] - bbox[0]
    height = 0 if bbox is None else bbox[3] - bbox[1]
    return ratio, width, height


before = load(BEFORE); control = load(CONTROL); after = load(AFTER)
control_ratio, control_w, control_h = metrics(before, control, 8)
if control_ratio < 1.0 or control_w < 220 or control_h < 120:
    fail(f"active facade control not player-visible: pct8={control_ratio:.4f} bbox={control_w}x{control_h}")
ratio3, width3, height3 = metrics(before, after, 3)
ratio8, _, _ = metrics(before, after, 8)
# Frozen before first roughness render: subtle response must be measurable but never become broad albedo-like mottling.
if ratio3 < 0.005:
    fail(f"roughness response too weak at >3 RGB: {ratio3:.4f}%")
if ratio3 > 2.0:
    fail(f"roughness response too broad: {ratio3:.4f}%")
if width3 < 120 or height3 < 40:
    fail(f"roughness response bbox too small: {width3}x{height3}")
print(
    "BRUSSELS_OSM_FACADE_ROUGHNESS_AB_OK: "
    f"pct3={ratio3:.4f} pct8={ratio8:.4f} bbox={width3}x{height3} "
    f"control_pct8={control_ratio:.4f} control_bbox={control_w}x{control_h}"
)
