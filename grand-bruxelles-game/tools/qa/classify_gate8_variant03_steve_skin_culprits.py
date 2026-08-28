#!/usr/bin/env python3
import json
import sys
from pathlib import Path

EXPECTED_ARTIFACT = 9661224043
EXPECTED_DIGEST = "sha256:c44b7a008e646cdcbc2b6ef41d37e9586855f45f43d73e193dec0287e3680bca"


def dominant(influences):
    assert influences, "missing influences"
    return max(influences, key=lambda item: float(item["weight"]))["bone"]


def bones(influences):
    return {str(item["bone"]) for item in influences if float(item["weight"]) > 0.0}


def classify(result):
    skin = result["metrics"]["skin_space"]
    absolute = skin["max_absolute_edge"]
    stretch = skin["max_stretch_edge"]
    compression = skin["min_compression_edge"]
    abs_pair = {dominant(absolute["vertex_a_influences"]), dominant(absolute["vertex_b_influences"])}
    assert abs_pair == {"spine_03", "upperarm_r"}, abs_pair
    assert float(absolute["absolute_change_m"]) > 0.25
    stretch_bones = bones(stretch["vertex_a_influences"]) | bones(stretch["vertex_b_influences"])
    assert {"lowerarm_r", "hand_r"}.issubset(stretch_bones), stretch_bones
    assert float(stretch["ratio"]) > 3.0
    compression_bones = bones(compression["vertex_a_influences"]) | bones(compression["vertex_b_influences"])
    assert {"upperarm_r", "clavicle_r"}.issubset(compression_bones), compression_bones
    assert "spine_03" in compression_bones, compression_bones
    assert float(compression["ratio"]) < 0.25
    return {
        "format": "grand-bruxelles-gate8-variant03-steve-skin-culprit-classification-v1",
        "source_artifact_id": EXPECTED_ARTIFACT,
        "source_artifact_digest": EXPECTED_DIGEST,
        "state": "MULTIPLE_RIGHT_ARM_SKIN_BOUNDARIES_CONFIRMED",
        "families": {
            "shoulder_torso": {"record":"max_absolute_edge","sample":int(absolute["sample"]),"mesh":absolute["mesh"],"dominant_boundary":sorted(abs_pair),"absolute_change_m":float(absolute["absolute_change_m"])},
            "forearm_hand": {"record":"max_stretch_edge","sample":int(stretch["sample"]),"mesh":stretch["mesh"],"required_bones":["lowerarm_r","hand_r"],"stretch_ratio":float(stretch["ratio"])},
            "upperarm_clavicle": {"record":"min_compression_edge","sample":int(compression["sample"]),"mesh":compression["mesh"],"required_bones":["upperarm_r","clavicle_r","spine_03"],"compression_ratio":float(compression["ratio"])},
        },
        "next_ab": ["decompose spine_03↔upperarm_r at sample 10","decompose lowerarm_r↔hand_r at sample 0","decompose upperarm_r↔clavicle_r/spine_03 at sample 2"],
        "retarget_change_authorized": False,
        "skin_weight_change_authorized": False,
        "production_authorized": False,
    }


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: classify_gate8_variant03_steve_skin_culprits.py godot-result.json output.json")
    result = json.loads(Path(sys.argv[1]).read_text())
    assert result["mechanical_state"] == "BLOCKED_CANONICAL_NATIVE_WALK_MECHANICS"
    assert result["production_authorized"] is False
    classified = classify(result)
    Path(sys.argv[2]).write_text(json.dumps(classified, indent=2, sort_keys=True) + "\n")
    print("GATE8_V03_STEVE_CULPRIT_CLASSIFICATION_OK state=%s" % classified["state"])

if __name__ == "__main__":
    main()
