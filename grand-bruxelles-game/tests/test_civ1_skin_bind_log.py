#!/usr/bin/env python3
import importlib.util
from pathlib import Path

P = Path(__file__).parents[1] / "tools" / "assess_civ1_skin_bind_log.py"
s = importlib.util.spec_from_file_location("m", P)
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)

good = m.assess("Godot Engine v4.7.1\nCIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK\n")
assert good["diagnostic_complete"] is True
assert good["skin_bind_integrity_verified"] is True
assert good["verdict"] == "ALLOW_DIAGNOSTIC_ONLY"
assert good["runtime_authorized"] is False and good["visual_approval_claimed"] is False

bad = m.assess(
    "ERROR: Skin bind bone mixamorig_Hips not found in Skeleton3D\n"
    "ERROR: Skin bind bone mixamorig_RightFoot not found in Skeleton3D\n"
    "CIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK\n"
)
assert bad["diagnostic_complete"] is True
assert bad["skin_bind_integrity_verified"] is False
assert bad["verdict"] == "BLOCK_SKIN_BIND_INTEGRITY"
assert bad["error_count"] == 2
assert "mixamorig_Hips" in bad["affected_bones"]
assert "mixamorig_RightFoot" in bad["affected_bones"]

# Exact wording emitted by the native Godot 4.7.1 probe. This used to evade
# the generic regexes because the line says "has no bone by that name" rather
# than "not found"/"missing", producing a false ALLOW_DIAGNOSTIC_ONLY.
native_named_bind = m.assess(
    "ERROR: Skin bind #0 contains named bind 'mixamorig_Hips' but Skeleton3D has no bone by that name.\n"
    "ERROR: Skin bind #46 contains named bind 'mixamorig_LeftFoot' but Skeleton3D has no bone by that name.\n"
    "ERROR: Skin bind #50 contains named bind 'mixamorig_RightFoot' but Skeleton3D has no bone by that name.\n"
    "CIV1_GLOBAL_CHAIN_DIAGNOSTIC_OK\n"
)
assert native_named_bind["diagnostic_complete"] is True
assert native_named_bind["skin_bind_integrity_verified"] is False
assert native_named_bind["verdict"] == "BLOCK_SKIN_BIND_INTEGRITY"
assert native_named_bind["error_count"] == 3
assert "mixamorig_Hips" in native_named_bind["affected_bones"]
assert "mixamorig_LeftFoot" in native_named_bind["affected_bones"]
assert "mixamorig_RightFoot" in native_named_bind["affected_bones"]

incomplete = m.assess("Godot Engine v4.7.1\nprobe started\n")
assert incomplete["diagnostic_complete"] is False
assert incomplete["skin_bind_integrity_verified"] is False
assert incomplete["verdict"] == "BLOCK_INCOMPLETE_DIAGNOSTIC"
assert incomplete["error_count"] == 0

incomplete_bad = m.assess(
    "ERROR: Skin bind bone mixamorig_LeftFoot missing in Skeleton3D\n"
)
assert incomplete_bad["diagnostic_complete"] is False
assert incomplete_bad["skin_bind_integrity_verified"] is False
assert incomplete_bad["verdict"] == "BLOCK_SKIN_BIND_INTEGRITY"
print("CIV1_SKIN_BIND_LOG_CONTRACT_OK")
