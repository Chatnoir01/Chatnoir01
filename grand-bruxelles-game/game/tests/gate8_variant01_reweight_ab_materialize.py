from __future__ import annotations

import pathlib
import sys

if len(sys.argv) != 5:
    raise SystemExit("usage: materialize.py SOURCE_GD OUT_GD OUTPUT_JSON PRUNE_THRESHOLD")

src_path = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
output_json = sys.argv[3]
prune = float(sys.argv[4])

text = src_path.read_text()
required = [
    'const TARGET_SCENE := "res://assets/npc_gate_06.glb"',
    'const EXPECTED_VERTICES := 24073',
    'const MICROPOSE_DEG := 5.0',
    'const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25',
    'const MAX_EDGE_STRETCH_RATIO := 3.0',
    'const MIN_EDGE_COMPRESSION_RATIO := 0.25',
    'var w := float(weights[off])',
    '"candidate_variant":6',
]
for token in required:
    if token not in text:
        raise SystemExit(f"validated harness drift: missing {token!r}")

text = text.replace('res://assets/npc_gate_06.glb', 'res://assets/npc_gate_01.glb')
text = text.replace('res://gate8_variant06_target_micropose_skin_result.json', f'res://{output_json}')
text = text.replace('EXPECTED_VERTICES := 24073', 'EXPECTED_VERTICES := 21044')
text = text.replace('"candidate_variant":6', '"candidate_variant":1')
text = text.replace('grand-bruxelles-gate8-variant06-target-micropose-skin-v1', 'grand-bruxelles-gate8-variant01-reweight-ab-measurement-v1')
text = text.replace('REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED', 'REWEIGHT_AB_STILL_BLOCKED')

marker = 'const COMMON_ROTATION_EPS_DEG := 0.01\n'
if marker not in text:
    raise SystemExit('validated harness drift: prune constant insertion marker missing')
text = text.replace(marker, marker + f'const MEASUREMENT_PRUNE_WEIGHT := {prune:.8f}\n', 1)

needle = '        var w := float(weights[off])\n        if w <= 0.0:\n'
replacement = (
    '        var w := float(weights[off])\n'
    '        if w > 0.0 and w < MEASUREMENT_PRUNE_WEIGHT:\n'
    '            w = 0.0\n'
    '        if w <= 0.0:\n'
)
if needle not in text:
    raise SystemExit('validated harness drift: weight-loop marker missing')
text = text.replace(needle, replacement, 1)

meta_needle = '        "measurement":"target_only_controlled_micropose_cpu_skin_space",\n'
meta_repl = (
    meta_needle
    + '        "measurement_weight_prune_threshold":MEASUREMENT_PRUNE_WEIGHT,\n'
    + '        "measurement_only_weight_operator":true,\n'
    + '        "canonical_glb_modified":false,\n'
)
if meta_needle not in text:
    raise SystemExit('validated harness drift: metadata marker missing')
text = text.replace(meta_needle, meta_repl, 1)

if 'RetargetModifier3D' in text:
    raise SystemExit('retarget rail violated')
if 'MICROPOSE_DEG := 5.0' not in text:
    raise SystemExit('micropose threshold drift')
if 'MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25' not in text or 'MAX_EDGE_STRETCH_RATIO := 3.0' not in text or 'MIN_EDGE_COMPRESSION_RATIO := 0.25' not in text:
    raise SystemExit('frozen skin gates drift')

out_path.write_text(text)
