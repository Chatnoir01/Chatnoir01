extends SceneTree

const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const ANNEESSENS_DATA_PATH := "res://data/osm/anneessens_environment_points.game.json"
const RUNTIME_PATH := "res://game/scripts/brussels_corridor_tree_runtime.gd"
const ASSET_PATH := "res://game/scripts/brussels_street_tree_asset.gd"
const EXPECTED_SOURCE_TREE_COUNT := 273
const EXPECTED_PREOWNED_TREE_COUNT := 7
const EXPECTED_RUNTIME_TREE_COUNT := 266
const POSITION_EPSILON_M := 0.0005

func _init() -> void:
    var failures: Array[String] = []
    if not FileAccess.file_exists(ASSET_PATH): failures.append("reusable Brussels street-tree asset missing")
    if not FileAccess.file_exists(RUNTIME_PATH): failures.append("red-first witness: corridor tree runtime missing")
    var data := _load_json(DATA_PATH)
    var anneessens := _load_json(ANNEESSENS_DATA_PATH)
    if data.is_empty(): failures.append("vertical-slice OSM payload missing")
    elif str(data.get("source", "")) != "OpenStreetMap contributors via Overpass API" or str(data.get("license", "")) != "ODbL-1.0": failures.append("OSM provenance contract changed")
    var source_trees: Array[Dictionary] = _trees(data.get("environment_points", []) as Array)
    var preowned_trees: Array[Dictionary] = _trees(anneessens.get("points", []) as Array)
    if source_trees.size() != EXPECTED_SOURCE_TREE_COUNT: failures.append("expected %d source trees, got %d" % [EXPECTED_SOURCE_TREE_COUNT, source_trees.size()])
    if preowned_trees.size() != EXPECTED_PREOWNED_TREE_COUNT: failures.append("expected %d Anneessens-owned trees, got %d" % [EXPECTED_PREOWNED_TREE_COUNT, preowned_trees.size()])
    var preowned_ids := {}
    for point: Dictionary in preowned_trees: preowned_ids[int(point.get("osm_id", 0))] = true
    var expected_runtime: Array[Dictionary] = []
    for point: Dictionary in source_trees:
        if not preowned_ids.has(int(point.get("osm_id", 0))): expected_runtime.append(point)
    if expected_runtime.size() != EXPECTED_RUNTIME_TREE_COUNT: failures.append("expected %d non-duplicated runtime trees, got %d" % [EXPECTED_RUNTIME_TREE_COUNT, expected_runtime.size()])

    if failures.is_empty():
        var runtime_script: Script = load(RUNTIME_PATH) as Script
        var scene := Node3D.new()
        scene.name = "TreeContractScene"
        root.add_child(scene)
        var runtime: Node = runtime_script.new() as Node if runtime_script != null else null
        if runtime == null:
            failures.append("corridor tree runtime failed to instantiate")
        else:
            root.add_child(runtime)
            runtime.call("bind_scene", scene)
            if bool(runtime.call("failed")): failures.append("runtime reported failure")
            if int(runtime.call("tree_count")) != EXPECTED_RUNTIME_TREE_COUNT: failures.append("runtime tree count mismatch")
            if int(runtime.call("total_source_tree_count")) != EXPECTED_SOURCE_TREE_COUNT: failures.append("runtime total-source count mismatch")
            if int(runtime.call("preowned_tree_count")) != EXPECTED_PREOWNED_TREE_COUNT: failures.append("runtime preowned count mismatch")
            if int(runtime.call("batch_count")) != 3: failures.append("tree visuals must use exactly 3 shared MultiMesh batches")
            if int(runtime.call("collision_count")) != EXPECTED_RUNTIME_TREE_COUNT: failures.append("tree collision count mismatch")
            if not bool(runtime.call("source_positions_unchanged")): failures.append("runtime moved source tree positions")
            var runtime_positions: Array = runtime.call("source_positions") as Array
            if runtime_positions.size() == expected_runtime.size():
                for index: int in range(expected_runtime.size()):
                    var source_pos := expected_runtime[index].get("position", []) as Array
                    var actual: Vector3 = runtime_positions[index] as Vector3
                    if source_pos.size() != 2 or abs(actual.x - float(source_pos[0])) > POSITION_EPSILON_M or abs(actual.z - float(source_pos[1])) > POSITION_EPSILON_M:
                        failures.append("runtime/source position mismatch at %d" % index)
                        break
            else: failures.append("runtime source-position count mismatch")
            if bool(runtime.call("claims_species")) or bool(runtime.call("claims_measured_dimensions")): failures.append("runtime made unsupported species/dimension claim")
            runtime.queue_free()
        scene.queue_free()
    if failures.is_empty():
        print("BRUSSELS_CORRIDOR_TREES_OK: source=273 Anneessens_owned=7 shared_runtime=266 union=273 batches=3 source=OSM license=ODbL-1.0")
        quit(0)
    for failure: String in failures: push_error("BRUSSELS_CORRIDOR_TREES_FAIL: %s" % failure)
    quit(1)

func _trees(points: Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for raw: Variant in points:
        if raw is Dictionary and str((raw as Dictionary).get("kind", "")) == "tree": result.append(raw as Dictionary)
    return result

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}
