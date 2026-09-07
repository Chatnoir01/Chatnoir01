#!/usr/bin/env python3
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
P = ROOT / "tools" / "build_civ1_rightfoot_contact_witness.py"
WORKFLOW = REPO / ".github" / "workflows" / "grand-bruxelles-civ1-rightfoot-contact-witness.yml"
spec = importlib.util.spec_from_file_location("contact_builder", P)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

witness = '''grand-bruxelles-civ1-rightfoot-landmark-witness-v1\n1280 720 45.0 [2.0, 4.0, 8.0]\nconst SAMPLES := [114, 115, 116, 117, 118]\nMARKER_RADIUS_M := 0.025\nmarker_mat.no_depth_test=true\nRightFoot\n'''
analyzer = '''grand-bruxelles-civ1-rightfoot-landmark-raster-analysis-v1\nDISTANCES=(2,4,8)\nSAMPLES=(114,115,116,117,118)\nMAX_CENTROID_ERROR_PX=1.5\nMAX_PATH_REL_ERROR=0.25\nrightfoot\n'''

w, a = m.build(witness, analyzer)
m.verify(w, a)
assert "[68, 69, 70, 71]" in w
assert "SAMPLES=(68,69,70,71)" in a
for token in ("1280", "720", "45.0", "[2.0, 4.0, 8.0]", "MARKER_RADIUS_M := 0.025", "marker_mat.no_depth_test=true"):
    assert token in w
for token in ("MAX_CENTROID_ERROR_PX=1.5", "MAX_PATH_REL_ERROR=0.25"):
    assert token in a

# Causal RED cases: source drift and duplicate source token must fail closed.
for bad_w in (witness.replace("[114, 115, 116, 117, 118]", "[114, 115]"), witness + "[114, 115, 116, 117, 118]\n"):
    try:
        m.build(bad_w, analyzer)
    except ValueError:
        pass
    else:
        raise AssertionError("drifted/ambiguous witness sample source accepted")

bad_a = analyzer.replace("MAX_CENTROID_ERROR_PX=1.5", "MAX_CENTROID_ERROR_PX=1.6")
try:
    m.build(witness, bad_a)
except ValueError:
    pass
else:
    raise AssertionError("centroid rail drift accepted")

# Regression for run 34066576671: a scratch Godot project containing only the
# stripped body cannot load res://game/main.tscn. The contact witness must execute
# from a copy of the exact-current-main canonical project and verify the scene is
# present before starting Godot.
workflow = WORKFLOW.read_text(encoding="utf-8")
required = (
    'CANONICAL_PROJECT=/tmp/civ1contact/canonical-project',
    'cp -a grand-bruxelles-game "$CANONICAL_PROJECT"',
    'test -f "$CANONICAL_PROJECT/game/main.tscn"',
    'cp /tmp/civ1contact/source/civ1_body.glb "$CANONICAL_PROJECT/civ1_body.glb"',
    'cp /tmp/civ1contact/evidence/right-contact-witness.gd "$CANONICAL_PROJECT/gb_rightfoot_contact.gd"',
    '--path "$CANONICAL_PROJECT"',
)
for token in required:
    assert token in workflow, f"canonical sandbox regression missing: {token}"
assert '--path /tmp/civ1contact/project' not in workflow, "rejected scratch sandbox path returned"

print("CIV1_RIGHTFOOT_CONTACT_WITNESS_REGRESSION_OK")
