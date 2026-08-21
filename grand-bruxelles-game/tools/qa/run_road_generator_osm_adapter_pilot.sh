#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_ROOT="$REPO_ROOT/grand-bruxelles-game"
BASE_CONTRACT="$PROJECT_ROOT/data/qa/road_generator_pilot_contract.json"
ADAPTER_CONTRACT="$PROJECT_ROOT/data/qa/road_generator_osm_adapter_contract.json"
WORK_ROOT="${RUNNER_TEMP:-/tmp}/grand-bruxelles-road-generator-osm-adapter-pilot"
UPSTREAM="$WORK_ROOT/upstream"
PILOT_PROJECT="$WORK_ROOT/project"
BIN_DIR="$WORK_ROOT/bin"
EVIDENCE="$WORK_ROOT/evidence"

rm -rf "$WORK_ROOT"
mkdir -p "$BIN_DIR" "$EVIDENCE"

read_json() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path
obj = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = obj
for part in sys.argv[2].split('.'):
    value = value[part]
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False))
else:
    print(value)
PY
}

UPSTREAM_REPO="$(read_json "$BASE_CONTRACT" upstream.repository)"
UPSTREAM_TAG="$(read_json "$BASE_CONTRACT" upstream.tag)"
UPSTREAM_COMMIT="$(read_json "$BASE_CONTRACT" upstream.commit)"
ADDON_SOURCE="$(read_json "$BASE_CONTRACT" upstream.addon_source_path)"
GODOT_VERSION="$(read_json "$BASE_CONTRACT" engine.version)"
SOURCE_REL="$(read_json "$ADAPTER_CONTRACT" source.path)"
SOURCE_SHA256="$(read_json "$ADAPTER_CONTRACT" source.sha256)"
SOURCE_OSM_ID="$(read_json "$ADAPTER_CONTRACT" sample_road.osm_id)"
SOURCE_PATH="$PROJECT_ROOT/$SOURCE_REL"

if [[ "$GODOT_VERSION" != "4.7.1-stable" ]]; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL unexpected engine version: $GODOT_VERSION" >&2
  exit 2
fi
if [[ -d "$PROJECT_ROOT/addons/road-generator" ]] || grep -q 'road-generator' "$PROJECT_ROOT/project.godot"; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL canonical project contains/enables Road Generator" >&2
  exit 3
fi
if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL source road payload missing: $SOURCE_REL" >&2
  exit 4
fi

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE source_contract\n'
actual_source_sha="$(sha256sum "$SOURCE_PATH" | awk '{print $1}')"
if [[ "$actual_source_sha" != "$SOURCE_SHA256" ]]; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL source sha256 $actual_source_sha != $SOURCE_SHA256" >&2
  exit 5
fi
printf '%s\n' "$actual_source_sha" > "$EVIDENCE/source-sha256.txt"

python3 - "$SOURCE_PATH" "$ADAPTER_CONTRACT" "$EVIDENCE/source-sample.json" <<'PY'
import json
import math
import sys
from pathlib import Path
source_path = Path(sys.argv[1])
contract_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])
source = json.loads(source_path.read_text(encoding="utf-8"))
contract = json.loads(contract_path.read_text(encoding="utf-8"))
expected_source = contract["source"]
expected = contract["sample_road"]
if source.get("format") != expected_source["format"]:
    raise SystemExit("source format drift")
if source.get("source") != expected_source["source"]:
    raise SystemExit("source attribution drift")
if source.get("license") != expected_source["license"]:
    raise SystemExit("source license drift")
matches = [r for r in source.get("roads", []) if int(r.get("osm_id", -1)) == int(expected["osm_id"])]
if len(matches) != 1:
    raise SystemExit(f"expected exactly one road {expected['osm_id']}, found {len(matches)}")
road = matches[0]
checks = {
    "name": road.get("name") == expected["name"],
    "class": road.get("class") == expected["class"],
    "width_m": abs(float(road.get("width", -1)) - float(expected["width_m"])) <= 1e-9,
    "drivable": bool(road.get("drivable", False)) is bool(expected["drivable"]),
    "point_count": len(road.get("points", [])) == int(expected["point_count"]),
}
failed = [k for k, ok in checks.items() if not ok]
if failed:
    raise SystemExit("source road contract drift: " + ",".join(failed))
points = road["points"]
if len(points) < 2:
    raise SystemExit("source road has fewer than 2 points")
length = 0.0
for a, b in zip(points, points[1:]):
    if len(a) != 2 or len(b) != 2:
        raise SystemExit("road point is not game XZ pair")
    length += math.hypot(float(b[0]) - float(a[0]), float(b[1]) - float(a[1]))
if abs(length - float(expected["polyline_length_m"])) > 0.0005:
    raise SystemExit(f"source polyline length drift: {length:.9f}")
