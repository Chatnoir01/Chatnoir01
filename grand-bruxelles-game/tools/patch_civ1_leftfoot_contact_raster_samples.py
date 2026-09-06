#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

OLD = 'const TARGET_SAMPLES := [114, 115, 116, 117, 118]'
NEW = 'const TARGET_SAMPLES := [118, 119, 0, 1, 2]'
OLD_VERDICT = 'AMELIORER_LEFTFOOT_LANDMARK_RASTERS_CAPTURED_NO_PROMOTION'
NEW_VERDICT = 'AMELIORER_LEFTFOOT_CONTACT_RASTERS_CAPTURED_NO_PROMOTION'


def patch_text(text: str) -> str:
    if text.count(OLD) != 1:
        raise ValueError(f'expected exactly one historical identity sample declaration, found {text.count(OLD)}')
    if text.count(OLD_VERDICT) != 1:
        raise ValueError(f'expected exactly one historical witness verdict, found {text.count(OLD_VERDICT)}')
    patched = text.replace(OLD, NEW).replace(OLD_VERDICT, NEW_VERDICT)
    if patched.count(NEW) != 1 or patched.count(NEW_VERDICT) != 1:
        raise ValueError('contact raster patch did not apply exactly once')
    return patched


def main() -> int:
    if len(sys.argv) != 2:
        print('usage: patch_civ1_leftfoot_contact_raster_samples.py WITNESS_GD', file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    path.write_text(patch_text(path.read_text(encoding='utf-8')), encoding='utf-8')
    print('CIV1_LEFTFOOT_CONTACT_RASTER_SAMPLE_PATCH_OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
