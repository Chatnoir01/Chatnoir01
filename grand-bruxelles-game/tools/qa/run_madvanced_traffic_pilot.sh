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
mkdir -p "$BIN_DIR" "$EVIDENCE" "$PROBE_DIR"

read_contract() {
  python3 - "$CONTRACT" "$1" <<'PY'
import json, sys
from pathlib import Path
value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for part in sys.argv[2].split('.'):
    value = value[part]
print(json.dumps(value) if isinstance(value, (dict, list)) else value)
PY
}

UPSTREAM_REPO="$(read_contract upstream.repository)"
EXPECTED_COMMIT="$(read_contract upstream.commit)"
ASSET_VERSION="$(read_contract upstream.asset_library_version)"
GODOT_VERSION="$(read_contract engine.version)"

if [[ -d "$PROJECT_ROOT/addons/M.A.V.S" ]] || grep -q 'M.A.V.S' "$PROJECT_ROOT/project.godot"; then
  echo "MADVANCED_TRAFFIC_PILOT_FAIL canonical project contains M.A.V.S" >&2
  exit 3
fi

printf 'MADVANCED_TRAFFIC_PILOT_PHASE source_pin\n'
git init -q "$UPSTREAM"
git -C "$UPSTREAM" remote add origin "$UPSTREAM_REPO"
git -C "$UPSTREAM" fetch -q --depth 1 origin "$EXPECTED_COMMIT"
git -C "$UPSTREAM" checkout -q FETCH_HEAD
actual_commit="$(git -C "$UPSTREAM" rev-parse HEAD)"
[[ "$actual_commit" == "$EXPECTED_COMMIT" ]]
grep -qi 'MIT License' "$UPSTREAM/LICENSE"
printf '%s\n' "$actual_commit" > "$EVIDENCE/upstream-commit.txt"
cp "$UPSTREAM/LICENSE" "$EVIDENCE/upstream-LICENSE.txt"

printf 'MADVANCED_TRAFFIC_PILOT_PHASE dependency_audit\n'
python3 - "$UPSTREAM" "$CONTRACT" "$EVIDENCE/dependency-audit.json" <<'PY'
import json, sys
from pathlib import Path
upstream = Path(sys.argv[1])
contract = json.loads(Path(sys.argv[2]).read_text())
spawner = (upstream / "addons/M.A.V.S/Scripts/traffic_spawner.gd").read_text()
target = (upstream / "addons/M.A.V.S/Scripts/Path_Follow_Setup.gd").read_text()
manager = (upstream / "addons/M.A.V.S/Scripts/MPathManager.gd").read_text()
vehicle_props = contract["vehicle_contract_properties"]
checks = {
  "spawner_accepts_path3d": "@export var road_line : Path3D" in spawner,
  "spawner_uses_player_car_group": 'get_nodes_in_group("Player_car")' in spawner,
  "target_extends_pathfollow3d": "extends PathFollow3D" in target,
  "target_requires_vehiclebody3d": "target_veh : VehicleBody3D" in target,
  "path_manager_extends_path3d": "extends Path3D" in manager,
  "path_manager_links_roads": "roads : Array[MPathManager]" in manager,
  "vehicle_api_coupling_present": all(f"selected_car.{p}" in spawner for p in vehicle_props),
}
if not all(checks.values()):
    raise SystemExit(f"MADVANCED_TRAFFIC_PILOT_FAIL dependency mismatch {checks}")
report = {"checks": checks, "vehicle_contract_properties": vehicle_props, "vehicle_contract_property_count": len(vehicle_props), "verdict_hint": "donor_only_not_drop_in_replacement"}
Path(sys.argv[3]).write_text(json.dumps(report, indent=2) + "\n")
print("MADVANCED_TRAFFIC_DEPENDENCY_AUDIT_GREEN", json.dumps(report, sort_keys=True))
PY

