from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
PROJECT_PATH = ROOT / "project.godot"
EXPECTED_SCHEMA = "grand-bruxelles-shared-environment-lifecycle-contract-v4"
LEGACY_POLL_RE = re.compile(r"for\s+[^\n]+\s+in\s+range\(\s*(120|180|240)\s*\)")
AUTOLOAD_RE = re.compile(
    r'^\s*(?P<name>[A-Za-z0-9_]+)\s*=\s*"\*res://(?P<path>game/scripts/[^"\n]+\.gd)"\s*$',
    re.MULTILINE,
)
EXPECTED_AUTOLOADS = {
    "MidiBlueStoneSurfaceRuntime": "game/scripts/midi_blue_stone_surface_runtime.gd",
    "MidiArchitecturalConcreteSurfaceRuntime": "game/scripts/midi_architectural_concrete_surface_runtime.gd",
    "MidiArchitecturalGlazingSurfaceRuntime": "game/scripts/midi_architectural_glazing_surface_runtime.gd",
    "MidiFauquenbergBrickSurfaceRuntime": "game/scripts/midi_fauquenberg_brick_surface_runtime.gd",
    "AnneessensMidiSidewalkRuntime": "game/scripts/anneessens_midi_sidewalk_runtime.gd",
    "AnneessensOsmFurnitureRuntime": "game/scripts/anneessens_osm_furniture_runtime.gd",
    "IxellesMidiSidewalkRuntime": "game/scripts/ixelles_midi_sidewalk_runtime.gd",
    "BrusselsOsmRoadSurfaceRuntime": "game/scripts/brussels_osm_road_surface_runtime.gd",
    "BrusselsBaseGroundSurfaceRuntime": "game/scripts/brussels_base_ground_surface_runtime.gd",
    "BrusselsOsmSidewalkSurfaceRuntime": "game/scripts/brussels_osm_sidewalk_surface_runtime.gd",
    "BrusselsOsmFacadeSurfaceRuntime": "game/scripts/brussels_osm_facade_surface_runtime.gd",
    "BrusselsOsmFacadeArticulationRuntime": "game/scripts/brussels_osm_facade_articulation_runtime.gd",
    "BrusselsOsmRailSurfaceRuntime": "game/scripts/brussels_osm_rail_surface_runtime.gd",
    "BrusselsBollardRuntime": "game/scripts/brussels_bollard_runtime.gd",
    "BrusselsStreetLampRuntime": "game/scripts/brussels_street_lamp_runtime.gd",
    "BrusselsCorridorTreeRuntime": "game/scripts/brussels_corridor_tree_runtime.gd",
}
GLOBAL_TREE_SCAN_TOKENS = (
    "get_tree().root",
    ".find_child(",
    ".find_children(",
    "_find_nested_production_scene(",
    "_find_production_scene(",
)


def fail(message: str) -> None:
    raise AssertionError(message)


def top_level_function_body(source: str, function_name: str) -> str:
    lines = source.splitlines()
    marker = f"func {function_name}("
    start = None
    for index, line in enumerate(lines):
        if line.startswith(marker):
            start = index + 1
            break
    if start is None:
        return ""
    body: list[str] = []
    for line in lines[start:]:
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break
        body.append(line)
    return "\n".join(body)


def assert_no_per_frame_global_tree_scan(source: str, rel_path: str) -> None:
    for function_name in ("_process", "_physics_process"):
        body = top_level_function_body(source, function_name)
        if not body:
            continue
        for token in GLOBAL_TREE_SCAN_TOKENS:
            if token in body:
                fail(
                    f"per-frame global SceneTree discovery reintroduced: {rel_path} "
                    f"function={function_name} token={token}"
                )


