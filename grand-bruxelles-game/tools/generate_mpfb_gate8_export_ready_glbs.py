#!/usr/bin/env python3
from __future__ import annotations

import importlib
import importlib.util
import sys
import traceback
from pathlib import Path

import bpy

BASE_PATH = Path(__file__).with_name("generate_mpfb_gate8_glbs.py")
SPEC = importlib.util.spec_from_file_location("grand_bruxelles_gate8_base_generator", BASE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load Gate-8 base generator: {BASE_PATH}")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)

_original_export_character = base.export_character


def _seed_from_hierarchy(root: bpy.types.Object):
    return next(
        (
            int(obj["mpfb_randomization_seed"])
            for obj in base.descendants(root)
            if "mpfb_randomization_seed" in obj
        ),
        None,
    )


def _delete_hierarchy(root: bpy.types.Object) -> None:
    # Remove children first so Blender does not leave orphaned character parts.
    for obj in reversed(base.descendants(root)):
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def export_character_ready(root: bpy.types.Object, output_path: Path) -> dict:
    mpfb = base.resolve_mpfb_module()
    services = importlib.import_module(mpfb.__package__ + ".services")
    ExportService = services.ExportService
    ObjectService = services.ObjectService
    TargetService = services.TargetService

    canonical_id = root.name
    source_seed = _seed_from_hierarchy(root)
    if source_seed is None:
        raise RuntimeError(f"{canonical_id}: source randomization seed missing")

    export_root = ExportService.create_character_copy(
        root,
        name_suffix="_gate8_export",
        place_in_collection=None,
    )
    export_basemesh = ObjectService.find_object_of_type_amongst_nearest_relatives(export_root)
    if export_basemesh is None or export_basemesh.type != "MESH":
        _delete_hierarchy(export_root)
        raise RuntimeError(f"{canonical_id}: MPFB export copy has no basemesh")

    vertices_before = len(export_basemesh.data.vertices)
    helper_groups_before = sorted(
        group.name
        for group in export_basemesh.vertex_groups
        if group.name in {"HelperGeometry", "JointCubes", "Mid", "Left", "Right"}
        or group.name.startswith("helper-")
        or group.name.startswith("joint-")
    )
    mask_modifiers_before = [
        modifier.name for modifier in export_basemesh.modifiers if modifier.type == "MASK"
    ]

    # External engines must not receive MakeHuman modelling targets or helper
    # geometry. MPFB's own export staging API is authoritative for this step.
    if TargetService.has_any_shapekey(export_basemesh):
        TargetService.bake_targets(export_basemesh)
    ExportService.bake_modifiers_remove_helpers(
        export_basemesh,
        bake_masks=True,
        bake_subdiv=False,
        remove_helpers=True,
        also_proxy=True,
    )
    bpy.context.view_layer.update()

    vertices_after = len(export_basemesh.data.vertices)
    helper_groups_after = sorted(
        group.name
        for group in export_basemesh.vertex_groups
        if group.name in {"HelperGeometry", "JointCubes", "Mid", "Left", "Right"}
        or group.name.startswith("helper-")
        or group.name.startswith("joint-")
    )
    mask_modifiers_after = [
        modifier.name for modifier in export_basemesh.modifiers if modifier.type == "MASK"
    ]

    if vertices_after >= vertices_before:
        _delete_hierarchy(export_root)
        raise RuntimeError(
            f"{canonical_id}: helper bake did not reduce basemesh vertices "
            f"before={vertices_before} after={vertices_after}"
        )
    if helper_groups_after:
        _delete_hierarchy(export_root)
        raise RuntimeError(
            f"{canonical_id}: helper vertex groups survived export prep: {helper_groups_after}"
        )
    if mask_modifiers_after:
        _delete_hierarchy(export_root)
        raise RuntimeError(
            f"{canonical_id}: MASK modifiers survived export prep: {mask_modifiers_after}"
        )
    if TargetService.has_any_shapekey(export_basemesh):
        _delete_hierarchy(export_root)
        raise RuntimeError(f"{canonical_id}: modelling shape keys survived export prep")

    if _seed_from_hierarchy(export_root) is None:
        export_basemesh["mpfb_randomization_seed"] = int(source_seed)

    prepared_root = base.root_of(export_basemesh)

    try:
        record = _original_export_character(prepared_root, output_path)
        # Blender can append .001 to duplicated object names while the source
        # hierarchy still exists. Runtime identity must stay deterministic and
        # tied to the canonical source slot, not Blender's temporary copy name.
        record["id"] = canonical_id
        record["seed"] = int(source_seed)
        record.update(
            {
                "export_copy": True,
                "modeling_shapekeys_baked": True,
                "mask_modifiers_baked": True,
                "helpers_removed": True,
                "basemesh_vertices_before": vertices_before,
                "basemesh_vertices_after": vertices_after,
                "helper_groups_before": helper_groups_before,
                "helper_groups_after": helper_groups_after,
                "mask_modifiers_before": mask_modifiers_before,
                "mask_modifiers_after": mask_modifiers_after,
            }
        )
        base.log(
            "EXPORT_READY "
            f"id={record['id']} seed={record['seed']} "
            f"vertices_before={vertices_before} vertices_after={vertices_after} "
            "helpers_removed=true masks_baked=true shapekeys_baked=true"
        )
        return record
    finally:
        if prepared_root.name in bpy.data.objects:
            _delete_hierarchy(prepared_root)


base.export_character = export_character_ready


if __name__ == "__main__":
    try:
        base.main()
    except Exception as exc:
        traceback.print_exc()
        print(f"GB_GATE8 FAIL {exc}", flush=True)
        raise SystemExit(1) from exc
