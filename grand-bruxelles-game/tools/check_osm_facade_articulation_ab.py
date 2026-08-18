#!/usr/bin/env python3
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
BEFORE = ROOT / "artifacts/visual/osm_facade_articulation_before.png"
AFTER = ROOT / "artifacts/visual/osm_facade_articulation_after.png"
MIN_RATIO_3 = 0.0050
MIN_RATIO_8 = 0.0020
MIN_BBOX_W = 300
MIN_BBOX_H = 120

def fail(message: str) -> None:
    raise SystemExit(f"BRUSSELS_OSM_FACADE_ARTICULATION_VISUAL_FAIL: {message}")

def changed_mask(before: Image.Image, after: Image.Image, threshold: int):
    b, a = before.convert("RGB"), after.convert("RGB")
    if b.size != (1280, 720) or a.size != (1280, 720): fail(f"expected 1280x720 captures, got {b.size} and {a.size}")
    bp, ap = b.load(), a.load(); min_x, min_y = 1280, 720; max_x = max_y = -1; count = 0
    for y in range(720):
        for x in range(1280):
            br,bg,bb = bp[x,y]; ar,ag,ab = ap[x,y]
            if max(abs(br-ar), abs(bg-ag), abs(bb-ab)) > threshold:
                count += 1; min_x=min(min_x,x); min_y=min(min_y,y); max_x=max(max_x,x); max_y=max(max_y,y)
    return count/(1280*720), None if count == 0 else (min_x,min_y,max_x+1,max_y+1)

def main() -> None:
    if not BEFORE.exists() or not AFTER.exists(): fail("A/B PNG missing")
    before, after = Image.open(BEFORE), Image.open(AFTER)
    ratio3, bbox = changed_mask(before, after, 3); ratio8, _ = changed_mask(before, after, 8)
    if bbox is None: fail("candidate produces zero changed pixels")
    width, height = bbox[2]-bbox[0], bbox[3]-bbox[1]
    print(f"BRUSSELS_OSM_FACADE_ARTICULATION_VISUAL_METRICS: changed_gt3={ratio3*100:.4f}% changed_gt8={ratio8*100:.4f}% bbox={width}x{height}")
    if ratio3 < MIN_RATIO_3: fail(f">3 RGB ratio {ratio3*100:.4f}% below locked {MIN_RATIO_3*100:.2f}%")
    if ratio8 < MIN_RATIO_8: fail(f">8 RGB ratio {ratio8*100:.4f}% below locked {MIN_RATIO_8*100:.2f}%")
    if width < MIN_BBOX_W or height < MIN_BBOX_H: fail(f"bbox {width}x{height} below locked {MIN_BBOX_W}x{MIN_BBOX_H}")
    print(f"BRUSSELS_OSM_FACADE_ARTICULATION_VISUAL_OK: gt3={ratio3*100:.4f}% gt8={ratio8*100:.4f}% bbox={width}x{height}")
if __name__ == "__main__": main()
