extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_world_streaming_runtime.gd")
const TEST_ROOT := "user://brussels_runtime_cell_index_test/cells"
const INDEX_PATH := "user://brussels_runtime_cell_index_test/runtime_cell_index.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_RUNTIME_CELL_INDEX_FAIL: %s" % message)
    quit(1)

func _write_json(path: String, payload: Dictionary) -> bool:
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(payload))
    file.close()
    return true

func _write_cell(cell_id: String, easting: float) -> bool:
    var base := TEST_ROOT.path_join(cell_id)
    var manifest := {
        "format": "grand-bruxelles-urbis-built-cell-v1",
        "cell_id": cell_id,
        "crs": "EPSG:31370",
        "bbox": [easting, 200000.0, easting + 500.0, 200500.0],
        "runtime": {
            "geometry_file": "runtime/cell.game.json",
            "geometry_format": "grand-bruxelles-urbis-cell-runtime-v1",
            "network_file": "runtime/network.game.json",
            "network_format": "grand-bruxelles-urbis-network-cell-runtime-v2"
        }
    }
    var runtime_cell := {
        "format": "grand-bruxelles-urbis-cell-runtime-v1",
        "cell_id": cell_id,
        "coordinate_system": {
            "lambert_origin_e": easting,
            "lambert_origin_n": 200000.0,
            "world_anchor_x": 0.0,
            "world_anchor_z": 0.0,
            "coordinates_are_current_game_world": true
        }
    }
    var network := {"format": "grand-bruxelles-urbis-network-cell-runtime-v2", "cell_id": cell_id}
    return _write_json(base.path_join("manifest.json"), manifest) and _write_json(base.path_join("runtime/cell.game.json"), runtime_cell) and _write_json(base.path_join("runtime/network.game.json"), network)

func _run() -> void:
    var indexed_a := "bxl-e100000-n200000-s500"
    var indexed_b := "bxl-e100500-n200000-s500"
    var rogue_valid_but_unindexed := "bxl-e101000-n200000-s500"
    for pair in [[indexed_a, 100000.0], [indexed_b, 100500.0], [rogue_valid_but_unindexed, 101000.0]]:
        if not _write_cell(str(pair[0]), float(pair[1])):
            _fail("could not write cell fixture %s" % str(pair[0])); return
    var index := {
        "format": "grand-bruxelles-runtime-cell-index-v1",
        "source_root": TEST_ROOT,
        "runtime_mount_authorized_by_index": false,
        "jouable_authorized_by_index": false,
        "cells": [
            {"cell_id": indexed_b},
            {"cell_id": indexed_a}
        ]
    }
    if not _write_json(INDEX_PATH, index):
        _fail("could not write deterministic index"); return

    var runtime := RUNTIME_SCRIPT.new()
    var descriptors: Array[Dictionary] = runtime.discover_runtime_cell_descriptors(TEST_ROOT, INDEX_PATH)
    if descriptors.size() != 2:
        _fail("index must expose exactly two cells, got %d" % descriptors.size()); return
    if str(descriptors[0].get("cell_id", "")) != indexed_a or str(descriptors[1].get("cell_id", "")) != indexed_b:
        _fail("index lookup must be deterministic and sorted"); return
    for descriptor: Dictionary in descriptors:
        if str(descriptor.get("cell_id", "")) == rogue_valid_but_unindexed:
            _fail("valid but unindexed cell leaked into runtime discovery"); return
    print("BRUSSELS_RUNTIME_CELL_INDEX_OK: indexed=2 rogue_unindexed_rejected=true mount_authorized_by_index=false jouable_authorized_by_index=false")
    quit(0)
