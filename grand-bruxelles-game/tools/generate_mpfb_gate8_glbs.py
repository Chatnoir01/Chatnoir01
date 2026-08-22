#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib
import json
import sys
import traceback
import zipfile
from pathlib import Path

import bpy
from mathutils import Vector

EXPECTED_MPFB_VERSION = (2, 0, 17)
EXPECTED_MPFB_BUILD = "20260821"
EXPECTED_COUNT = 8
EXPECTED_ASSET_SIZE = 81_255_948
EXPECTED_ASSET_SHA256 = "6b1d673e4c1fd169372d3a74fe174d9c185069c1f55ff6bf6b224f6655e4b67a"
BASE_SEED = 260821
PACK_FILTER = "makehuman_system_assets"


def log(message: str) -> None:
    print(f"GB_GATE8 {message}", flush=True)


def parse_args() -> tuple[Path, Path]:
    argv = sys.argv
    args = argv[argv.index("--") + 1 :] if "--" in argv else []
    values: dict[str, str] = {}
    iterator = iter(args)
    for item in iterator:
        if item in {"--asset-pack", "--output-dir"}:
            values[item] = next(iterator)
    if "--asset-pack" not in values or "--output-dir" not in values:
        raise ValueError("required args: --asset-pack ZIP --output-dir DIR")
    return Path(values["--asset-pack"]).resolve(), Path(values["--output-dir"]).resolve()


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resolve_mpfb_module():
    for module_name, module in list(sys.modules.items()):
        if module_name.endswith(".mpfb") and tuple(getattr(module, "VERSION", ())) == EXPECTED_MPFB_VERSION:
            return module

    errors: list[str] = []
    for module_name in ("bl_ext.gb_ci.mpfb", "bl_ext.user_default.mpfb", "mpfb"):
        try:
            module = importlib.import_module(module_name)
        except Exception as exc:
            errors.append(f"{module_name}: {exc!r}")
            continue
        if getattr(module, "MPFB_CONTEXTUAL_INFORMATION", None) is None:
            module.register()
        if tuple(getattr(module, "VERSION", ())) == EXPECTED_MPFB_VERSION:
            return module
        errors.append(f"{module_name}: version={getattr(module, 'VERSION', None)!r}")
    raise RuntimeError("MPFB 2.0.17 is not installed/enabled; " + "; ".join(errors))


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result = [root]
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        result.append(obj)
        stack.extend(obj.children)
    return result


def root_of(obj: bpy.types.Object) -> bpy.types.Object:
    root = obj
    while root.parent is not None:
        root = root.parent
    return root


def bounds_for(root: bpy.types.Object) -> tuple[float, float]:
    min_z = float("inf")
    max_z = float("-inf")
    found = False
    for obj in descendants(root):
        if obj.type != "MESH" or not getattr(obj, "bound_box", None):
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            min_z = min(min_z, world.z)
            max_z = max(max_z, world.z)
            found = True
    if not found:
        raise RuntimeError(f"no mesh bounds under {root.name}")
    return min_z, max_z


def safe_extract(archive: zipfile.ZipFile, destination: Path) -> None:
    destination = destination.resolve()
    for member in archive.infolist():
        target = (destination / member.filename).resolve()
        if target != destination and destination not in target.parents:
            raise RuntimeError(f"unsafe ZIP path: {member.filename}")
    archive.extractall(destination)


def install_asset_pack(asset_pack: Path, location_service, asset_service) -> None:
    if not asset_pack.is_file():
        raise RuntimeError(f"asset pack missing: {asset_pack}")
    if asset_pack.stat().st_size != EXPECTED_ASSET_SIZE:
        raise RuntimeError(
            f"Gate-8 asset pack size mismatch: expected={EXPECTED_ASSET_SIZE} actual={asset_pack.stat().st_size}"
        )
    digest = sha256_path(asset_pack)
    if digest != EXPECTED_ASSET_SHA256:
        raise RuntimeError(
            f"Gate-8 asset pack sha256 mismatch: expected={EXPECTED_ASSET_SHA256} actual={digest}"
        )

    problem = asset_service.check_asset_pack_zip(str(asset_pack))
    if problem is not None:
        raise RuntimeError(f"MPFB rejected Gate-8 asset pack: {problem}")

    data_dir = Path(location_service.get_user_data())
    data_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(asset_pack, "r") as archive:
        bad = archive.testzip()
        if bad is not None:
            raise RuntimeError(f"Gate-8 asset pack CRC failure: {bad}")
        safe_extract(archive, data_dir)

    asset_service.update_all_asset_lists()
    modern_pack, brown_material = asset_service.check_if_modern_makehuman_system_assets_installed()
    if not modern_pack or not brown_material:
        raise RuntimeError(
            f"MakeHuman system assets not recognized after install: pack={modern_pack} brown={brown_material}"
        )
    if not asset_service.system_assets_pack_is_installed():
        raise RuntimeError("makehuman_system_assets pack name is not visible to MPFB")
    log(f"ASSET_PACK_OK data_dir={data_dir} sha256={digest}")


