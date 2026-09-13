extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const TARGET_OSM_ID := 288509378
const SHORT_OSM_ID := 977936292
const CONTROL_OSM_ID := 35903015
const MAX_LOOKAHEAD_M := 22.0
const MIN_AXIS_ALIGNMENT := 0.90
const RECEIPT_PATH := "res://artifacts/qa/midi_fonsny_same_way_arc_runtime.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_SAME_WAY_ARC_RUNTIME_FAIL: %s" % message)
    quit(1)


func _polyline_length(points: PackedVector2Array) -> float:
    var total := 0.0
    for index: int in range(points.size() - 1):
        total += points[index].distance_to(points[index + 1])
    return total


func _best_segment(points: PackedVector2Array) -> Dictionary:
    var best_index := -1
    var best_length := -1.0
    for index: int in range(points.size() - 1):
        var length := points[index].distance_to(points[index + 1])
        if length > best_length:
            best_length = length
            best_index = index
    return {"index": best_index, "length_m": best_length}


func _point_on_requested_way(resolver: Object, points: PackedVector2Array, point: Vector2) -> bool:
    for index: int in range(points.size() - 1):
        if float(resolver.call("_point_segment_distance", point, points[index], points[index + 1])) <= 0.001:
            return true
    return false


func _write_receipt(receipt: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()
    return true


func _run() -> void:
    var resolver: Object = RESOLVER_SCRIPT.new()
    var target_bundle: Dictionary = resolver.call("_source_bundle_by_id", TARGET_OSM_ID)
    var short_bundle: Dictionary = resolver.call("_source_bundle_by_id", SHORT_OSM_ID)
    var control_bundle: Dictionary = resolver.call("_source_bundle_by_id", CONTROL_OSM_ID)
    if target_bundle.is_empty() or short_bundle.is_empty() or control_bundle.is_empty():
        _fail("source-backed runtime-index bundle missing")
        return

    var target_document: Dictionary = target_bundle["document"]
    var target_road: Dictionary = target_bundle["road"]
    var target_points: PackedVector2Array = resolver.call("_road_points", target_road) as PackedVector2Array
    var target_best := _best_segment(target_points)
    var target_total := _polyline_length(target_points)
    var target_half_best := float(target_best["length_m"]) * 0.5
    var target_first_offset := float(resolver.call("_display_road_width", target_road)) * 0.5 + 1.10
    var target_required := target_first_offset * 2.10
    if target_half_best >= target_required:
        _fail("baseline single-segment blocker no longer reproduces")
        return
    if target_total <= target_required:
        _fail("requested way lacks enough same-way source arc")
        return

    var target_view: Dictionary = resolver.call("_safe_viewpoint", target_document, target_road)
    if target_view.is_empty():
        _fail("same-way multi-segment resolver still rejects road-288509378")
        return
    if not bool(target_view.get("same_requested_osm_way_only", false)):
        _fail("requested OSM identity continuity was not sealed")
        return
    if int(target_view.get("source_arc_segment_hops", 0)) < 1:
        _fail("road-288509378 did not exercise the multi-segment same-way path")
        return
    var target_lookahead := float(target_view.get("axis_lookahead_m", 0.0))
    if target_lookahead + 0.000001 < float(target_view["offset_m"]) * 2.10 or target_lookahead > MAX_LOOKAHEAD_M + 0.000001:
        _fail("lookahead violates frozen production bounds")
        return
    if float(target_view.get("axis_alignment", 0.0)) < MIN_AXIS_ALIGNMENT:
        _fail("axis alignment dropped below frozen contract")
        return
    var target_xz: Vector2 = target_view["target"]
    if not _point_on_requested_way(resolver, target_points, target_xz):
        _fail("look target left the exact requested OSM way geometry")
        return

    var short_document: Dictionary = short_bundle["document"]
    var short_road: Dictionary = short_bundle["road"]
    var short_points: PackedVector2Array = resolver.call("_road_points", short_road) as PackedVector2Array
    var short_total := _polyline_length(short_points)
    var short_first_offset := float(resolver.call("_display_road_width", short_road)) * 0.5 + 1.10
    var short_required := short_first_offset * 2.10
    if short_total >= short_required:
        _fail("short-way source precondition changed")
        return
    if not (resolver.call("_safe_viewpoint", short_document, short_road) as Dictionary).is_empty():
        _fail("road-977936292 crossed a way boundary instead of failing closed")
        return

    var control_document: Dictionary = control_bundle["document"]
    var control_road: Dictionary = control_bundle["road"]
    var control_view: Dictionary = resolver.call("_safe_viewpoint", control_document, control_road)
    if control_view.is_empty():
        _fail("control road-35903015 regressed")
        return
    if int(control_view.get("source_arc_segment_hops", -1)) != 0:
        _fail("control road unexpectedly left its proven single segment")
        return
    if absf(float(control_view.get("axis_lookahead_m", 0.0)) - MAX_LOOKAHEAD_M) > 0.000001:
        _fail("control road lookahead changed")
        return

    var receipt := {
        "schema": "grand-bruxelles-midi-fonsny-same-way-arc-runtime-v1",
        "target_osm_id": TARGET_OSM_ID,
        "target_source_path": str(target_bundle.get("source_path", "")),
        "target_source_sha256": str(target_bundle.get("source_sha256", "")),
        "target_best_segment_m": float(target_best["length_m"]),
        "target_half_best_segment_m": target_half_best,
        "target_same_way_polyline_m": target_total,
        "target_required_first_offset_lookahead_m": target_required,
        "target_axis_lookahead_m": target_lookahead,
        "target_axis_alignment": float(target_view.get("axis_alignment", 0.0)),
        "target_source_arc_segment_hops": int(target_view.get("source_arc_segment_hops", 0)),
        "target_same_requested_osm_way_only": true,
        "short_osm_id": SHORT_OSM_ID,
        "short_same_way_polyline_m": short_total,
        "short_required_first_offset_lookahead_m": short_required,
        "short_remains_fail_closed": true,
        "control_osm_id": CONTROL_OSM_ID,
        "control_axis_lookahead_m": float(control_view.get("axis_lookahead_m", 0.0)),
        "control_source_arc_segment_hops": int(control_view.get("source_arc_segment_hops", -1)),
        "cross_way_traversal_used": false,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_contract_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist receipt")
        return
    resolver.free()
    print("MIDI_FONSNY_SAME_WAY_ARC_RUNTIME_OK: requested=288509378 hops=%d lookahead=%.6f alignment=%.6f short_977936292_fail_closed=true control_35903015_single_segment=true" % [int(target_view.get("source_arc_segment_hops", 0)), target_lookahead, float(target_view.get("axis_alignment", 0.0))])
    quit(0)