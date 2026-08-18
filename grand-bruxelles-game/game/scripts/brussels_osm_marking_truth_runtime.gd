extends Node

const POLICY_FAMILY := "brussels_osm_marking_truth_v1"
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"
const LEGACY_MARKING_COLOR := Color(0.88, 0.87, 0.80, 1.0)

var _markings: Array[CSGBox3D] = []
var _legacy_visibility: Dictionary = {}
var _enhanced_enabled := true
var _ready_complete := false
var _failed := false
var _geometry_snapshot: Dictionary = {}

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _is_legacy_inferred_marking(node: Node) -> bool:
    if not node is CSGBox3D:
        return false
    var dash := node as CSGBox3D
    if not is_equal_approx(dash.size.x, 0.12) or not is_equal_approx(dash.size.y, 0.025):
        return false
    if dash.size.z <= 0.0 or dash.size.z > 3.5001:
        return false
    if not dash.material is StandardMaterial3D:
        return false
    var material := dash.material as StandardMaterial3D
    return material.albedo_color.is_equal_approx(LEGACY_MARKING_COLOR)

func _apply_when_ready() -> void:
    var roads_root: Node3D = null
    for _attempt: int in range(180):
        await get_tree().process_frame
        var candidate := get_tree().root.find_child("GeneratedRoads", true, false)
        if candidate is Node3D:
            roads_root = candidate as Node3D
            break
    if roads_root == null:
        push_error("Brussels OSM marking truth runtime: GeneratedRoads missing")
        _failed = true
        _ready_complete = true
        return

    for child: Node in roads_root.get_children():
        if not _is_legacy_inferred_marking(child):
            continue
        var dash := child as CSGBox3D
        var id := dash.get_instance_id()
        _markings.append(dash)
        _legacy_visibility[id] = dash.visible
        _geometry_snapshot[id] = {
            "transform": dash.transform,
            "size": dash.size,
        }
        dash.set_meta("marking_truth_family", POLICY_FAMILY)
        dash.set_meta("marking_owner", "osm_city_builder_legacy_class_inference")
        dash.set_meta("source", SOURCE)
        dash.set_meta("license", LICENSE)
        dash.set_meta("source_backed_lane_marking", false)
        dash.set_meta("road_class_is_marking_evidence", false)
        dash.set_meta("geometry_changed_by_marking_truth_runtime", false)

    if _markings.is_empty():
        push_error("Brussels OSM marking truth runtime: no legacy inferred lane markings found")
        _failed = true
        _ready_complete = true
        return

    _set_state(_enhanced_enabled)
    _ready_complete = true
    print("BRUSSELS_OSM_MARKING_TRUTH_READY: unsupported_marks=%d family=%s source=OSM license=ODbL-1.0 candidate=hidden geometry_changed=false" % [_markings.size(), POLICY_FAMILY])

func _set_state(enabled: bool) -> void:
    for dash: CSGBox3D in _markings:
        if not is_instance_valid(dash):
            continue
        dash.visible = false if enabled else bool(_legacy_visibility.get(dash.get_instance_id(), true))

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if _ready_complete and not _failed:
        _set_state(enabled)

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func affected_marking_count() -> int:
    return _markings.size() if _ready_complete and not _failed else 0

func geometry_unchanged() -> bool:
    for dash: CSGBox3D in _markings:
        if not is_instance_valid(dash):
            return false
        var snapshot: Dictionary = _geometry_snapshot.get(dash.get_instance_id(), {})
        if snapshot.is_empty():
            return false
        if not dash.transform.is_equal_approx(snapshot.get("transform", Transform3D.IDENTITY)):
            return false
        if not dash.size.is_equal_approx(snapshot.get("size", Vector3.ZERO)):
            return false
    return true
