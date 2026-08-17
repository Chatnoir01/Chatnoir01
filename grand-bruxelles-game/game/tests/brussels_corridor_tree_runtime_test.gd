extends SceneTree

const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_PATH := "res://game/scripts/brussels_corridor_tree_runtime.gd"
const ASSET_PATH := "res://game/scripts/brussels_street_tree_asset.gd"
const EXPECTED_TREE_COUNT := 273
const POSITION_EPSILON_M := 0.0005

func _init() -> void:
    var failures: Array[String] = []
    if not FileAccess.file_exists(ASSET_PATH):
        failures.append("reusable Brussels street-tree asset missing")
    if not FileAccess.file_exists(RUNTIME_PATH):
        failures.append("red-first witness: corridor tree runtime missing")
    var data := _load_json(DATA_PATH)
    if data.is_empty():
        failures.append("vertical-slice OSM payload missing")
    elif str(data.get("source", "")) != "OpenStreetMap contributors via Overpass API" or str(data.get("license", "")) != "ODbL-1.0":
        failures.append("OSM provenance contract changed")
    var source_trees: Array[Dictionary] = []
    for raw: Variant in data.get("environment_points", []):
        if raw is Dictionary and str((raw as Dictionary).get("kind", "")) == "tree":
            source_trees.append(raw as Dictionary)
    if source_trees.size() != EXPECTED_TREE_COUNT:
        failures.append("expected %d source trees, got %d" % [EXPECTED_TREE_COUNT, source_trees.size()])
    if failures.is_empty():
        var runtime_script: Script = load(RUNTIME_PATH) as Script
        if runtime_script == null:
            failures.append("corridor tree runtime failed to load")
        else:
            var scene := Node3D.new()
            scene.name = "TreeContractScene"
            root.add_child(scene)
            var runtime: Node = runtime_script.new() as Node
            if runtime == null:
                failures.append("corridor tree runtime failed to instantiate")
            else:
                root.add_child(runtime)
                runtime.call("bind_scene", scene)
                if bool(runtime.call("failed")):
                    failures.append("runtime reported failure")
                if int(runtime.call("tree_count")) != EXPECTED_TREE_COUNT:
                    failures.append("runtime tree count mismatch")
                if int(runtime.call("batch_count")) > 3:
                    failures.append("tree visuals exceed 3 shared MultiMesh batches")
                if int(runtime.call("collision_count")) != EXPECTED_TREE_COUNT:
                    failures.append("tree collision count mismatch")
                var runtime_positions: Array = runtime.call("source_positions") as Array
                if runtime_positions.size() != source_trees.size():
                    failures.append("runtime source-position count mismatch")
                else:
                    for index: int in range(source_trees.size()):
                        var source_pos := (source_trees[index].get("position", []) as Array)
                        var runtime_pos: Vector3 = runtime_positions[index] as Vector3
                        if source_pos.size() != 2:
                            failures.append("malformed source tree position")
                            break
                        if abs(runtime_pos.x - float(source_pos[0])) > POSITION_EPSILON_M or abs(runtime_pos.z - float(source_pos[1])) > POSITION_EPSILON_M:
                            failures.append("runtime moved source tree position at index %d" % index)
                            break
                if bool(runtime.call("claims_species")) or bool(runtime.call("claims_measured_dimensions")):
                    failures.append("runtime made unsupported species/dimension claim")
                runtime.queue_free()
            scene.queue_free()
    if failures.is_empty():
        print("BRUSSELS_CORRIDOR_TREES_OK: trees=%d source=OSM license=ODbL-1.0 batches<=3" % EXPECTED_TREE_COUNT)
        quit(0)
    for failure: String in failures:
        push_error("BRUSSELS_CORRIDOR_TREES_FAIL: %s" % failure)
    quit(1)

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}
