from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
BEFORE = ROOT / "artifacts/visual/brussels_osm_roof_surface_before.png"
AFTER = ROOT / "artifacts/visual/brussels_osm_roof_surface_after.png"

# Fixed before first visual run. Do not lower these to rescue the lot.
MIN_GT3_RATIO = 0.0075
MIN_GT8_RATIO = 0.0020
MIN_BBOX_WIDTH = 350
MIN_BBOX_HEIGHT = 90


def main() -> None:
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    if before.size != (1280, 720) or after.size != before.size:
        raise SystemExit(f"BRUSSELS_OSM_ROOF_SURFACE_VISUAL_FAIL invalid frame size: {before.size} / {after.size}")
    diff = ImageChops.difference(before, after)
    pixels = list(diff.getdata())
    total = len(pixels)
    gt3 = sum(1 for r, g, b in pixels if max(r, g, b) > 3)
    gt8 = sum(1 for r, g, b in pixels if max(r, g, b) > 8)
    gt3_ratio = gt3 / total
    gt8_ratio = gt8 / total
    mask = diff.convert("L").point(lambda value: 255 if value > 3 else 0)
    bbox = mask.getbbox()
    width = 0 if bbox is None else bbox[2] - bbox[0]
    height = 0 if bbox is None else bbox[3] - bbox[1]
    print("BRUSSELS_OSM_ROOF_SURFACE_AB_METRICS: " f"gt3={gt3_ratio:.6%} gt8={gt8_ratio:.6%} bbox={bbox} size={width}x{height}")
    if gt3_ratio < MIN_GT3_RATIO:
        raise SystemExit("BRUSSELS_OSM_ROOF_SURFACE_VISUAL_FAIL weak >3 RGB impact")
    if gt8_ratio < MIN_GT8_RATIO:
        raise SystemExit("BRUSSELS_OSM_ROOF_SURFACE_VISUAL_FAIL weak >8 RGB impact")
    if width < MIN_BBOX_WIDTH or height < MIN_BBOX_HEIGHT:
        raise SystemExit("BRUSSELS_OSM_ROOF_SURFACE_VISUAL_FAIL impact bbox too small")
    print("BRUSSELS_OSM_ROOF_SURFACE_AB_OK")

if __name__ == "__main__":
    main()
