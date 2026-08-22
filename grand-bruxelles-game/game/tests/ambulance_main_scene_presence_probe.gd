extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const EXPECTED_SOURCE_OSM_ID := 108931599
const EXPECTED_EVIDENCE_SOURCE := "midi_ambulance_parking_evidence:midi-parking-angleterre-108931599"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AMBULANCE_MAIN_SCENE_PRESENCE_FAIL %s" % message)
    quit(1)

func _run() -> void:
    var info := Engine.get_version_info()
    var version := "%d.%d.%d" % [int(info.major), int(info.minor), int(info.patch)]
    if version != "4.7.1":
        _fail("engine=%s" % version)
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(12):
        await process_frame

    var manager := main.get_node_or_null("TrafficManager")
    if manager == null or not manager.has_method("get_ambulance_count"):
        _fail("traffic_manager_or_contract_missing")
        return
    if not manager.has_method("get_ambulance_parking_evidence_road_count"):
        _fail("parking_evidence_join_contract_missing")
        return
    var joined_road_count := int(manager.call("get_ambulance_parking_evidence_road_count"))
    if joined_road_count != 1:
        _fail("parking_evidence_joined_roads=%d expected=1" % joined_road_count)
        return
    var ambulance_count := int(manager.call("get_ambulance_count"))
    if ambulance_count != 2:
        _fail("ambulance_count=%d expected=2" % ambulance_count)
        return

    var ambulances := get_nodes_in_group("ambulance")
    if ambulances.size() != 2:
        _fail("ambulance_group_count=%d expected=2" % ambulances.size())
        return
    var ids: Dictionary = {}
    for raw_node: Node in ambulances:
        if not raw_node is Node3D:
            _fail("ambulance_not_node3d=%s" % raw_node.name)
            return
        var node := raw_node as Node3D
        var candidate_id := int(node.get_meta("parking_candidate_id", -1))
        var source_osm_id := int(node.get_meta("source_osm_id", 0))
        if candidate_id < 0 or source_osm_id <= 0:
            _fail("ambulance_not_source_backed=%s candidate=%d osm=%d" % [node.name, candidate_id, source_osm_id])
            return
        if source_osm_id != EXPECTED_SOURCE_OSM_ID:
            _fail("ambulance_source_osm_drifted=%s osm=%d expected=%d" % [node.name, source_osm_id, EXPECTED_SOURCE_OSM_ID])
            return
        if ids.has(candidate_id):
            _fail("parking_candidate_reused=%d" % candidate_id)
            return
        ids[candidate_id] = true
        if not bool(node.get_meta("parking_evidence_runtime_approved", false)):
            _fail("parking_evidence_not_approved=%s" % node.name)
            return
        var evidence_source := str(node.get_meta("parking_evidence_source", ""))
        if evidence_source != EXPECTED_EVIDENCE_SOURCE:
            _fail("parking_evidence_source_drifted=%s source=%s" % [node.name, evidence_source])
            return

    print("AMBULANCE_MAIN_SCENE_PRESENCE_OK ambulances=2 source_backed=2 unique_parking=2 osm=%d evidence_roads=1 engine=%s" % [EXPECTED_SOURCE_OSM_ID, version])
    quit(0)
