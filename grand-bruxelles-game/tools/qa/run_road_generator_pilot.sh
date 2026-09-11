#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_ROOT="$REPO_ROOT/grand-bruxelles-game"
CONTRACT="$PROJECT_ROOT/data/qa/road_generator_pilot_contract.json"
WORK_ROOT="${RUNNER_TEMP:-/tmp}/grand-bruxelles-road-generator-pilot"
UPSTREAM="$WORK_ROOT/upstream"
PILOT_PROJECT="$WORK_ROOT/project"
BIN_DIR="$WORK_ROOT/bin"
EVIDENCE="$WORK_ROOT/evidence"

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
UPSTREAM_TAG="$(read_contract upstream.tag)"
EXPECTED_COMMIT="$(read_contract upstream.commit)"
ADDON_SOURCE="$(read_contract upstream.addon_source_path)"
GODOT_VERSION="$(read_contract engine.version)"

if [[ "$GODOT_VERSION" != "4.7.1-stable" ]]; then
  echo "ROAD_GENERATOR_PILOT_FAIL unexpected engine version: $GODOT_VERSION" >&2
  exit 2
fi

if [[ -d "$PROJECT_ROOT/addons/road-generator" ]] || grep -q 'road-generator' "$PROJECT_ROOT/project.godot"; then
  echo "ROAD_GENERATOR_PILOT_FAIL canonical project already contains/enables Road Generator" >&2
  exit 3
fi

GODOT_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_BIN="$BIN_DIR/Godot_v4.7.1-stable_linux.x86_64"

printf 'ROAD_GENERATOR_PILOT_PHASE source_pin\n'
git clone --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO" "$UPSTREAM"
actual_commit="$(git -C "$UPSTREAM" rev-parse HEAD)"
if [[ "$actual_commit" != "$EXPECTED_COMMIT" ]]; then
  echo "ROAD_GENERATOR_PILOT_FAIL upstream commit $actual_commit != $EXPECTED_COMMIT" >&2
  exit 4
fi
if ! grep -qi 'MIT License' "$UPSTREAM/LICENSE"; then
  echo "ROAD_GENERATOR_PILOT_FAIL upstream license is not MIT" >&2
  exit 5
fi
printf '%s\n' "$actual_commit" > "$EVIDENCE/upstream-commit.txt"
cp "$UPSTREAM/LICENSE" "$EVIDENCE/upstream-LICENSE.txt"
cp "$UPSTREAM/$ADDON_SOURCE/plugin.cfg" "$EVIDENCE/upstream-plugin.cfg"

printf 'ROAD_GENERATOR_PILOT_PHASE godot_4_7_1\n'
curl -fL --retry 3 --retry-delay 3 \
  "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/$GODOT_ZIP" \
  -o "$WORK_ROOT/$GODOT_ZIP"
unzip -q "$WORK_ROOT/$GODOT_ZIP" -d "$BIN_DIR"
chmod +x "$GODOT_BIN"
"$GODOT_BIN" --version | tee "$EVIDENCE/godot-version.txt"
grep -q '^4\.7\.1\.stable' "$EVIDENCE/godot-version.txt"

printf 'ROAD_GENERATOR_PILOT_PHASE isolated_install\n'
cp -a "$PROJECT_ROOT" "$PILOT_PROJECT"
mkdir -p "$PILOT_PROJECT/addons"
cp -a "$UPSTREAM/$ADDON_SOURCE" "$PILOT_PROJECT/addons/road-generator"
cat >> "$PILOT_PROJECT/project.godot" <<'EOF'

[editor_plugins]

enabled=PackedStringArray("res://addons/road-generator/plugin.cfg")
EOF

test -f "$PILOT_PROJECT/addons/road-generator/plugin.cfg"
grep -q 'road-generator/plugin.cfg' "$PILOT_PROJECT/project.godot"
grep -q 'renderer/rendering_method="gl_compatibility"' "$PILOT_PROJECT/project.godot"

cat > "$PILOT_PROJECT/road_generator_pilot_smoke.gd" <<'GDSCRIPT'
extends SceneTree