def set_value(properties, scene, name: str, value) -> None:
    properties.set_value(name, value, entity_reference=scene)
    actual = properties.get_value(name, entity_reference=scene)
    if actual != value:
        raise RuntimeError(f"MPFB property did not stick: {name} expected={value!r} actual={actual!r}")


def configure_randomization(properties, randomization_service, scene) -> None:
    set_value(properties, scene, "seed", BASE_SEED)
    set_value(properties, scene, "new_random_seed", False)
    set_value(properties, scene, "batch_count", EXPECTED_COUNT)
    set_value(properties, scene, "batch_strategy", "GRID")
    set_value(properties, scene, "batch_row_length", 4)
    set_value(properties, scene, "batch_spacing_x", 2.5)
    set_value(properties, scene, "batch_row_shift_y", 2.5)
    set_value(properties, scene, "batch_random_rotation", False)

    set_value(properties, scene, "scale_factor", "METER")
    set_value(properties, scene, "add_rig", "game_engine")
    set_value(properties, scene, "detailed_helpers", False)
    set_value(properties, scene, "extra_vertex_groups", False)
    set_value(properties, scene, "mask_helpers", True)
    set_value(properties, scene, "add_subdiv_modifier", False)

    # MPFB 2.0.17 uses discrete_gender/discrete_age as mode toggles, but the
    # individual booleans are named gender_allow_* and age_allow_*.
    set_value(properties, scene, "discrete_gender", True)
    set_value(properties, scene, "gender_allow_female", True)
    set_value(properties, scene, "gender_allow_male", True)

    set_value(properties, scene, "discrete_age", True)
    for age in ("baby", "child", "young", "middleage", "old"):
        set_value(properties, scene, f"age_allow_{age}", age in {"young", "middleage", "old"})

    set_value(properties, scene, "randomize_skin", True)
    set_value(properties, scene, "skin_pack", PACK_FILTER)
    set_value(properties, scene, "match_gender", True)
    # The bounded Gate-8 pack intentionally has fewer old/middle-age race
    # combinations than the full system pack; do not over-constrain selection.
    set_value(properties, scene, "match_age", False)
    set_value(properties, scene, "match_race", False)

    set_value(properties, scene, "eyes_mode", "LOWPOLY")
    set_value(properties, scene, "eyes_randomize_alt_materials", True)

    set_value(properties, scene, "hair_randomize", True)
    set_value(properties, scene, "hair_pack", PACK_FILTER)
    set_value(properties, scene, "hair_match_gender", False)
    set_value(properties, scene, "eyebrows_enable", True)
    set_value(properties, scene, "eyebrows_pack", PACK_FILTER)
    set_value(properties, scene, "eyelashes_enable", True)
    set_value(properties, scene, "eyelashes_pack", PACK_FILTER)
    set_value(properties, scene, "teeth_enable", True)
    set_value(properties, scene, "teeth_pack", PACK_FILTER)
    set_value(properties, scene, "tongue_enable", False)

    for slot in randomization_service.get_clothes_slots():
        enabled = slot in {"full_body", "feet"}
        set_value(properties, scene, f"clothes_{slot}_enable", enabled)
        if slot == "full_body":
            set_value(properties, scene, f"clothes_{slot}_chance", 100)
            set_value(properties, scene, f"clothes_{slot}_pack", PACK_FILTER)
            set_value(properties, scene, f"clothes_{slot}_include_any", "")
            set_value(properties, scene, f"clothes_{slot}_include_female", "female")
            set_value(properties, scene, f"clothes_{slot}_include_male", "male")
            set_value(properties, scene, f"clothes_{slot}_exclude", "")
        elif slot == "feet":
            set_value(properties, scene, f"clothes_{slot}_chance", 100)
            set_value(properties, scene, f"clothes_{slot}_pack", PACK_FILTER)
            set_value(properties, scene, f"clothes_{slot}_include_any", "shoe")
            set_value(properties, scene, f"clothes_{slot}_include_female", "")
            set_value(properties, scene, f"clothes_{slot}_include_male", "")
            set_value(properties, scene, f"clothes_{slot}_exclude", "")


