#!/usr/bin/env python3
"""Build one review-only Midi civilian through MPFB inside Blender.

Two characters are created from the exact same MakeHuman MHM control source:
1) an Enhanced SSS / procedural-eyes Blender reference, rendered only for ceiling review;
2) a GAMEENGINE material copy, cleaned with MPFB ExportService and exported as GLB.

The GLB is the only asset later imported by Godot. Neither path authorizes production.
"""
import importlib
import json
import math
import os
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Vector

MHM_INPUT = Path(os.environ.get("GB_MPFB_MHM_INPUT", "/tmp/gb_mpfb_source/FemalePilot.mhm")).resolve()
ASSET_SOURCE = Path(os.environ.get("GB_MPFB_ASSET_SOURCE_ROOT", "/tmp/mpfb-asset-root")).resolve()
GLB_OUTPUT = Path(os.environ.get("GB_MPFB_GLB_OUTPUT", "/tmp/gb_mpfb_output/FemalePilot.glb")).resolve()
REFERENCE_DIR = Path(os.environ.get("GB_MPFB_REFERENCE_DIR", "/tmp/gb_mpfb_output/reference")).resolve()
METRICS_OUTPUT = Path(os.environ.get("GB_MPFB_METRICS_OUTPUT", "/tmp/gb_mpfb_output/mpfb_metrics.json")).resolve()


def dynamic_import(package_suffix, key):
    for module_name in tuple(sys.modules):
        if module_name.endswith(package_suffix):
            module = importlib.import_module(module_name)
            if not hasattr(module, key):
                raise AttributeError(f"{module_name} has no {key}")
            return getattr(module, key)
    raise RuntimeError(f"MPFB module ending with {package_suffix!r} is not loaded")


HumanService = dynamic_import("mpfb.services.humanservice", "HumanService")
ExportService = dynamic_import("mpfb.services.exportservice", "ExportService")
ObjectService = dynamic_import("mpfb.services.objectservice", "ObjectService")
TargetService = dynamic_import("mpfb.services.targetservice", "TargetService")
LocationService = dynamic_import("mpfb.services.locationservice", "LocationService")


def _install_assets():
    if not ASSET_SOURCE.is_dir():
        raise RuntimeError(f"MPFB asset source root missing: {ASSET_SOURCE}")
    user_data = Path(LocationService.get_user_data()).resolve()
    user_data.mkdir(parents=True, exist_ok=True)
    for child in ASSET_SOURCE.iterdir():
        target = user_data / child.name
        if child.is_dir():
            shutil.copytree(child, target, dirs_exist_ok=True)
        else:
            shutil.copy2(child, target)
    print(f"GB_MPFB_ASSETS_OK source={ASSET_SOURCE} user_data={user_data}")


def _deserialization_settings(high_fidelity):
    settings = HumanService.get_default_deserialization_settings()
    settings.update({
        "scale": 0.1,
        "load_clothes": True,
        "override_rig": "default",
        "bodypart_deep_search": True,
        "clothes_deep_search": True,
        "detailed_helpers": True,
        "extra_vertex_groups": True,
        "mask_helpers": True,
    })
    if high_fidelity:
        settings.update({
            "override_skin_model": "ENHANCED_SSS",
            "override_clothes_model": "MAKESKIN",
            "override_eyes_model": "PROCEDURAL_EYES",
            "material_instances": "ENHANCED",
        })
    else:
        settings.update({
            "override_skin_model": "GAMEENGINE",
            "override_clothes_model": "GAMEENGINE",
            "override_eyes_model": "GAMEENGINE",
            "material_instances": "NEVER",
        })
    return settings


def _import_character(high_fidelity):
    if not MHM_INPUT.is_file():
        raise RuntimeError(f"MHM control source missing: {MHM_INPUT}")
    basemesh = HumanService.deserialize_from_mhm(str(MHM_INPUT), _deserialization_settings(high_fidelity))
    if basemesh is None:
        raise RuntimeError("MPFB returned no basemesh")
    HumanService.refit(basemesh)
    bpy.context.view_layer.update()
    return basemesh


