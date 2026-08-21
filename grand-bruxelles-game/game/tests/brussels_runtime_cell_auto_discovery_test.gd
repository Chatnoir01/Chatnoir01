extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_world_streaming_runtime.gd")
const TEST_ROOT := "user://brussels_runtime_cell_auto_discovery_test"
const INDEX_PATH := "user://brussels_runtime_cell_auto_discovery_test/runtime_cell_index.json"
const GENERIC_SOURCE_PLAN_SCRIPT := "res://game/scripts/brussels_source_plan_streamed_cell.gd"
const IXELLES_NORTH_DTM_SCRIPT := "res://game/zones/ixelles/ixelles_streamed_north_dtm_cell.gd"
const IXELLES_EAST_DTM_SCRIPT := "res://game/zones/ixelles/ixelles_streamed_east_dtm_cell.gd"

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
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(payload))
    file.close()
    return true

func _manifest(cell_id: String, easting: float, northing: float) -> Dictionary:
    return {"format":"grand-bruxelles-urbis-built-cell-v1","cell_id":cell_id,"crs":"EPSG:31370","bbox":[easting,northing,easting+500.0,northing+500.0],"runtime":{"geometry_file":"runtime/cell.game.json","geometry_format":"grand-bruxelles-urbis-cell-runtime-v1","network_file":"runtime/network.game.json","network_format":"grand-bruxelles-urbis-network-cell-runtime-v2"}}

func _candidate_manifest(cell_id: String, easting: float, northing: float, sealed: bool) -> Dictionary:
    var result := _manifest(cell_id, easting, northing)
    result["authorization"] = {"candidate_only":true,"runtime_mount_authorized":false}
    if sealed:
        result["format"] = "grand-bruxelles-urbis-built-cell-candidate-v1"
        result["promotion"] = {"production_discovery_eligible":false}
    return result

func _runtime_cell(cell_id: String, easting: float, northing: float) -> Dictionary:
    return {"format":"grand-bruxelles-urbis-cell-runtime-v1","cell_id":cell_id,"coordinate_system":{"lambert_origin_e":easting,"lambert_origin_n":northing,"world_anchor_x":0.0,"world_anchor_z":0.0,"coordinates_are_current_game_world":true}}

func _runtime_network(cell_id: String) -> Dictionary:
    return {"format":"grand-bruxelles-urbis-network-cell-runtime-v2","cell_id":cell_id}

func _write_complete(cell_id: String, easting: float, northing: float, manifest: Dictionary) -> bool:
    var base := TEST_ROOT.path_join(cell_id)
    return _write_json(base.path_join("manifest.json"), manifest) and _write_json(base.path_join("runtime/cell.game.json"), _runtime_cell(cell_id,easting,northing)) and _write_json(base.path_join("runtime/network.game.json"), _runtime_network(cell_id))

func _run() -> void:
    var first_id := "bxl-e100000-n200000-s500"
    var second_id := "bxl-e100500-n200000-s500"
    var incomplete_id := "bxl-e101000-n200000-s500"
    var mismatched_id := "bxl-e101500-n200000-s500"
    var sealed_candidate_id := "bxl-e102000-n200000-s500"
    var unsealed_candidate_id := "bxl-e102500-n200000-s500"
    var shipped_north_id := "bxl-e149000-n169500-s500"
    var shipped_east_id := "bxl-e149500-n169000-s500"
    if not _expect(_write_complete(second_id,100500.0,200000.0,_manifest(second_id,100500.0,200000.0)),"write second"): return
    if not _expect(_write_complete(first_id,100000.0,200000.0,_manifest(first_id,100000.0,200000.0)),"write first"): return
    if not _expect(_write_complete(shipped_north_id,149000.0,169500.0,_manifest(shipped_north_id,149000.0,169500.0)),"write north shipped"): return
    if not _expect(_write_complete(shipped_east_id,149500.0,169000.0,_manifest(shipped_east_id,149500.0,169000.0)),"write east shipped"): return
    if not _expect(_write_json(TEST_ROOT.path_join(incomplete_id).path_join("manifest.json"),_manifest(incomplete_id,101000.0,200000.0)),"write incomplete"): return
    var mismatch_base := TEST_ROOT.path_join(mismatched_id)
    if not _expect(_write_json(mismatch_base.path_join("manifest.json"),_manifest(mismatched_id,101500.0,200000.0)),"write mismatch manifest"): return
    if not _expect(_write_json(mismatch_base.path_join("runtime/cell.game.json"),_runtime_cell(mismatched_id,101500.0,200000.0)),"write mismatch cell"): return
    if not _expect(_write_json(mismatch_base.path_join("runtime/network.game.json"),_runtime_network("bxl-e999999-n999999-s500")),"write mismatch network"): return
    if not _expect(_write_complete(sealed_candidate_id,102000.0,200000.0,_candidate_manifest(sealed_candidate_id,102000.0,200000.0,true)),"write sealed candidate"): return
    if not _expect(_write_complete(unsealed_candidate_id,102500.0,200000.0,_candidate_manifest(unsealed_candidate_id,102500.0,200000.0,false)),"write unsealed candidate"): return
    var index_cells: Array = []
    for cell_id in [second_id,first_id,incomplete_id,mismatched_id,sealed_candidate_id,unsealed_candidate_id,shipped_north_id,shipped_east_id]:
        index_cells.append({"cell_id":cell_id})
    if not _expect(_write_json(INDEX_PATH,{"format":"grand-bruxelles-runtime-cell-index-v1","source_root":TEST_ROOT,"runtime_mount_authorized_by_index":false,"jouable_authorized_by_index":false,"cells":index_cells}),"write index"): return
    var runtime := RUNTIME_SCRIPT.new()
    var descriptors: Array[Dictionary] = runtime.discover_runtime_cell_descriptors(TEST_ROOT, INDEX_PATH)
    if not _expect(descriptors.size()==4,"only four production-safe indexed fixtures expected, got %d"%descriptors.size()): return
    var ids := PackedStringArray()
    var by_id := {}
    for descriptor: Dictionary in descriptors:
        var cell_id := str(descriptor.get("cell_id","")); ids.append(cell_id); by_id[cell_id]=descriptor
    var sorted := ids.duplicate(); sorted.sort()
    if not _expect(ids==sorted,"indexed descriptors must be sorted"): return
    if not _expect(str((by_id[first_id] as Dictionary).get("script_path",""))==GENERIC_SOURCE_PLAN_SCRIPT,"generic renderer first"): return
    if not _expect(str((by_id[second_id] as Dictionary).get("script_path",""))==GENERIC_SOURCE_PLAN_SCRIPT,"generic renderer second"): return
    if not _expect(str((by_id[shipped_north_id] as Dictionary).get("script_path",""))==IXELLES_NORTH_DTM_SCRIPT,"north specialized renderer preserved"): return
    if not _expect(str((by_id[shipped_east_id] as Dictionary).get("script_path",""))==IXELLES_EAST_DTM_SCRIPT,"east specialized renderer preserved"): return
    if not _expect(runtime.is_destination_collision_authorized(shipped_east_id),"east DTM collision authorization from #1044 was lost"): return
    print("BRUSSELS_RUNTIME_CELL_AUTO_DISCOVERY_OK: deterministic index drives discovery; invalid and candidate bundles fail closed; north/east specialized DTM renderers stay compatible")
    quit(0)