payload = {
    "source": expected_source["source"],
    "license": expected_source["license"],
    "source_path": expected_source["path"],
    "source_sha256": expected_source["sha256"],
    "road": road,
    "source_polyline_length_m": length,
}
out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"ROAD_GENERATOR_OSM_SOURCE_GREEN osm_id={road['osm_id']} points={len(points)} length_m={length:.6f}")
PY

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE source_pin\n'
git clone --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_REPO" "$UPSTREAM"
actual_commit="$(git -C "$UPSTREAM" rev-parse HEAD)"
if [[ "$actual_commit" != "$UPSTREAM_COMMIT" ]]; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL upstream commit $actual_commit != $UPSTREAM_COMMIT" >&2
  exit 6
fi
if ! grep -qi 'MIT License' "$UPSTREAM/LICENSE"; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL Road Generator license is not MIT" >&2
  exit 7
fi
printf '%s\n' "$actual_commit" > "$EVIDENCE/upstream-commit.txt"
cp "$UPSTREAM/LICENSE" "$EVIDENCE/upstream-LICENSE.txt"

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE godot_4_7_1\n'
GODOT_ZIP="Godot_v4.7.1-stable_linux.x86_64.zip"
GODOT_BIN="$BIN_DIR/Godot_v4.7.1-stable_linux.x86_64"
curl -fL --retry 3 --retry-delay 3 \
  "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/$GODOT_ZIP" \
  -o "$WORK_ROOT/$GODOT_ZIP"
unzip -q "$WORK_ROOT/$GODOT_ZIP" -d "$BIN_DIR"
chmod +x "$GODOT_BIN"
"$GODOT_BIN" --version | tee "$EVIDENCE/godot-version.txt"
grep -q '^4\.7\.1\.stable' "$EVIDENCE/godot-version.txt"

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE isolated_install\n'
cp -a "$PROJECT_ROOT" "$PILOT_PROJECT"
mkdir -p "$PILOT_PROJECT/addons/road-generator"
cp -a "$UPSTREAM/$ADDON_SOURCE/." "$PILOT_PROJECT/addons/road-generator/"
cp "$EVIDENCE/source-sample.json" "$PILOT_PROJECT/data/qa/road_generator_osm_adapter_sample.json"
cat >> "$PILOT_PROJECT/project.godot" <<'EOF'

[editor_plugins]

enabled=PackedStringArray("res://addons/road-generator/plugin.cfg")
EOF

test -f "$PILOT_PROJECT/addons/road-generator/plugin.cfg"
grep -q 'renderer/rendering_method="gl_compatibility"' "$PILOT_PROJECT/project.godot"

cat > "$PILOT_PROJECT/road_generator_osm_adapter_smoke.gd" <<'GDSCRIPT'
extends SceneTree

func fail(message: String, code: int) -> void:
    push_error("ROAD_GENERATOR_OSM_ADAPTER_FAIL " + message)
    quit(code)

func class_paths() -> Dictionary:
    var paths := {}
    for entry in ProjectSettings.get_global_class_list():
        paths[str(entry.get("class", ""))] = str(entry.get("path", ""))
    return paths

func _init() -> void:
    # SceneTree._init runs before Node3D global transforms are valid. Defer the
    # actual probe so the temporary test world is genuinely inside the tree.
    call_deferred("_run")

