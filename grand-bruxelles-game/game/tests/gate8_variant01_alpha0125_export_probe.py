#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

import bpy

SOURCE_DIR = Path(os.environ["GATE8_SOURCE_DIR"]).resolve()
EVIDENCE_PATH = Path(os.environ["GATE8_REMATCH_EVIDENCE"]).resolve()
RESULT_PATH = Path(os.environ["GATE8_ALPHA_RESULT"]).resolve()
ALPHA = 0.125
FOCUS_VERTICES = (377, 378, 379, 486, 599, 601, 615, 864)
OBJECT_FRAGMENT = "female_sportsuit01"

sys.path.insert(0, str(SOURCE_DIR))
import generate_mpfb_gate8_export_ready_glbs as ready  # noqa: E402


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    return [root, *ready.base.descendants(root)]


def find_sportsuit(root: bpy.types.Object) -> bpy.types.Object:
    matches = [
        obj for obj in descendants(root)
        if obj.type == "MESH" and OBJECT_FRAGMENT in obj.name.lower()
    ]
    if len(matches) != 1:
        raise RuntimeError(f"expected one sportsuit under {root.name}, got {[o.name for o in matches]}")
    return matches[0]


def set_vertex_weights(obj: bpy.types.Object, vertex_index: int, weights: dict[str, float]) -> None:
    for group in obj.vertex_groups:
        try:
            group.remove([vertex_index])
        except RuntimeError:
            pass
    positive = {name: float(value) for name, value in weights.items() if float(value) > 0.0}
    total = sum(positive.values())
    if total <= 1e-12:
        raise RuntimeError(f"zero blended deform weight at vertex {vertex_index}")
    for name, value in positive.items():
        group = obj.vertex_groups.get(name)
        if group is None:
            group = obj.vertex_groups.new(name=name)
        group.add([vertex_index], value / total, "REPLACE")


def blend_weights(stored: dict[str, Any], rematched: dict[str, Any]) -> dict[str, float]:
    names = set(stored) | set(rematched)
    blended = {
        name: (1.0 - ALPHA) * float(stored.get(name, 0.0)) + ALPHA * float(rematched.get(name, 0.0))
        for name in names
    }
    return {name: value for name, value in blended.items() if value > 1e-12}


def main() -> None:
    evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    if evidence.get("format") != "grand-bruxelles-gate8-variant01-mhclo-rematch-v2":
        raise RuntimeError("unexpected rematch evidence format")
    records = evidence.get("records", {})
    if set(records) != {str(v) for v in FOCUS_VERTICES}:
        raise RuntimeError("focus vertex evidence drifted")

    mpfb = ready.base.resolve_mpfb_module()
    services = __import__(mpfb.__package__ + ".services", fromlist=["ExportService"])
    ExportService = services.ExportService
    original_create_copy = ExportService.create_character_copy
    touched = False
    audit: dict[str, Any] = {}

    def wrapped_create_copy(root, *args, **kwargs):
        nonlocal touched, audit
        copy_root = original_create_copy(root, *args, **kwargs)
        if root.name != "npc_gate_01":
            return copy_root
        sportsuit = find_sportsuit(copy_root)
        if len(sportsuit.data.vertices) != 1797:
            raise RuntimeError(f"sportsuit topology drifted: {len(sportsuit.data.vertices)}")
        vertex_audit: dict[str, Any] = {}
        for vertex_index in FOCUS_VERTICES:
            record = records[str(vertex_index)]
            if not record.get("rematch_success"):
                raise RuntimeError(f"missing rematch for {vertex_index}")
            stored = record["stored_mpfb_deform_weights"]
            rematched = record["rematched_mpfb_deform_weights"]
            blended = blend_weights(stored, rematched)
            set_vertex_weights(sportsuit, vertex_index, blended)
            vertex_audit[str(vertex_index)] = {
                "stored": stored,
                "rematched": rematched,
                "alpha0125": blended,
                "sum": sum(blended.values()),
            }
        touched = True
        audit = {
            "variant": root.name,
            "sportsuit": sportsuit.name,
            "sportsuit_vertex_count": len(sportsuit.data.vertices),
            "alpha": ALPHA,
            "focus_vertices": list(FOCUS_VERTICES),
            "vertices": vertex_audit,
        }
        return copy_root

    ExportService.create_character_copy = wrapped_create_copy
    try:
        ready.base.main()
    finally:
        ExportService.create_character_copy = original_create_copy

    if not touched:
        raise RuntimeError("alpha0125 probe never intercepted npc_gate_01 export")
    output_dir = next((Path(sys.argv[i + 1]).resolve() for i, arg in enumerate(sys.argv) if arg == "--output-dir"), None)
    if output_dir is None:
        raise RuntimeError("output dir missing")
    glbs = sorted(output_dir.glob("npc_gate_*.glb"))
    if len(glbs) != 8:
        raise RuntimeError(f"expected 8 generated GLBs, got {len(glbs)}")
    result = {
        "format": "grand-bruxelles-gate8-alpha0125-export-v1",
        "alpha": ALPHA,
        "candidate_variant": "npc_gate_01",
        "focus_vertices": list(FOCUS_VERTICES),
        "source_evidence_artifact_id": 9720026708,
        "source_pack_sha256": ready.base.EXPECTED_ASSET_SHA256,
        "generator_mpfb": "2.0.17",
        "generator_mpfb_build": ready.base.EXPECTED_MPFB_BUILD,
        "audit": audit,
        "canonical_asset_mutation": False,
        "canonical_mhclo_mutation": False,
        "runtime_npc_mutation": False,
        "production_activation_allowed": False,
        "visual_approval_allowed": False,
    }
    RESULT_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULT_PATH.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("GATE8_ALPHA0125_EXPORT_OK variant=npc_gate_01 alpha=0.125 focus_vertices=8", flush=True)


if __name__ == "__main__":
    main()
