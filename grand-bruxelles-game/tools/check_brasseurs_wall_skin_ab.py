#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops

MIN_RATIO_GT3 = 0.02
MIN_RATIO_GT8 = 0.01
MIN_BBOX_W = 300
MIN_BBOX_H = 260
EXPECTED_SIZE = (1280, 720)
OUT = Path('/tmp/brasseurs-wall-ab-metrics.json')


def main() -> int:
    if len(sys.argv) != 3:
        print('usage: check_brasseurs_wall_skin_ab.py BEFORE AFTER', file=sys.stderr)
        return 2
    before = Image.open(sys.argv[1]).convert('RGB')
    after = Image.open(sys.argv[2]).convert('RGB')
    if before.size != EXPECTED_SIZE or after.size != EXPECTED_SIZE:
        print(f'BRASSEURS_WALL_SKIN_VISUAL_FAIL: expected {EXPECTED_SIZE}, got {before.size}/{after.size}', file=sys.stderr)
        return 1

    b = before.load()
    a = after.load()
    total = EXPECTED_SIZE[0] * EXPECTED_SIZE[1]
    changed3 = changed8 = 0
    min_x = EXPECTED_SIZE[0]
    min_y = EXPECTED_SIZE[1]
    max_x = max_y = -1
    for y in range(EXPECTED_SIZE[1]):
        for x in range(EXPECTED_SIZE[0]):
            delta = max(abs(a[x, y][i] - b[x, y][i]) for i in range(3))
            if delta > 3:
                changed3 += 1
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
            if delta > 8:
                changed8 += 1
    ratio3 = changed3 / total
    ratio8 = changed8 / total
    bbox_w = 0 if max_x < min_x else max_x - min_x + 1
    bbox_h = 0 if max_y < min_y else max_y - min_y + 1
    metrics = {
        'schema': 'grand-bruxelles-brasseurs-wall-skin-ab-v1',
        'size': list(EXPECTED_SIZE),
        'changed_gt3': changed3,
        'changed_gt8': changed8,
        'ratio_gt3': ratio3,
        'ratio_gt8': ratio8,
        'bbox': [min_x, min_y, max_x, max_y] if bbox_w else None,
        'bbox_width': bbox_w,
        'bbox_height': bbox_h,
        'thresholds': {
            'min_ratio_gt3': MIN_RATIO_GT3,
            'min_ratio_gt8': MIN_RATIO_GT8,
            'min_bbox_width': MIN_BBOX_W,
            'min_bbox_height': MIN_BBOX_H,
        },
    }
    OUT.write_text(json.dumps(metrics, indent=2) + '\n', encoding='utf-8')
    passed = ratio3 >= MIN_RATIO_GT3 and ratio8 >= MIN_RATIO_GT8 and bbox_w >= MIN_BBOX_W and bbox_h >= MIN_BBOX_H
    print('BRASSEURS_WALL_SKIN_METRICS ' + json.dumps(metrics, sort_keys=True))
    if not passed:
        print('BRASSEURS_WALL_SKIN_VISUAL_FAIL: frozen impact gate not met', file=sys.stderr)
        return 1
    print('BRASSEURS_WALL_SKIN_VISUAL_OK: frozen impact gate met')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
