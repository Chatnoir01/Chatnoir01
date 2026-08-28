from __future__ import annotations

import argparse
from pathlib import Path

EXPECTED_SOURCE_SHA = "73feaa653d3d66bbd46cd218576e7d9585161ae2"
EXPECTED_SOURCE_PATH = "grand-bruxelles-game/game/tests/gate8_variant06_target_micropose_skin_test.gd"

REPLACEMENTS = {
    "npc_gate_06.glb": "npc_gate_07.glb",
    "gate8_variant06_target_micropose_skin_result.json": "gate8_variant07_target_micropose_skin_result.json",
    "EXPECTED_VERTICES := 24073": "EXPECTED_VERTICES := 22642",
    "variant06": "variant07",
    "Variant06": "Variant07",
    "VARIANT06": "VARIANT07",
    "candidate_variant\":6": "candidate_variant\":7",
    "REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED": "REJECT_VARIANT07_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED",
}

REQUIRED_SOURCE_TOKENS = (
    'const MICROPOSE_DEG := 5.0',
    'const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25',
    'const MAX_EDGE_STRETCH_RATIO := 3.0',
    'const MIN_EDGE_COMPRESSION_RATIO := 0.25',
    'const EXPECTED_TARGET_BONES := 53',
    'const EXPECTED_VERTICES := 24073',
    '"candidate_variant":6',
    '"source_animation_used":false',
    '"retarget_applied":false',
    '"target_skin_modified":false',
    '"target_rest_modified":false',
    '"threshold_changed":false',
)

REQUIRED_OUTPUT_TOKENS = (
    'res://assets/npc_gate_07.glb',
    'gate8_variant07_target_micropose_skin_result.json',
    'const EXPECTED_VERTICES := 22642',
    '"candidate_variant":7',
    'grand-bruxelles-gate8-variant07-target-micropose-skin-v1',
    'REJECT_VARIANT07_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED',
)

FORBIDDEN_OUTPUT_TOKENS = (
    'npc_gate_06.glb',
    'EXPECTED_VERTICES := 24073',
    '"candidate_variant":6',
    'REJECT_VARIANT06_DYNAMIC_TARGET_SKIN_OR_REWEIGHT_REQUIRED',
    'RetargetModifier3D',
)


def materialize(source: str) -> str:
    for token in REQUIRED_SOURCE_TOKENS:
        if token not in source:
            raise AssertionError(f"validated harness drift: missing {token!r}")

    output = source
    for old, new in REPLACEMENTS.items():
        output = output.replace(old, new)

    for token in REQUIRED_OUTPUT_TOKENS:
        if token not in output:
            raise AssertionError(f"variant07 materialization incomplete: missing {token!r}")
    for token in FORBIDDEN_OUTPUT_TOKENS:
        if token in output:
            raise AssertionError(f"variant07 materialization leaked forbidden token {token!r}")

    if output.count('const MICROPOSE_DEG := 5.0') != 1:
        raise AssertionError("micropose amplitude drifted")
    if output.count('const MAX_EDGE_ABSOLUTE_CHANGE_M := 0.25') != 1:
        raise AssertionError("edge threshold drifted")
    if output.count('const MAX_EDGE_STRETCH_RATIO := 3.0') != 1:
        raise AssertionError("stretch threshold drifted")
    if output.count('const MIN_EDGE_COMPRESSION_RATIO := 0.25') != 1:
        raise AssertionError("compression threshold drifted")
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.source.read_text(encoding="utf-8")
    rendered = materialize(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered, encoding="utf-8")
    print("VARIANT07_MICROPOSE_HARNESS_MATERIALIZED_OK")


if __name__ == "__main__":
    main()