def export_character(root: bpy.types.Object, output_path: Path) -> dict:
    original_location = root.location.copy()
    original_rotation = root.rotation_euler.copy()

    root.location.x = 0.0
    root.location.y = 0.0
    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()

    min_z, _ = bounds_for(root)
    root.location.z -= min_z
    bpy.context.view_layer.update()
    grounded_min_z, grounded_max_z = bounds_for(root)
    height = grounded_max_z - grounded_min_z

    if abs(grounded_min_z) > 0.01:
        raise RuntimeError(f"{root.name}: grounding failed min_z={grounded_min_z}")
    if not 1.25 <= height <= 2.30:
        raise RuntimeError(f"{root.name}: implausible human height={height}")

    bpy.ops.object.select_all(action="DESELECT")
    hierarchy = descendants(root)
    for obj in hierarchy:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_skins=True,
        export_animations=False,
        export_apply=False,
        export_materials="EXPORT",
    )

    meshes = [obj for obj in hierarchy if obj.type == "MESH"]
    armatures = [obj for obj in hierarchy if obj.type == "ARMATURE"]
    if not output_path.is_file() or output_path.stat().st_size < 50_000:
        raise RuntimeError(f"{root.name}: GLB missing or suspiciously small")
    if not meshes:
        raise RuntimeError(f"{root.name}: no meshes")
    if len(armatures) != 1:
        raise RuntimeError(f"{root.name}: expected one armature, got {len(armatures)}")

    record = {
        "id": root.name,
        "seed": next(
            (int(obj["mpfb_randomization_seed"]) for obj in hierarchy if "mpfb_randomization_seed" in obj),
            None,
        ),
        "height_m": round(float(height), 6),
        "ground_min_z_m": round(float(grounded_min_z), 6),
        "mesh_count": len(meshes),
        "armature_count": len(armatures),
        "glb": output_path.name,
        "size_bytes": output_path.stat().st_size,
        "sha256": sha256_path(output_path),
    }

    root.location = original_location
    root.rotation_euler = original_rotation
    bpy.context.view_layer.update()
    return record


def main() -> None:
    asset_pack, output_dir = parse_args()
    output_dir.mkdir(parents=True, exist_ok=True)

    mpfb = resolve_mpfb_module()
    version = tuple(getattr(mpfb, "VERSION", ()))
    build = str(getattr(mpfb, "BUILD_INFO", ""))
    if version != EXPECTED_MPFB_VERSION or build != EXPECTED_MPFB_BUILD:
        raise RuntimeError(f"unexpected MPFB identity: version={version} build={build}")
    package = mpfb.__package__
    log(f"MPFB_OK package={package} version={version} build={build}")

    services = importlib.import_module(package + ".services")
    randomize = importlib.import_module(package + ".ui.new_human.randomize.randomizeproperties")
    location_service = services.LocationService
    asset_service = services.AssetService
    randomization_service = services.RandomizationService
    properties = randomize.RANDOMIZE_PROPERTIES

    install_asset_pack(asset_pack, location_service, asset_service)
    configure_randomization(properties, randomization_service, bpy.context.scene)

    before_seeded = {obj.name for obj in bpy.data.objects if "mpfb_randomization_seed" in obj}
    result = bpy.ops.mpfb.create_random_human_batch("EXEC_DEFAULT")
    if "FINISHED" not in result:
        raise RuntimeError(f"MPFB batch operator failed: {result}")

    basemeshes = [
        obj
        for obj in bpy.data.objects
        if "mpfb_randomization_seed" in obj and obj.name not in before_seeded
    ]
    roots: list[bpy.types.Object] = []
    seen: set[int] = set()
    for basemesh in basemeshes:
        root = root_of(basemesh)
        pointer = root.as_pointer()
        if pointer not in seen:
            roots.append(root)
            seen.add(pointer)

    roots.sort(
        key=lambda root: int(
            next(
                (obj["mpfb_randomization_seed"] for obj in descendants(root) if "mpfb_randomization_seed" in obj),
                0,
            )
        )
    )
    if len(roots) != EXPECTED_COUNT:
        raise RuntimeError(f"expected {EXPECTED_COUNT} generated characters, got {len(roots)}")

    records = []
    for index, root in enumerate(roots, start=1):
        root.name = f"npc_gate_{index:02d}"
        output_path = output_dir / f"npc_gate_{index:02d}.glb"
        record = export_character(root, output_path)
        records.append(record)
        log(
            f"EXPORTED id={record['id']} seed={record['seed']} height={record['height_m']} "
            f"bytes={record['size_bytes']} sha256={record['sha256']}"
        )

    seeds = [record["seed"] for record in records]
    if None in seeds or len(seeds) != len(set(seeds)):
        raise RuntimeError(f"invalid or duplicate MPFB seeds: {seeds}")

    manifest = {
        "schema_version": 1,
        "generator": "Grand Bruxelles MPFB Gate-8",
        "blender_version": bpy.app.version_string,
        "mpfb_version": ".".join(str(v) for v in version),
        "mpfb_build": build,
        "base_seed": BASE_SEED,
        "rig": "game_engine",
        "scale_factor": "METER",
        "asset_pack_sha256": sha256_path(asset_pack),
        "character_count": len(records),
        "characters": records,
    }
    manifest_path = output_dir / "gate8_glb_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    log(f"SUCCESS count={len(records)} manifest={manifest_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        traceback.print_exc()
        print(f"GB_GATE8 FAIL {exc}", flush=True)
        raise SystemExit(1) from exc