func fail(message: String, code: int) -> void:
    push_error("ROAD_GENERATOR_PILOT_FAIL " + message)
    quit(code)

func _init() -> void:
    var required_classes := ["RoadManager", "RoadContainer", "RoadPoint", "RoadLane", "RoadLaneAgent"]
    var required_lane_properties := ["reverse_direction", "lane_left", "lane_right", "lane_next", "lane_prior"]
    var class_paths := {}
    for entry in ProjectSettings.get_global_class_list():
        class_paths[str(entry.get("class", ""))] = str(entry.get("path", ""))
    for required_class_name in required_classes:
        if not class_paths.has(required_class_name) or str(class_paths[required_class_name]).is_empty():
            fail("missing global class %s" % required_class_name, 20)
            return

    var lane_script: Script = load(str(class_paths["RoadLane"]))
    if lane_script == null:
        fail("RoadLane script could not load", 21)
        return
    var lane = lane_script.new()
    if lane == null or not lane is Path3D:
        fail("RoadLane is not a Path3D", 22)
        return

    var property_names := {}
    for item in lane.get_property_list():
        property_names[str(item.get("name", ""))] = true
    for property_name in required_lane_properties:
        if not property_names.has(property_name):
            fail("RoadLane missing property %s" % property_name, 23)
            return

    lane.curve = Curve3D.new()
    lane.curve.add_point(Vector3(0.0, 0.0, 0.0))
    lane.curve.add_point(Vector3(12.0, 0.0, 0.0))
    var baked_length: float = float(lane.curve.get_baked_length())
    if baked_length < 11.9 or baked_length > 12.1:
        fail("unexpected RoadLane baked length %.3f" % baked_length, 24)
        return

    print("ROAD_GENERATOR_LANE_API_GREEN")
    print("road_lane_path=" + str(class_paths["RoadLane"]))
    print("road_lane_agent_path=" + str(class_paths["RoadLaneAgent"]))
    print("road_lane_baked_length=%.3f" % baked_length)
    quit(0)
GDSCRIPT

printf 'ROAD_GENERATOR_PILOT_PHASE editor_import\n'
set +e
timeout 45 "$GODOT_BIN" --headless --editor --path "$PILOT_PROJECT" --audio-driver Dummy > "$EVIDENCE/editor-import.log" 2>&1
editor_rc=$?
set -e
if [[ "$editor_rc" -ne 0 && "$editor_rc" -ne 124 ]]; then
  cat "$EVIDENCE/editor-import.log"
  echo "ROAD_GENERATOR_PILOT_FAIL editor import exited with $editor_rc" >&2
  exit 6
fi
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class' "$EVIDENCE/editor-import.log"; then
  echo "ROAD_GENERATOR_PILOT_FAIL plugin produced script/import errors" >&2
  exit 7
fi

printf 'ROAD_GENERATOR_PILOT_PHASE lane_api\n'
"$GODOT_BIN" --headless --path "$PILOT_PROJECT" --audio-driver Dummy --script res://road_generator_pilot_smoke.gd \
  | tee "$EVIDENCE/lane-api.log"
grep -q 'ROAD_GENERATOR_LANE_API_GREEN' "$EVIDENCE/lane-api.log"

printf 'ROAD_GENERATOR_PILOT_PHASE canonical_clean\n'
test ! -d "$PROJECT_ROOT/addons/road-generator"
! grep -q 'road-generator' "$PROJECT_ROOT/project.godot"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game)" ]]; then
  git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game >&2
  echo "ROAD_GENERATOR_PILOT_FAIL canonical project tree changed" >&2
  exit 8
fi

cat > "$EVIDENCE/result.txt" <<EOF
ROAD_GENERATOR_ISOLATED_LANE_PILOT_GREEN
base_main=$(read_contract base_main_sha)
upstream_tag=$UPSTREAM_TAG
upstream_commit=$actual_commit
godot_version=$GODOT_VERSION
renderer=gl_compatibility
canonical_addon_installed=false
replace_osm_urbis_geometry_authorized=false
replace_existing_traffic_manager_authorized=false
runtime_authorized=false
export_authorized=false
EOF
cat "$EVIDENCE/result.txt"
