#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
TOOL = HERE / 'tools' / 'patch_civ1_leftfoot_contact_raster_samples.py'
spec = importlib.util.spec_from_file_location('contact_patch', TOOL)
assert spec and spec.loader
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def main() -> int:
    source = '''extends SceneTree\nconst TARGET_SAMPLES := [114, 115, 116, 117, 118]\nvar verdict := "AMELIORER_LEFTFOOT_LANDMARK_RASTERS_CAPTURED_NO_PROMOTION"\n'''
    patched = m.patch_text(source)
    assert 'const TARGET_SAMPLES := [118, 119, 0, 1, 2]' in patched
    assert 'AMELIORER_LEFTFOOT_CONTACT_RASTERS_CAPTURED_NO_PROMOTION' in patched
    assert '[114, 115, 116, 117, 118]' not in patched
    try:
        m.patch_text(patched)
    except ValueError:
        pass
    else:
        raise AssertionError('patch must fail closed if applied twice')
    drifted = source.replace('[114, 115, 116, 117, 118]', '[113, 114, 115, 116, 117]')
    try:
        m.patch_text(drifted)
    except ValueError:
        pass
    else:
        raise AssertionError('patch must fail closed when upstream sample contract drifts')
    print('CIV1_LEFTFOOT_CONTACT_RASTER_SAMPLE_PATCH_TEST_OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
