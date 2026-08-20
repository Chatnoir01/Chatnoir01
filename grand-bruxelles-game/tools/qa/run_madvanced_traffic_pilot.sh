#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_ROOT="$REPO_ROOT/grand-bruxelles-game"
CONTRACT="$PROJECT_ROOT/data/qa/madvanced_traffic_pilot_contract.json"
WORK_ROOT="${RUNNER_TEMP:-/tmp}/grand-bruxelles-madvanced-traffic-pilot"
UPSTREAM="$WORK_ROOT/upstream"
PILOT_PROJECT="$WORK_ROOT/project"
BIN_DIR="$WORK_ROOT/bin"
EVIDENCE="$WORK_ROOT/evidence"
PROBE_DIR="$PILOT_PROJECT/addons/madvanced_traffic_probe"

rm -rf "$WORK_ROOT"
mkdir -p "$BIN_DIR" "$EVIDENCE"

read_contract() {
  python3 - "$CONTRACT" "$1" <<'PY'
import json
import sys
from pathlib import Path
obj = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = obj
for part in sys.argv[2].split('.'):
    value = value[part]
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

UPSTREAM_REPO="$(read_contract upstream.repository)"
EXPECTED_COMMIT="$(read_contract upstream.commit)"
ASSET_VERSION="$(read_contract upstream.asset_library_version)"
GODOT_VERSION="$(read_contract engine.version)"

if [[ "$GODOT_VERSION" != "4.7.1-stable" ]]; then
  echo "MADVANCED_TRAFFIC_PILOT_FAIL unexpected engine version: $GODOT_VERSION" >&2
  exit 2
fi

if [[ -d "$PROJECT_ROOT/addons/M.A.V.S" ]] || grep -q 'M.A.V.S' "$PROJECT_ROOT/project.godot"; then
  echo "MADVANCED_TRAFFIC_PILOT_FAIL canonical project already contains/enables M.A.V.S" >&2
  exit 3
fi

printf 'MADVANCED_TRAFFIC_PILOT_PHASE source_pin\n'
git init -q "$UPSTREAM"
git -C "$UPSTREAM" remote add origin "$UPSTREAM_REPO"
git -C "$UPSTREAM" fetch -q --depth 1 origin "$EXPECTED_COMMIT"
git -C "$UPSTREAM" checkout -q FETCH_HEAD
actual_commit="$(git -C "$UPSTREAM" rev-parse HEAD)"
if [[ "$actual_commit" != "$EXPECTED_COMMIT" ]]; then
  echo "MADVANCED_TRAFFIC_PILOT_FAIL upstream commit $actual_commit != $EXPECTED_COMMIT" >&2
  exit 4
fi
if ! grep -qi 'MIT License' "$UPSTREAM/LICENSE"; then
  echo "MADVANCED_TRAFFIC_PILOT_FAIL upstream license is not MIT" >&2
  exit 5
fi
printf '%s\n' "$actual_commit" > "$EVIDENCE/upstream-commit.txt"
cp "$UPSTREAM/LICENSE" "$EVIDENCE/upstream-LICENSE.txt"

printf 'MADVANCED_TRAFFIC_PILOT_PHASE dependency_audit\n'
python3 - "$UPSTREAM" "$CONTRACT" "$EVIDENCE/dependency-audit.json" <<'PY'
import json
import sys
from pathlib import Path
upstream = Path(sys.argv[1])
contract = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
out = Path(sys.argv[3])
spawner = (upstream / "addons/M.A.V.S/Scripts/traffic_spawner.gd").read_text(encoding="utf-8")
target = (upstream / "addons/M.A.V.S/Scripts/Path_Follow_Setup.gd").read_text(encoding="utf-8")
manager = (upstream / "addons/M.A.V.S/Scripts/MPathManager.gd").read_text(encoding="utf-8")
vehicle_props = contract["vehicle_contract_properties"]
missing = [name for name in vehicle_props if f"selected_car.{name}" not in spawner]
if missing:
    raise SystemExit(f"MADVANCED_TRAFFIC_PILOT_FAIL expected vehicle coupling tokens missing: {missing}")
checks = {
    "spawner_accepts_path3d": "@export var road_line : Path3D" in spawner,
    "spawner_uses_player_car_group": 'get_nodes_in_group("Player_car")' in spawner,
    "target_extends_pathfollow3d": "extends PathFollow3D" in target,
    "target_requires_vehiclebody3d": "target_veh : VehicleBody3D" in target,
    "path_manager_extends_path3d": "extends Path3D" in manager,
    "path_manager_links_roads": "roads : Array[MPathManager]" in manager,
}
if not all(checks.values()):
    raise SystemExit(f"MADVANCED_TRAFFIC_PILOT_FAIL dependency contract mismatch: {checks}")
report = {
    "asset_library_version": contract["upstream"]["asset_library_version"],
    "upstream_commit": contract["upstream"]["commit"],
    "logic_subset": ["MPathManager", "MTrafficTarget", "MTrafficSpawner"],
    "checks": checks,
    "vehicle_contract_properties": vehicle_props,
    "vehicle_contract_property_count": len(vehicle_props),
    "verdict_hint": "path layer modular; spawner coupled to MAdvanced vehicle API",
}
out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print("MADVANCED_TRAFFIC_DEPENDENCY_AUDIT_GREEN", json.dumps(report, sort_keys=True))
PY

GODOT_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_BIN="$BIN_DIR/Godot_v4.7.1-stable_linux.x86_64"
printf 'MADVANCED_TRAFFIC_PILOT_PHASE godot_4_7_1\n'
curl -fL --retry 3 --retry-delay 3 \
  "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/$GODOT_ZIP" \
  -o "$WORK_ROOT/$GODOT_ZIP"
unzip -q "$WORK_ROOT/$GODOT_ZIP" -d "$BIN_DIR"
chmod +x "$GODOT_BIN"
"$GODOT_BIN" --version | tee "$EVIDENCE/godot-version.txt"
grep -q '^4\.7\.1\.stable' "$EVIDENCE/godot-version.txt"

printf 'MADVANCED_TRAFFIC_PILOT_PHASE isolated_logic_subset\n'
cp -a "$PROJECT_ROOT" "$PILOT_PROJECT"
mkdir -p "$PROBE_DIR"
for src in MPathManager.gd Path_Follow_Setup.gd traffic_spawner.gd; do
  sed '/^@icon(/d' "$UPSTREAM/addons/M.A.V.S/Scripts/$src" > "$PROBE_DIR/$src"
done
grep -q 'renderer/rendering_method="gl_compatibility"' "$PILOT_PROJECT/project.godot"

cat > "$PILOT_PROJECT/madvanced_traffic_pilot_smoke.gd" <<'GDSCRIPT'
extends SceneTree

func fail(message: String, code: int) -> void:
    push_error("MADVANCED_TRAFFIC_PILOT_FAIL " + message)
    quit(code)

func _init() -> void:
    var required_classes := ["MPathManager", "MTrafficTarget", "MTrafficSpawner"]
    var class_paths := {}
    for entry in ProjectSettings.get_global_class_list():
        class_paths[str(entry.get("class", ""))] = str(entry.get("path", ""))
    for required_class_name in required_classes:
        if not class_paths.has(required_class_name) or str(class_paths[required_class_name]).is_empty():
            fail("missing global class %s" % required_class_name, 20)
            return

    var manager_script: Script = load(str(class_paths["MPathManager"]))
    var manager = manager_script.new()
    if manager == null or not manager is Path3D:
        fail("MPathManager is not Path3D", 21)
        return
    manager.curve = Curve3D.new()
    manager.curve.add_point(Vector3(0.0, 0.0, 0.0))
    manager.curve.add_point(Vector3(20.0, 0.0, 0.0))
    var path_length: float = float(manager.curve.get_baked_length())
    if path_length < 19.9 or path_length > 20.1:
        fail("unexpected MPathManager length %.3f" % path_length, 22)
        return

    var target_script: Script = load(str(class_paths["MTrafficTarget"]))
    var target = target_script.new()
    if target == null or not target is PathFollow3D:
        fail("MTrafficTarget is not PathFollow3D", 23)
        return
    manager.add_child(target)
    target.active = true
    target.speed = 20.0
    target.sensors = []
    target._physics_process(0.25)
    var progress_after_step: float = float(target.progress)
    if progress_after_step < 4.9 or progress_after_step > 5.1:
        fail("traffic target did not advance predictably: %.3f" % progress_after_step, 24)
        return

    var spawner_script: Script = load(str(class_paths["MTrafficSpawner"]))
    var spawner = spawner_script.new()
    if spawner == null or not spawner is Node3D:
        fail("MTrafficSpawner is not Node3D", 25)
        return
    spawner.road_line = manager
    if spawner.road_line != manager:
        fail("MTrafficSpawner rejected generic Path3D road_line", 26)
        return

    var spawner_props := {}
    for item in spawner.get_property_list():
        spawner_props[str(item.get("name", ""))] = true
    for required_prop in ["allow_despawn", "generation_distance", "spawn_limiter", "vehicle_pool", "traffic_manager", "road_line"]:
        if not spawner_props.has(required_prop):
            fail("MTrafficSpawner missing property %s" % required_prop, 27)
            return

    print("MADVANCED_TRAFFIC_LOGIC_GREEN")
    print("path_length=%.3f" % path_length)
    print("target_progress_after_0_25s=%.3f" % progress_after_step)
    print("spawner_accepts_generic_path3d=true")
    print("vehicle_api_coupling_count=4")
    quit(0)
GDSCRIPT

printf 'MADVANCED_TRAFFIC_PILOT_PHASE editor_import\n'
set +e
timeout 45 "$GODOT_BIN" --headless --editor --path "$PILOT_PROJECT" --audio-driver Dummy > "$EVIDENCE/editor-import.log" 2>&1
editor_rc=$?
set -e
if [[ "$editor_rc" -ne 0 && "$editor_rc" -ne 124 ]]; then
  cat "$EVIDENCE/editor-import.log"
  echo "MADVANCED_TRAFFIC_PILOT_FAIL editor import exited with $editor_rc" >&2
  exit 6
fi
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class' "$EVIDENCE/editor-import.log" | grep -E 'madvanced_traffic_probe|MPathManager|MTrafficTarget|MTrafficSpawner'; then
  echo "MADVANCED_TRAFFIC_PILOT_FAIL donor logic subset produced script/import errors" >&2
  exit 7
fi

printf 'MADVANCED_TRAFFIC_PILOT_PHASE logic_smoke\n'
"$GODOT_BIN" --headless --path "$PILOT_PROJECT" --audio-driver Dummy --script res://madvanced_traffic_pilot_smoke.gd \
  | tee "$EVIDENCE/logic-smoke.log"
grep -q 'MADVANCED_TRAFFIC_LOGIC_GREEN' "$EVIDENCE/logic-smoke.log"

printf 'MADVANCED_TRAFFIC_PILOT_PHASE canonical_clean\n'
test ! -d "$PROJECT_ROOT/addons/M.A.V.S"
! grep -q 'M.A.V.S' "$PROJECT_ROOT/project.godot"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game)" ]]; then
  git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game >&2
  echo "MADVANCED_TRAFFIC_PILOT_FAIL canonical project tree changed" >&2
  exit 8
fi

cat > "$EVIDENCE/result.txt" <<EOF
MADVANCED_TRAFFIC_DONOR_PILOT_GREEN
base_main=$(read_contract base_main_sha)
asset_library_version=$ASSET_VERSION
upstream_commit=$actual_commit
godot_version=$GODOT_VERSION
renderer=gl_compatibility
path_layer_modular=true
spawner_vehicle_api_coupling_count=4
canonical_addon_installed=false
third_party_visual_assets_authorized=false
replace_osm_urbis_geometry_authorized=false
replace_existing_traffic_manager_authorized=false
replace_existing_vehicle_runtime_authorized=false
runtime_authorized=false
export_authorized=false
verdict=donor_only_not_drop_in_replacement
EOF
cat "$EVIDENCE/result.txt"