def _relatives(root):
    objects = [root]
    for child in ObjectService.get_list_of_children(root):
        if child not in objects:
            objects.append(child)
    # Include parent rig if root is basemesh and hierarchy is oriented around rig.
    parent = root.parent
    while parent is not None:
        if parent not in objects:
            objects.append(parent)
        parent = parent.parent
    return objects


def _mesh_objects(root):
    return [obj for obj in _relatives(root) if getattr(obj, "type", "") == "MESH"]


def _world_bounds(root):
    points = []
    for obj in _mesh_objects(root):
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    if not points:
        raise RuntimeError("character has no mesh bounds")
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return minimum, maximum


def _look_at(obj, target):
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _build_review_world():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.10, 0.115, 0.14)

    camera_data = bpy.data.cameras.new("MPFBReviewCamera")
    camera = bpy.data.objects.new("MPFBReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.angle = math.radians(43.0)

    key_data = bpy.data.lights.new("MPFBKey", "AREA")
    key_data.energy = 650.0
    key_data.shape = "DISK"
    key_data.size = 4.0
    key = bpy.data.objects.new("MPFBKey", key_data)
    scene.collection.objects.link(key)
    key.location = (2.8, -3.5, 4.5)
    _look_at(key, (0.0, 1.0, 0.0))

    fill_data = bpy.data.lights.new("MPFBFill", "AREA")
    fill_data.energy = 300.0
    fill_data.size = 3.0
    fill = bpy.data.objects.new("MPFBFill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = (-2.5, -1.5, 2.8)
    _look_at(fill, (0.0, 1.1, 0.0))
    return camera


def _render_reference(root):
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)
    minimum, maximum = _world_bounds(root)
    center = (minimum + maximum) * 0.5
    height = maximum.z - minimum.z
    # MPFB METER-scale humans are expected around 1.7 m. A wildly different
    # height would make the V4 camera comparison invalid.
    if height < 1.4 or height > 2.2:
        raise RuntimeError(f"MPFB reference height implausible for metre scale: {height:.4f}")

    camera = _build_review_world()
    scene = bpy.context.scene
    views = [
        ("source_full.png", Vector((0.0, -3.20, 1.48)), Vector((0.0, 0.0, 0.93)), math.radians(43.0)),
        ("source_close.png", Vector((0.0, -1.48, 1.46)), Vector((0.0, 0.0, 1.40)), math.radians(39.0)),
        ("source_three_quarter.png", Vector((1.95, -2.05, 1.52)), Vector((0.0, 0.0, 1.03)), math.radians(43.0)),
    ]
    for filename, position, target, angle in views:
        camera.location = position
        camera.data.angle = angle
        _look_at(camera, target)
        scene.render.filepath = str(REFERENCE_DIR / filename)
        bpy.ops.render.render(write_still=True)
        if not (REFERENCE_DIR / filename).is_file():
            raise RuntimeError(f"Blender reference render missing: {filename}")
    return {"height_m": height, "minimum": list(minimum), "maximum": list(maximum)}


def _delete_character(root):
    for obj in reversed(_relatives(root)):
        if obj and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.update()


def _prepare_export(engine_basemesh):
    export_root = ExportService.create_character_copy(engine_basemesh, name_suffix="_engine_export")
    export_basemesh = ObjectService.find_object_of_type_amongst_nearest_relatives(export_root, "Basemesh")
    if export_basemesh is None:
        raise RuntimeError("MPFB export copy has no basemesh")
    TargetService.bake_targets(export_basemesh)
    ExportService.bake_modifiers_remove_helpers(
        export_basemesh,
        bake_masks=True,
        bake_subdiv=True,
        remove_helpers=True,
        also_proxy=True,
    )
    bpy.context.view_layer.update()
    return export_root, export_basemesh


def _object_metrics(root):
    meshes = _mesh_objects(root)
    triangles = 0
    materials = set()
    images = set()
    armatures = []
    bone_count = 0
    for obj in _relatives(root):
        if getattr(obj, "type", "") == "ARMATURE":
            armatures.append(obj.name)
            bone_count += len(obj.data.bones)
    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        for slot in obj.material_slots:
            mat = slot.material
            if mat is None:
                continue
            materials.add(mat.name)
            if mat.use_nodes and mat.node_tree:
                for node in mat.node_tree.nodes:
                    image = getattr(node, "image", None)
                    if image is not None:
                        images.add(image.name)
    minimum, maximum = _world_bounds(root)
    return {
        "mesh_objects": len(meshes),
        "triangles": triangles,
        "materials": sorted(materials),
        "material_count": len(materials),
        "images": sorted(images),
        "image_count": len(images),
        "armatures": armatures,
        "bone_count": bone_count,
        "bounds_min": list(minimum),
        "bounds_max": list(maximum),
        "height_m": maximum.z - minimum.z,
    }


def _export_glb(export_root):
    GLB_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    export_objects = _relatives(export_root)
    for obj in export_objects:
        if obj.name in bpy.data.objects:
            obj.hide_set(False)
            obj.hide_render = False
            obj.select_set(True)
    bpy.context.view_layer.objects.active = export_root
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_apply=True,
    )
    if not GLB_OUTPUT.is_file() or GLB_OUTPUT.stat().st_size < 100_000:
        raise RuntimeError(f"GLB output missing or implausibly small: {GLB_OUTPUT}")


