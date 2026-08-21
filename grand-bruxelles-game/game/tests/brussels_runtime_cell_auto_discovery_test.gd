extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_world_streaming_runtime.gd")
const TEST_ROOT := "user://brussels_runtime_cell_auto_discovery_test"
const GENERIC_SOURCE_PLAN_SCRIPT := "res://game/scripts/brussels_source_plan_streamed_cell.gd"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BRUSSELS_RUNTIME_CELL_AUTO_DISCOVERY_FAIL: %s" % message)
    quit(1)


func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true


func _write_json(path: String, payload: Dictionary) -> bool:
    var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
    if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(payload))
    file.close()
    return true


func _manifest(cell_id: String, easting: float, northing: float) -> Dictionary:
    return {
        "format": "grand-bruxelles-urbis-built-cell-v1",
        "cell_id": cell_id,
        "crs": "EPSG:31370",
        "bbox": [easting, northing, easting + 500.0, northing + 500.0],
        "runtime": {
            "geometry_file": "runtime/cell.game.json",
            "geometry_format": "grand-bruxelles-urbis-cell-runtime-v1",
            "network_file": "runtime/network.game.json",
            "network_format": "grand-bruxelles-urbis-network-cell-runtime-v2",
        },
    }


func _sealed_candidate_manifest(cell_id: String, easting: float, northing: float) -> Dictionary:
    var result := _manifest(cell_id, easting, northing)
    result["format"] = "grand-bruxelles-urbis-built-cell-candidate-v1"
    result["authorization"] = {
        "candidate_only": true,
        "runtime_mount_authorized": false,
    }
    result["promotion"] = {
        "state": "qa_candidate_only",
        "production_discovery_eligible": false,
        "requires_explicit_validated_promotion": true,
    }
    return result


func _unsealed_candidate_manifest(cell_id: String, easting: float, northing: float) -> Dictionary:
    var result := _manifest(cell_id, easting, northing)
    result["authorization"] = {
        "candidate_only": true,
        "runtime_mount_authorized": false,
        "collision_authorized": false,
        "terrain_runtime_authorized": false,
        "jouable_promotion_authorized": false,
    }
    return result


func _runtime_cell(cell_id: String, easting: float, northing: float) -> Dictionary:
    return {
        "format": "grand-bruxelles-urbis-cell-runtime-v1",
        "cell_id": cell_id,
        "coordinate_system": {
            "lambert_origin_e": easting,
            "lambert_origin_n": northing,
            "world_anchor_x": 0.0,
            "world_anchor_z": 0.0,
            "coordinates_are_current_game_world": true,
        },
    }


func _runtime_network(cell_id: String) -> Dictionary:
    return {
        "format": "grand-bruxelles-urbis-network-cell-runtime-v2",
        "cell_id": cell_id,
    }


func _write_complete_cell_with_manifest(cell_id: String, easting: float, northing: float, manifest: Dictionary) -> bool:
    var base := TEST_ROOT.path_join(cell_id)
    return (
        _write_json(base.path_join("manifest.json"), manifest)
        and _write_json(base.path_join("runtime/cell.game.json"), _runtime_cell(cell_id, easting, northing))
        and _write_json(base.path_join("runtime/network.game.json"), _runtime_network(cell_id))
    )


func _write_complete_cell(cell_id: String, easting: float, northing: float) -> bool:
    return _write_complete_cell_with_manifest(cell_id, easting, northing, _manifest(cell_id, easting, northing))


func _run() -> void:
    var first_id := "bxl-e100000-n200000-s500"
    var second_id := "bxl-e100500-n200000-s500"
    var incomplete_id := "bxl-e101000-n200000-s500"
    var mismatched_id := "bxl-e101500-n200000-s500"
    var sealed_candidate_id := "bxl-e102000-n200000-s500"
    var unsealed_candidate_id := "bxl-e102500-n200000-s500"

    if not _expect(_write_complete_cell(second_id, 100500.0, 200000.0), "could not write second complete cell fixture"):
        return
    if not _expect(_write_complete_cell(first_id, 100000.0, 200000.0), "could not write first complete cell fixture"):
        return

    var incomplete_base := TEST_ROOT.path_join(incomplete_id)
    if not _expect(_write_json(incomplete_base.path_join("manifest.json"), _manifest(incomplete_id, 101000.0, 200000.0)), "could not write incomplete cell fixture"):
        return

    var mismatched_base := TEST_ROOT.path_join(mismatched_id)
    if not _expect(_write_json(mismatched_base.path_join("manifest.json"), _manifest(mismatched_id, 101500.0, 200000.0)), "could not write mismatched manifest fixture"):
        return
    if not _expect(_write_json(mismatched_base.path_join("runtime/cell.game.json"), _runtime_cell(mismatched_id, 101500.0, 200000.0)), "could not write mismatched runtime cell fixture"):
        return
    if not _expect(_write_json(mismatched_base.path_join("runtime/network.game.json"), _runtime_network("bxl-e999999-n999999-s500")), "could not write mismatched network fixture"):
        return

    if not _expect(
        _write_complete_cell_with_manifest(
            sealed_candidate_id,
            102000.0,
            200000.0,
            _sealed_candidate_manifest(sealed_candidate_id, 102000.0, 200000.0)
        ),
        "could not write sealed candidate fixture"
    ):
        return

    if not _expect(
        _write_complete_cell_with_manifest(
            unsealed_candidate_id,
            102500.0,
            200000.0,
            _unsealed_candidate_manifest(unsealed_candidate_id, 102500.0, 200000.0)
        ),
        "could not write unsealed candidate fixture"
    ):
        return

    var runtime := RUNTIME_SCRIPT.new()
    if not _expect(runtime.has_method("discover_runtime_cell_descriptors"), "production runtime still has no automatic pregenerated-cell discovery API"):
        return
    var descriptors: Array[Dictionary] = runtime.discover_runtime_cell_descriptors(TEST_ROOT)

    if not _expect(descriptors.size() == 2, "automatic discovery should accept only the two production-safe fixtures, got %d" % descriptors.size()):
        return
    if not _expect(str(descriptors[0].get("cell_id", "")) == first_id and str(descriptors[1].get("cell_id", "")) == second_id, "automatic discovery should be deterministic and sorted by cell id"):
        return

    for descriptor: Dictionary in descriptors:
        if not _expect(str(descriptor.get("script_path", "")) == GENERIC_SOURCE_PLAN_SCRIPT, "newly discovered regional cells must use the generic source-plan renderer"):
            return
        if not _expect(FileAccess.file_exists(str(descriptor.get("manifest_path", ""))), "descriptor manifest path is not resolvable"):
            return
        if not _expect(FileAccess.file_exists(str(descriptor.get("runtime_cell_path", ""))), "descriptor runtime geometry path is not resolvable"):
            return
        if not _expect(FileAccess.file_exists(str(descriptor.get("runtime_network_path", ""))), "descriptor runtime network path is not resolvable"):
            return

    print("BRUSSELS_RUNTIME_CELL_AUTO_DISCOVERY_OK: complete production cells are discovered automatically; incomplete, identity-mismatched, sealed candidate and unsealed unauthorized candidate cells fail closed")
    quit(0)
