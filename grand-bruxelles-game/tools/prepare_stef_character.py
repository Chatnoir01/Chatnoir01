"""Export the audited CC0 Stef Blender source to a Godot-friendly GLB.

Run with Blender opening the source .blend first, then this script:
    blender --background SOURCE.blend --python tools/prepare_stef_character.py -- OUTPUT.glb

The script does not remodel the character. It validates the existing armature,
skinned meshes, materials and animation actions, reconnects packaged textures,
normalizes only the scene-root scale to a 1.70 m game height, and exports GLB
with skins, materials and animations preserved.
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy
from mathutils import Vector

TARGET_HEIGHT_M = 1.70
TEXTURE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".tga")


def _output_arg() -> Path:
    argv = sys.argv
    if "--" not in argv:
        raise SystemExit("Expected output GLB after --")
    args = argv[argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("Usage: blender --background SOURCE.blend --python prepare_stef_character.py -- OUTPUT.glb")
    return Path(args[0]).resolve()


def _mesh_world_bounds() -> tuple[float, float]:
    points: list[Vector] = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    if not points:
        raise RuntimeError("Stef source contains no mesh geometry")
    return min(p.z for p in points), max(p.z for p in points)


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


def _validate_source() -> dict[str, object]:
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError("Stef source has no armature")

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    skinned = []
    for obj in meshes:
        has_armature_modifier = any(mod.type == "ARMATURE" for mod in obj.modifiers)
        if has_armature_modifier or obj.parent in armatures:
            skinned.append(obj)
    if not skinned:
        raise RuntimeError("Stef source has no skinned mesh")

    actions = list(bpy.data.actions)
    if not actions:
        raise RuntimeError("Stef source has no animation actions")

    material_slots = sum(len(obj.material_slots) for obj in meshes)
    if material_slots <= 0:
        raise RuntimeError("Stef source has no material slots")

    return {
        "armatures": len(armatures),
        "bones": sum(len(obj.data.bones) for obj in armatures),
        "meshes": len(meshes),
        "skinned_meshes": len(skinned),
        "materials": material_slots,
        "actions": [action.name for action in actions],
    }


def _normalized_stem(name: str) -> str:
    return Path(name).stem.strip().lower()


def _reconnect_textures() -> None:
    source_path = Path(bpy.data.filepath)
    if not source_path.is_file():
        return

    texture_dir = source_path.parent
    package_textures = {
        _normalized_stem(path.name): path
        for path in texture_dir.iterdir()
        if path.is_file() and path.suffix.lower() in TEXTURE_EXTENSIONS
    }

    relinked = 0
    unresolved: list[str] = []
    for image in bpy.data.images:
        if image.source != "FILE":
            continue
        original_name = Path(bpy.path.abspath(image.filepath)).name or image.name
        key = _normalized_stem(original_name)
        replacement = package_textures.get(key)
        if replacement is None:
            unresolved.append(original_name)
            continue
        image.filepath = str(replacement)
        try:
            image.reload()
        except RuntimeError as exc:
            raise RuntimeError(f"Failed to reload packaged texture {replacement.name}: {exc}") from exc
        relinked += 1

    print(f"STEF_TEXTURE_RELINK: relinked={relinked} unresolved={len(unresolved)}")
    if unresolved:
        print("STEF_TEXTURE_UNRESOLVED: " + " | ".join(sorted(set(unresolved))))


def _mark_metadata(scale: float, audit: dict[str, object]) -> None:
    scene = bpy.context.scene
    scene["grand_bruxelles_character"] = "stef_cc0_candidate_v1"
    scene["source_character"] = "npc girl Stef / supersteve / OpenGameArt"
    scene["source_license"] = "CC0"
    scene["source_page"] = "https://opengameart.org/content/npc-girl-stef"
    scene["source_archive_sha256"] = "3b1f65c188ffd91dd237dae3d670d8b1d390ce7e96a251dd13ec5b8fb5d6fe22"
    scene["target_height_m"] = TARGET_HEIGHT_M
    scene["source_to_game_scale"] = scale
    scene["rig_bone_count"] = int(audit["bones"])
    scene["source_action_count"] = len(audit["actions"])


def _export_glb(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_apply=False,
        export_animations=True,
        export_skins=True,
        export_morph=True,
        export_yup=True,
        export_materials="EXPORT",
        export_draco_mesh_compression_enable=False,
    )
    if not output.is_file() or output.stat().st_size < 100_000:
        raise RuntimeError(f"GLB export missing or unexpectedly small: {output}")


def main() -> None:
    output = _output_arg()
    _reconnect_textures()
    audit = _validate_source()
    scale = _normalize_height()
    _mark_metadata(scale, audit)
    _export_glb(output)
    print(
        "STEF_EXPORT_OK: "
        f"output={output} armatures={audit['armatures']} bones={audit['bones']} "
        f"meshes={audit['meshes']} skinned={audit['skinned_meshes']} "
        f"materials={audit['materials']} actions={len(audit['actions'])} "
        f"height={TARGET_HEIGHT_M:.2f}m"
    )
    print("STEF_ACTIONS: " + " | ".join(str(x) for x in audit["actions"]))


if __name__ == "__main__":
    main()
