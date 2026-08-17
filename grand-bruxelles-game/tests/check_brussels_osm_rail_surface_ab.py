from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BEFORE = ROOT / "artifacts/visual/brussels_osm_rail_surface_before.png"
AFTER = ROOT / "artifacts/visual/brussels_osm_rail_surface_after.png"

MIN_GT3_RATIO = 0.0050
MIN_GT8_RATIO = 0.0020
MIN_BBOX_WIDTH = 300
MIN_BBOX_HEIGHT = 70


def main():
    assert BEFORE.exists(), f"missing BEFORE: {BEFORE}"
    assert AFTER.exists(), f"missing AFTER: {AFTER}"
    before = Image.open(BEFORE).convert("RGB")
    after = Image.open(AFTER).convert("RGB")
    assert before.size == (1280, 720) and after.size == (1280, 720)

    gt3 = 0
    gt8 = 0
    min_x = 1280
    min_y = 720
    max_x = -1
    max_y = -1
    for index, (a, b) in enumerate(zip(before.getdata(), after.getdata())):
        delta = max(abs(int(a[0]) - int(b[0])), abs(int(a[1]) - int(b[1])), abs(int(a[2]) - int(b[2])))
        if delta > 3:
            gt3 += 1
            x = index % 1280
            y = index // 1280
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)
        if delta > 8:
            gt8 += 1

    total = 1280 * 720
    ratio3 = gt3 / total
    ratio8 = gt8 / total
    width = 0 if max_x < min_x else max_x - min_x + 1
    height = 0 if max_y < min_y else max_y - min_y + 1
    print(
        "BRUSSELS_OSM_RAIL_SURFACE_AB: "
        f"gt3={ratio3:.6%} gt8={ratio8:.6%} bbox={width}x{height} "
        f"required={MIN_GT3_RATIO:.2%}/{MIN_GT8_RATIO:.2%}/{MIN_BBOX_WIDTH}x{MIN_BBOX_HEIGHT}"
    )
    assert ratio3 >= MIN_GT3_RATIO, f"rail A/B too small at >3 RGB: {ratio3:.6%}"
    assert ratio8 >= MIN_GT8_RATIO, f"rail A/B too small at >8 RGB: {ratio8:.6%}"
    assert width >= MIN_BBOX_WIDTH and height >= MIN_BBOX_HEIGHT, f"rail A/B bbox too small: {width}x{height}"
    print("BRUSSELS_OSM_RAIL_SURFACE_AB_OK")


if __name__ == "__main__":
    main()
