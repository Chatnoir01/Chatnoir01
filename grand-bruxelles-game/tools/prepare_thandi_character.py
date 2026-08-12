"""Prepare the Thandi source FBX as the authored Grand Bruxelles player GLB.

Run with Blender 4.x:
    blender --background --python tools/prepare_thandi_character.py -- \
      assets/characters/player/thandi/source/Thandi.fbx \
      assets/characters/player/thandi/Thandi.glb

The script deliberately performs only safe, reversible production changes:
- imports the original rigged FBX with animation and shape keys,
- normalizes the character to a game-sized height,
- replaces the zebra top colour path with the approved hot-pink material,
- darkens hair while keeping its normal/opacity structure,
- preserves the Mixamo skeleton and facial shape keys,
- exports a Godot-friendly GLB with skins, animations and morph targets.

It does not sculpt the source face. Face likeness work remains a separate authored pass.
"""

from __future__ import annotations

import math
import os
import sys
from pathlib import Path

import bpy

TARGET_HEIGHT_M = 1.70
TARGET_PINK = (0.93, 0.055, 0.46, 1.0)
TARGET_HAIR = (0.012, 0.009, 0.008, 1.0)


def _args() -> tuple[Path, Path]:
    argv = sys.argv
    if "--" not in argv:
        raise SystemExit("Expected source FBX and output GLB after --")
    args = argv[argv.index("--") + 1 :]
    if len(args) != 2:
        raise SystemExit("Usage: blender --background --python prepare_thandi_character.py -- SOURCE.fbx OUTPUT.glb")
    return Path(args[0]).resolve(), Path(args[1]).resolve()


def _clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def _import_fbx(source: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    bpy.ops.import_scene.fbx(
        filepath=str(source),
        automatic_bone_orientation=False,
        use_anim=True,
        use_custom_normals=True,
    )


def _find_object(*names: str):
    lower = {name.lower() for name in names}
    for obj in bpy.context.scene.objects:
        clean = obj.name.lower().replace("mesh", "").strip(" ._-")
        if obj.name.lower() in lower or clean in lower:
            return obj
    return None


def _principled(material):
    if not material or not material.use_nodes:
        return None
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            return node
    return None


def _tint_material_slots(obj, color, roughness: float, disconnect_base_texture: bool = False) -> None:
    if obj is None:
        return
    for slot in obj.material_slots:
        material = slot.material
        if material is None:
            continue
        material.diffuse_color = color
        material.use_nodes = True
        bsdf = _principled(material)
        if bsdf is None:
            continue
        base = bsdf.inputs.get("Base Color")
        if base is not None:
            if disconnect_base_texture and base.is_linked:
                for link in list(base.links):
                    material.node_tree.links.remove(link)
            base.default_value = color
        rough = bsdf.inputs.get("Roughness")
        if rough is not None:
            rough.default_value = roughness


def _mesh_world_bounds():
    points = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ __import__("mathutils").Vector(corner))
    if not points:
        raise RuntimeError("Imported FBX contains no mesh geometry")
    min_z = min(p.z for p in points)
    max_z = max(p.z for p in points)
    return min_z, max_z


def _normalize_height() -> float:
    min_z, max_z = _mesh_world_bounds()
    height = max_z - min_z
    if height <= 0.01:
        raise RuntimeError(f"Invalid source height: {height}")
    scale = TARGET_HEIGHT_M / height

    roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
    for obj in roots:
        obj.scale *= scale
    bpy.context.view_layer.update()

    min_z_after, _ = _mesh_world_bounds()
    for obj in roots:
        obj.location.z -= min_z_after
    bpy.context.view_layer.update()
    return scale


def _validate_rig_and_shapes() -> tuple[int, list[str]]:
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError("Thandi import lost its armature")

    shape_names: list[str] = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        shape_names.extend(key.name for key in obj.data.shape_keys.key_blocks if key.name != "Basis")

    expected = {"MouthOpen", "Blink_Left", "Blink_Right", "Smile_Left", "Smile_Right"}
    missing = sorted(expected.difference(shape_names))
    if missing:
        print(f"THANDI_WARN: expected facial shapes not found after Blender import: {missing}")
    return sum(len(a.data.bones) for a in armatures), sorted(set(shape_names))


def _mark_asset_metadata(scale: float, bones: int, shapes: list[str]) -> None:
    scene = bpy.context.scene
    scene["grand_bruxelles_character"] = "thandi_pink_v1"
    scene["source_character"] = "African Female Rigged with Mouth Morphs / Dale.Nolan"
    scene["source_license"] = "CC BY"
    scene["target_height_m"] = TARGET_HEIGHT_M
    scene["source_to_game_scale"] = scale
    scene["rig_bone_count"] = bones
    scene["facial_shape_count"] = len(shapes)


def _export_glb(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_apply=False,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_morph_normal=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    if not output.is_file() or output.stat().st_size < 100_000:
        raise RuntimeError(f"GLB export missing or unexpectedly small: {output}")


def main() -> None:
    source, output = _args()
    _clear_scene()
    _import_fbx(source)

    top = _find_object("Tops", "Top")
    hair = _find_object("Hair")
    body = _find_object("Body")
    if body is None:
        raise RuntimeError("Expected Thandi Body mesh was not found")
    if top is None:
        raise RuntimeError("Expected Thandi Tops mesh was not found")

    # The source top has a zebra diffuse map. Removing only the Base Color link
    # gives us a clean hot-pink first production pass while keeping mesh UVs,
    # normals, opacity and the underlying rig untouched.
    _tint_material_slots(top, TARGET_PINK, 0.52, disconnect_base_texture=True)
    _tint_material_slots(hair, TARGET_HAIR, 0.68, disconnect_base_texture=False)

    scale = _normalize_height()
    bones, shapes = _validate_rig_and_shapes()
    _mark_asset_metadata(scale, bones, shapes)
    _export_glb(output)

    print(
        "THANDI_PREP_OK: "
        f"output={output} bones={bones} facial_shapes={len(shapes)} "
        f"height={TARGET_HEIGHT_M:.2f}m"
    )


if __name__ == "__main__":
    main()