printf 'MADVANCED_TRAFFIC_PILOT_PHASE godot_4_7_1\n'
GODOT_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_BIN="$BIN_DIR/Godot_v4.7.1-stable_linux.x86_64"
curl -fsSL --retry 3 "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/$GODOT_ZIP" -o "$WORK_ROOT/$GODOT_ZIP"
unzip -q "$WORK_ROOT/$GODOT_ZIP" -d "$BIN_DIR"
chmod +x "$GODOT_BIN"
"$GODOT_BIN" --version | tee "$EVIDENCE/godot-version.txt"
grep -q '^4\.7\.1\.stable' "$EVIDENCE/godot-version.txt"

printf 'MADVANCED_TRAFFIC_PILOT_PHASE isolated_logic_subset\n'
cat > "$PILOT_PROJECT/project.godot" <<'EOF'
[application]
config/name="Grand Bruxelles MAdvanced Donor Probe"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF
for src in MPathManager.gd Path_Follow_Setup.gd traffic_spawner.gd; do
  sed '/^@icon(/d' "$UPSTREAM/addons/M.A.V.S/Scripts/$src" > "$PROBE_DIR/$src"
done

cat > "$PILOT_PROJECT/smoke.gd" <<'GDSCRIPT'
extends SceneTree

func fail(message: String, code: int) -> void:
    push_error("MADVANCED_TRAFFIC_PILOT_FAIL " + message)
    quit(code)

func _init() -> void:
    var classes := {}
    for entry in ProjectSettings.get_global_class_list():
        classes[str(entry.get("class", ""))] = str(entry.get("path", ""))
    for required in ["MPathManager", "MTrafficTarget", "MTrafficSpawner"]:
        if not classes.has(required):
            fail("missing class " + required, 20)
            return

    var manager = load(classes["MPathManager"]).new()
    if not manager is Path3D:
        fail("MPathManager is not Path3D", 21)
        return
    manager.curve = Curve3D.new()
    manager.curve.add_point(Vector3.ZERO)
    manager.curve.add_point(Vector3(20.0, 0.0, 0.0))
    var path_length: float = float(manager.curve.get_baked_length())

    var target = load(classes["MTrafficTarget"]).new()
    if not target is PathFollow3D:
        fail("MTrafficTarget is not PathFollow3D", 22)
        return
    manager.add_child(target)
    target.active = true
    target.speed = 20.0
    target.sensors = []
    target._physics_process(0.25)
    var progress: float = float(target.progress)
    if progress < 4.9 or progress > 5.1:
        fail("unexpected target progress %.3f" % progress, 23)
        return

    var spawner = load(classes["MTrafficSpawner"]).new()
    if not spawner is Node3D:
        fail("MTrafficSpawner is not Node3D", 24)
        return
    spawner.road_line = manager
    if spawner.road_line != manager:
        fail("spawner rejected generic Path3D", 25)
        return

    print("MADVANCED_TRAFFIC_LOGIC_GREEN")
    print("path_length=%.3f" % path_length)
    print("target_progress_after_0_25s=%.3f" % progress)
    print("spawner_accepts_generic_path3d=true")
    print("vehicle_api_coupling_count=4")
    quit(0)
GDSCRIPT

"$GODOT_BIN" --headless --editor --path "$PILOT_PROJECT" --quit-after 3 --audio-driver Dummy > "$EVIDENCE/editor-import.log" 2>&1
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class' "$EVIDENCE/editor-import.log"; then
  cat "$EVIDENCE/editor-import.log"
  exit 7
fi
"$GODOT_BIN" --headless --path "$PILOT_PROJECT" --audio-driver Dummy --script res://smoke.gd | tee "$EVIDENCE/logic-smoke.log"
grep -q 'MADVANCED_TRAFFIC_LOGIC_GREEN' "$EVIDENCE/logic-smoke.log"

printf 'MADVANCED_TRAFFIC_PILOT_PHASE canonical_clean\n'
test ! -d "$PROJECT_ROOT/addons/M.A.V.S"
! grep -q 'M.A.V.S' "$PROJECT_ROOT/project.godot"

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