def main():
    _install_assets()
    print("GB_MPFB_VERSION", dynamic_import("mpfb", "VERSION"))

    source = _import_character(high_fidelity=True)
    source_metrics = _object_metrics(source)
    source_bounds = _render_reference(source)
    source_metrics["render_bounds"] = source_bounds
    _delete_character(source)

    engine = _import_character(high_fidelity=False)
    export_root, _export_basemesh = _prepare_export(engine)
    export_metrics = _object_metrics(export_root)
    _export_glb(export_root)

    metrics = {
        "schema": "grand-bruxelles-mpfb-high-fidelity-candidate-v1",
        "production_authorized": False,
        "source_identity": "makehuman_v4_control_mhm",
        "mpfb_mode": {
            "reference": {
                "skin": "ENHANCED_SSS",
                "eyes": "PROCEDURAL_EYES",
                "clothes": "MAKESKIN",
                "render_engine": "BLENDER_EEVEE_NEXT",
            },
            "engine": {
                "skin": "GAMEENGINE",
                "eyes": "GAMEENGINE",
                "clothes": "GAMEENGINE",
                "rig": "default",
                "export": "GLB",
                "shape_keys": "baked",
                "mask_modifiers": "baked",
                "subdiv_modifiers": "baked",
                "helpers": "removed",
            },
        },
        "mhm_input": str(MHM_INPUT),
        "glb_output": str(GLB_OUTPUT),
        "glb_bytes": GLB_OUTPUT.stat().st_size,
        "reference": source_metrics,
        "engine_export": export_metrics,
        "reference_pngs": [
            str(REFERENCE_DIR / "source_full.png"),
            str(REFERENCE_DIR / "source_close.png"),
            str(REFERENCE_DIR / "source_three_quarter.png"),
        ],
    }
    METRICS_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    METRICS_OUTPUT.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(
        "GB_MPFB_HIGH_FIDELITY_OK glb=%s bytes=%d source_triangles=%d engine_triangles=%d "
        "engine_bones=%d production_authorized=false"
        % (
            GLB_OUTPUT,
            GLB_OUTPUT.stat().st_size,
            source_metrics["triangles"],
            export_metrics["triangles"],
            export_metrics["bone_count"],
        )
    )


if __name__ == "__main__":
    main()