func _run() -> void:
    var sample_text := FileAccess.get_file_as_string("res://data/qa/road_generator_osm_adapter_sample.json")
    var sample_variant: Variant = JSON.parse_string(sample_text)
    if typeof(sample_variant) != TYPE_DICTIONARY:
        fail("adapter source sample is invalid JSON", 20)
        return
    var sample: Dictionary = sample_variant
    var road: Dictionary = sample.get("road", {})
    var points: Array = road.get("points", [])
    if int(road.get("osm_id", -1)) != 359177328 or not bool(road.get("drivable", false)):
        fail("source road identity/drivable contract failed", 21)
        return
    if points.size() != 6:
        fail("source road point count drift", 22)
        return

    var paths := class_paths()
    for required_class_name in ["RoadLane", "RoadLaneAgent"]:
        if not paths.has(required_class_name) or str(paths[required_class_name]).is_empty():
            fail("missing global class %s" % required_class_name, 23)
            return

    var lane_script: Script = load(str(paths["RoadLane"]))
    var agent_script: Script = load(str(paths["RoadLaneAgent"]))
    if lane_script == null or agent_script == null:
        fail("RoadLane/RoadLaneAgent script load failed", 24)
        return

    var lane = lane_script.new()
    if lane == null or not lane is Path3D:
        fail("RoadLane does not instantiate as Path3D", 25)
        return
    lane.name = "OSM_359177328_RoadLane_MetadataOnly"
    lane.set_meta("source", str(sample.get("source", "")))
    lane.set_meta("source_license", str(sample.get("license", "")))
    lane.set_meta("source_osm_id", int(road.get("osm_id", -1)))
    lane.set_meta("source_road_class", str(road.get("class", "")))
    lane.set_meta("source_width_m", float(road.get("width", 0.0)))
    lane.set_meta("source_drivable", bool(road.get("drivable", false)))
    lane.set_meta("geometry_role", "navigation_metadata_only")
    lane.curve = Curve3D.new()

    for raw_point: Variant in points:
        var source_point := Vector3(float(raw_point[0]), 0.0, float(raw_point[1]))
        lane.curve.add_point(source_point)

    if lane.curve.point_count != points.size():
        fail("RoadLane point count differs from source", 26)
        return
    for index: int in range(points.size()):
        var expected_point := Vector3(float(points[index][0]), 0.0, float(points[index][1]))
        var mapped_point: Vector3 = lane.curve.get_point_position(index)
        if mapped_point.distance_to(expected_point) > 0.0005:
            fail("source point %d moved during RoadLane mapping" % index, 27)
            return

    var source_length := float(sample.get("source_polyline_length_m", 0.0))
    var lane_length: float = float(lane.curve.get_baked_length())
    if absf(lane_length - source_length) > 0.05:
        fail("RoadLane length %.6f differs from source %.6f" % [lane_length, source_length], 28)
        return

    var test_world := Node3D.new()
    test_world.name = "RoadGeneratorOSMAdapterTestWorld"
    get_root().add_child(test_world)
    test_world.add_child(lane)
    if not lane.is_inside_tree():
        fail("RoadLane test node is not inside SceneTree", 32)
        return

    var actor := Node3D.new()
    actor.name = "RoadLaneAgentProbeActor"
    actor.position = lane.curve.get_point_position(0)
    test_world.add_child(actor)
    if not actor.is_inside_tree():
        fail("RoadLaneAgent actor is not inside SceneTree", 33)
        return

    var agent = agent_script.new()
    agent.set("actor", actor)
    agent.set("current_lane", lane)
    agent.set("auto_register", false)
    var moved_variant: Variant = agent.call("test_move_along_lane", 25.0)
    if typeof(moved_variant) != TYPE_VECTOR3:
        fail("RoadLaneAgent did not return a Vector3", 29)
        return
    var moved: Vector3 = moved_variant
    var moved_offset: float = float(lane.curve.get_closest_offset(lane.to_local(moved)))
    if absf(moved_offset - 25.0) > 0.10:
        fail("RoadLaneAgent offset %.6f != 25m probe" % moved_offset, 30)
        return

    if str(lane.get_meta("geometry_role", "")) != "navigation_metadata_only":
        fail("navigation-only metadata contract lost", 31)
        return

    print("ROAD_GENERATOR_OSM_ADAPTER_GREEN")
    print("osm_id=%d" % int(road.get("osm_id", -1)))
    print("road_name=" + str(road.get("name", "")))
    print("road_class=" + str(road.get("class", "")))
    print("source_points=%d" % points.size())
    print("source_length_m=%.6f" % source_length)
    print("roadlane_length_m=%.6f" % lane_length)
    print("agent_probe_offset_m=%.6f" % moved_offset)
    print("source_geometry_mutated=false")
    print("traffic_manager_replaced=false")
    print("canonical_runtime_authorized=false")
    quit(0)
GDSCRIPT

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE editor_import\n'
set +e
timeout 45 "$GODOT_BIN" --headless --editor --path "$PILOT_PROJECT" --audio-driver Dummy > "$EVIDENCE/editor-import.log" 2>&1
editor_rc=$?
set -e
if [[ "$editor_rc" -ne 0 && "$editor_rc" -ne 124 ]]; then
  cat "$EVIDENCE/editor-import.log"
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL editor import exited with $editor_rc" >&2
  exit 8
fi
if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|Cannot get class' "$EVIDENCE/editor-import.log"; then
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL addon produced script/import errors" >&2
  exit 9
fi

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE lane_agent\n'
"$GODOT_BIN" --headless --path "$PILOT_PROJECT" --audio-driver Dummy --script res://road_generator_osm_adapter_smoke.gd \
  | tee "$EVIDENCE/adapter.log"
grep -q 'ROAD_GENERATOR_OSM_ADAPTER_GREEN' "$EVIDENCE/adapter.log"
grep -q 'source_geometry_mutated=false' "$EVIDENCE/adapter.log"
grep -q 'traffic_manager_replaced=false' "$EVIDENCE/adapter.log"

printf 'ROAD_GENERATOR_OSM_ADAPTER_PHASE canonical_clean\n'
test ! -d "$PROJECT_ROOT/addons/road-generator"
! grep -q 'road-generator' "$PROJECT_ROOT/project.godot"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game)" ]]; then
  git -C "$REPO_ROOT" status --porcelain -- grand-bruxelles-game >&2
  echo "ROAD_GENERATOR_OSM_ADAPTER_FAIL canonical project tree changed" >&2
  exit 10
fi

cat > "$EVIDENCE/result.txt" <<EOF
ROAD_GENERATOR_OSM_ADAPTER_PILOT_GREEN
osm_id=$SOURCE_OSM_ID
source_sha256=$actual_source_sha
upstream_tag=$UPSTREAM_TAG
upstream_commit=$actual_commit
godot_version=$GODOT_VERSION
renderer=gl_compatibility
roadlane_metadata_only=true
source_geometry_mutated=false
canonical_addon_installed=false
replace_osm_urbis_geometry_authorized=false
replace_existing_traffic_manager_authorized=false
traffic_runtime_bridge_authorized=false
runtime_authorized=false
export_authorized=false
EOF
cat "$EVIDENCE/result.txt"