def main() -> None:
    if not CONTRACT_PATH.is_file():
        fail("shared Environment lifecycle contract missing")
    if not PROJECT_PATH.is_file():
        fail("project.godot missing; cannot verify production autoload lifecycle coverage")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("schema") != EXPECTED_SCHEMA:
        fail("shared Environment lifecycle contract schema mismatch")
    if contract.get("runtime_policy") != "dormant_event_driven_nested_mount_safe":
        fail("shared Environment lifecycle policy mismatch")
    if contract.get("legitimate_absence_is_failure") is not False:
        fail("legitimate partial-mount absence must remain dormant")
    if contract.get("geometry_or_material_change_authorized") is not False:
        fail("lifecycle contract must not authorize geometry/material changes")
    if contract.get("registry_complete_for_known_event_driven_runtimes") is not True:
        fail("shared Environment lifecycle registry completeness rail missing")
    if contract.get("production_autoload_identity_locked") is not True:
        fail("shared Environment production autoload identity rail missing")
    if contract.get("per_frame_global_tree_scan_forbidden") is not True:
        fail("per-frame global SceneTree discovery rail missing")

    project_source = PROJECT_PATH.read_text(encoding="utf-8")
    project_pairs = [(m.group("name"), m.group("path")) for m in AUTOLOAD_RE.finditer(project_source)]
    project_names = [name for name, _ in project_pairs]
    project_paths = [path for _, path in project_pairs]
    if len(project_names) != len(set(project_names)):
        fail("duplicate production autoload alias detected")
    if len(project_paths) != len(set(project_paths)):
        fail("same runtime script registered under multiple production autoload aliases")
    autoload_map = dict(project_pairs)
    for expected_name, expected_path in EXPECTED_AUTOLOADS.items():
        actual_path = autoload_map.get(expected_name)
        if actual_path != expected_path:
            fail(
                f"shared Environment production autoload identity drifted: "
                f"{expected_name} expected={expected_path} actual={actual_path}"
            )

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment lifecycle runtime registry missing")
    if contract.get("registered_runtime_count") != len(EXPECTED_AUTOLOADS):
        fail("registered runtime count metadata mismatch")

    seen_paths: set[str] = set()
    seen_names: set[str] = set()
    for entry in runtimes:
        if not isinstance(entry, dict):
            fail("malformed lifecycle runtime entry")
        autoload_name = entry.get("autoload_name")
        rel_path = entry.get("path")
        if not isinstance(autoload_name, str) or autoload_name not in EXPECTED_AUTOLOADS:
            fail(f"invalid lifecycle autoload name: {autoload_name}")
        if not isinstance(rel_path, str) or not rel_path.startswith("game/scripts/"):
            fail("invalid lifecycle runtime path")
        if autoload_name in seen_names:
            fail(f"duplicate lifecycle autoload alias: {autoload_name}")
        if rel_path in seen_paths:
            fail(f"duplicate lifecycle runtime path: {rel_path}")
        seen_names.add(autoload_name)
        seen_paths.add(rel_path)
        if EXPECTED_AUTOLOADS[autoload_name] != rel_path:
            fail(f"contract autoload/path pair drifted: {autoload_name} -> {rel_path}")
        if entry.get("event_signal") != "SceneTree.node_added":
            fail(f"runtime lost node_added lifecycle contract: {rel_path}")
        if entry.get("nested_mount_recovery") is not True:
            fail(f"runtime lost bounded nested-mount recovery contract: {rel_path}")
        if entry.get("late_child_bind") not in (True, False):
            fail(f"runtime late-child policy missing: {rel_path}")

        script_path = ROOT / rel_path
        if not script_path.is_file():
            fail(f"registered lifecycle runtime missing: {rel_path}")
        source = script_path.read_text(encoding="utf-8")
        if LEGACY_POLL_RE.search(source):
            fail(f"legacy 120/180/240-frame global polling reintroduced: {rel_path}")
        if "node_added" not in source:
            fail(f"event-driven wakeup missing from runtime: {rel_path}")
        assert_no_per_frame_global_tree_scan(source, rel_path)

    if seen_names != set(EXPECTED_AUTOLOADS):
        fail("lifecycle registry autoload alias set drifted")
    if seen_paths != set(EXPECTED_AUTOLOADS.values()):
        fail("lifecycle registry runtime path set drifted")

    print(
        "SHARED_ENVIRONMENT_LIFECYCLE_CONTRACT_OK: "
        f"runtimes={len(runtimes)} autoload_identity=locked "
        "per_frame_global_tree_scan=0 legacy_polling=0 "
        "policy=dormant_event_driven_nested_mount_safe"
    )


if __name__ == "__main__":
    main()
