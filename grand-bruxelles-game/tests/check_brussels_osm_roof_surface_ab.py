from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BEFORE = ROOT / "artifacts/visual/brussels_osm_roof_surface_before.png"
AFTER = ROOT / "artifacts/visual/brussels_osm_roof_surface_after.png"
MIN_GT3_RATIO = 0.0075
MIN_GT8_RATIO = 0.0020
MIN_BBOX_WIDTH = 350
MIN_BBOX_HEIGHT = 90


def main() -> None:
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    assert before.size == (1280, 720) and after.size == (1280, 720)
    changed3 = []
    changed8 = 0
    for y in range(720):
        for x in range(1280):
            a = before.getpixel((x, y))
            b = after.getpixel((x, y))
            d = max(abs(a[i] - b[i]) for i in range(3))
            if d > 3:
                changed3.append((x, y))
            if d > 8:
                changed8 += 1
    total = 1280 * 720
    ratio3 = len(changed3) / total
    ratio8 = changed8 / total
    assert ratio3 >= MIN_GT3_RATIO, f"BRUSSELS_OSM_ROOF_SURFACE_AB_FAIL: >3 ratio {ratio3}"
    assert ratio8 >= MIN_GT8_RATIO, f"BRUSSELS_OSM_ROOF_SURFACE_AB_FAIL: >8 ratio {ratio8}"
    xs = [p[0] for p in changed3]
    ys = [p[1] for p in changed3]
    width = max(xs) - min(xs) + 1
    height = max(ys) - min(ys) + 1
    assert width >= MIN_BBOX_WIDTH and height >= MIN_BBOX_HEIGHT, f"BRUSSELS_OSM_ROOF_SURFACE_AB_FAIL: bbox {width}x{height}"
    print(f"BRUSSELS_OSM_ROOF_SURFACE_AB_OK: changed_gt3={ratio3*100:.4f}% changed_gt8={ratio8*100:.4f}% bbox={width}x{height} thresholds_locked=true")


if __name__ == "__main__":
    main()
