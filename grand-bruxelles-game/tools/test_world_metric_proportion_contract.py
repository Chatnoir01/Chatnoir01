#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data/qa/world_metric_proportion_contract.json"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"{label}: missing {needle!r}")


def close(actual: float, expected: float, label: str, tol: float = 1e-9) -> None:
    if not math.isclose(actual, expected, rel_tol=0.0, abs_tol=tol):
        raise AssertionError(f"{label}: actual={actual} expected={expected}")


def gd_const(text: str, name: str) -> float:
    match = re.search(rf"^const\s+{re.escape(name)}\s*:=\s*(-?\d+(?:\.\d+)?)\s*$", text, re.MULTILINE)
    if not match:
        raise AssertionError(f"missing numeric GDScript constant: {name}")
    return float(match.group(1))


def tscn_subresource(text: str, resource_type: str, resource_id: str) -> str:
    header = rf'^\[sub_resource type="{re.escape(resource_type)}" id="{re.escape(resource_id)}"\]\s*$'
    match = re.search(header + r"\n(.*?)(?=\n\[|\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"missing TSCN subresource {resource_type}/{resource_id}")
    return match.group(1)


def tscn_float(block: str, key: str) -> float:
    match = re.search(rf"^{re.escape(key)}\s*=\s*(-?\d+(?:\.\d+)?)\s*$", block, re.MULTILINE)
    if not match:
        raise AssertionError(f"missing TSCN numeric property: {key}")
    return float(match.group(1))


contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
assert contract["format"] == "grand-bruxelles-world-metric-proportion-contract-v1"
assert contract["world_units"]["godot_units_per_meter"] == 1.0
assert contract["geography"]["distance_scale"] == 1.0
for key, value in contract["policy"].items():
    assert value is True, f"metric policy disabled: {key}"
anchors = contract["anchors"]

main_scene = read("game/main.tscn")
player_capsule = tscn_subresource(main_scene, "CapsuleShape3D", "CapsuleShape_player")
close(tscn_float(player_capsule, "height"), float(anchors["player_physics"]["height_m"]), "player physics height")
close(tscn_float(player_capsule, "radius"), float(anchors["player_physics"]["radius_m"]), "player physics radius")

camera = read("game/scripts/gta_scale_camera_runtime.gd")
require(camera, "The world remains metre-authored", "camera world-scale rail")
close(gd_const(camera, "TARGET_PLAYER_VISUAL_HEIGHT_M"), float(anchors["player_visual"]["height_m"]), "player visual height")

npc = read("game/scripts/npc_appearance_profile.gd")
require(npc, "lerpf(0.92, 1.08", "NPC stature bounds")
close(float(anchors["npc_stature"]["min_scale"]), 0.92, "NPC min stature")
close(float(anchors["npc_stature"]["max_scale"]), 1.08, "NPC max stature")

civilian = read("game/scripts/civilian_vehicle_visual.gd")
require(civilian, '"brand_specific": false', "civilian vehicle provenance")
for name, dims in anchors["civilian_vehicle_profiles"].items():
    if name in {"authority", "brand_specific"}:
        continue
    require(civilian, f'"name": "{name}"', f"civilian {name}")
    for field, value in dims.items():
        pattern = rf'"{re.escape(field)}"\s*:\s*{float(value):.2f}\b'
        assert re.search(pattern, civilian), f"civilian {name} {field} drifted"

police = anchors["police_vehicles"]
assert police["authority"] == "authored_metric"
assert police["official_model_dimensions_claimed"] is False
for key, rel in {
    "patrol": "game/vehicles/police_patrol.tscn",
    "civil": "game/vehicles/police_civil.tscn",
    "bab_van": "game/vehicles/police_bab_van.tscn",
}.items():
    text = read(rel)
    dims = police[key]
    size_match = re.search(r"size = Vector3\(([^,]+),\s*([^,]+),\s*([^\)]+)\)", text)
    assert size_match, f"police {key}: collision size missing"
    actual = tuple(float(size_match.group(i)) for i in range(1, 4))
    expected = (float(dims["width_m"]), float(dims["collision_height_m"]), float(dims["length_m"]))
    for index, label in enumerate(("width", "height", "length")):
        close(actual[index], expected[index], f"police {key} {label}")
    wheel = re.search(r"top_radius = (\d+(?:\.\d+)?)", text)
    assert wheel, f"police {key}: wheel radius missing"
    close(float(wheel.group(1)), float(dims["wheel_radius_m"]), f"police {key} wheel")

sidewalk = read("game/scripts/anneessens_midi_sidewalk_runtime.gd")
for const_name, field in {
    "SIDEWALK_HEIGHT_M": "height_m",
    "NARROW_SIDEWALK_WIDTH_M": "narrow_width_m",
    "WIDE_SIDEWALK_WIDTH_M": "wide_width_m",
    "CURB_GAP_M": "curb_gap_m",
}.items():
    close(gd_const(sidewalk, const_name), float(anchors["anneessens_midi_sidewalk"][field]), f"sidewalk {field}")

road = read("game/scripts/automatic_road_direct_spawn.gd")
require(road, 'properties.get("width_m", 0.0)', "road source width")
assert anchors["road_widths"]["authority"] == "heuristic_fallback"
assert anchors["road_widths"]["source_width_takes_precedence"] is True
assert anchors["road_widths"]["precise_real_width_claimed"] is False

for anchor_key, rel, checks in (
    ("bollard", "game/scripts/brussels_bollard_asset.gd", {"BODY_HEIGHT": "body_height_m", "CAP_HEIGHT": "cap_height_m", "COLLISION_HEIGHT": "collision_height_m"}),
    ("street_lamp", "game/scripts/brussels_street_lamp_asset.gd", {"POLE_HEIGHT": "pole_height_m", "ARM_LENGTH": "arm_length_m"}),
    ("street_tree", "game/scripts/brussels_street_tree_asset.gd", {"TRUNK_HEIGHT": "trunk_height_m", "FOLIAGE_RADIUS": "foliage_radius_m"}),
):
    text = read(rel)
    anchor = anchors[anchor_key]
    assert anchor["authority"] == "authored_presentation"
    assert anchor["source_dimensions_measured"] is False
    for const_name, field in checks.items():
        close(gd_const(text, const_name), float(anchor[field]), f"{anchor_key} {field}")

tree = read("game/scripts/brussels_street_tree_asset.gd")
require(tree, "return 0.92 + float(bucket) * 0.016", "tree variation scale")
close(float(anchors["street_tree"]["variation_scale_min"]), 0.92, "tree variation min")
close(float(anchors["street_tree"]["variation_scale_max"]), 1.08, "tree variation max")

lambert_path = ROOT / "tools/lambert72_to_game_geojson.py"
spec = importlib.util.spec_from_file_location("lambert72_to_game_geojson", lambert_path)
assert spec and spec.loader
lambert = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lambert)
oe, on = lambert.DEFAULT_ORIGIN_E, lambert.DEFAULT_ORIGIN_N
p0 = lambert.transform_position([oe, on], oe, on, 0.0)
px = lambert.transform_position([oe + 100.0, on], oe, on, 0.0)
pz = lambert.transform_position([oe, on + 100.0], oe, on, 0.0)
close(math.dist(p0, px), 100.0, "Lambert east distance")
close(math.dist(p0, pz), 100.0, "Lambert north distance")
converted = lambert.convert_document({"type": "Point", "coordinates": [oe + 3.0, on + 4.0]}, oe, on, 0.0)
assert converted["grand_bruxelles_coordinate_system"]["units"] == "metres"
close(math.hypot(*converted["coordinates"]), 5.0, "Lambert 3-4-5 distance")

print("WORLD_METRIC_PROPORTION_OK units=1m player=1.80m radius=0.42m visual=1.78m npc=0.92-1.08 vehicles=metric sidewalks=metric roads=source-first/fallback-labeled furniture=authored-metric geography=distance-preserving")
