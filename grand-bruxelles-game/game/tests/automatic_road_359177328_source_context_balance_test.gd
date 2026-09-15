extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const LEMONNIER_ID := 359177328
const MAX_VISUAL_PROBE_M := 250.0
const EXPECTED_BUILDING_SELECTION_RADIUS_M := 130.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_BALANCE_FAIL: %s" % message)
    quit(1)

func _classify_source_context(left_hits: int, right_hits: int, coverage_clamped: bool) -> Dictionary:
    var bilateral := left_hits > 0 and right_hits > 0
    var classification := "bilateral_source_context_present"
    if coverage_clamped and bilateral:
        classification = "bilateral_source_context_present_within_covered_radius"
    elif coverage_clamped and not bilateral:
        classification = "source_coverage_insufficient_for_visual_void_claim"
    elif left_hits == 0 and right_hits > 0:
        classification = "left_side_source_void_confirmed"
    elif right_hits == 0 and left_hits > 0:
        classification = "right_side_source_void_confirmed"
    elif left_hits == 0 and right_hits == 0:
        classification = "bilateral_source_void_confirmed"
    return {"classification": classification}

func _verify_classification_truth_table() -> bool:
    var cases: Array[Dictionary] = [
        {"left": 2, "right": 1, "clamped": true, "expected": "bilateral_source_context_present_within_covered_radius"},
        {"left": 0, "right": 2, "clamped": true, "expected": "source_coverage_insufficient_for_visual_void_claim"},
        {"left": 2, "right": 0, "clamped": true, "expected": "source_coverage_insufficient_for_visual_void_claim"},
        {"left": 0, "right": 0, "clamped": true, "expected": "source_coverage_insufficient_for_visual_void_claim"},
        {"left": 0, "right": 2, "clamped": false, "expected": "left_side_source_void_confirmed"},
        {"left": 2, "right": 0, "clamped": false, "expected": "right_side_source_void_confirmed"},
        {"left": 0, "right": 0, "clamped": false, "expected": "bilateral_source_void_confirmed"},
        {"left": 1, "right": 1, "clamped": false, "expected": "bilateral_source_context_present"},
    ]
    for case in cases:
        var observed := String(_classify_source_context(case.left, case.right, case.clamped).classification)
        if observed != case.expected:
            _fail("classification truth-table regression")
            return false
    print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_CLASSIFICATION_TABLE_GREEN: cases=8 fail_closed_clamped_zero_hit=true")
    return true

func _run() -> void:
    if not _verify_classification_truth_table(): return
    var scene := MAIN_SCENE.instantiate()
    var viewport := SubViewport.new()
    viewport.own_world_3d = true
    root.add_child(viewport)
    viewport.add_child(scene)
    for _frame in range(12): await process_frame
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null: _fail("production Player missing"); return
    var resolver := RESOLVER_SCRIPT.new(); viewport.add_child(resolver)
    if not resolver.apply_to_player(player, LEMONNIER_ID): _fail("road did not resolve"); return
    var bundle: Dictionary = resolver._source_bundle_by_id(LEMONNIER_ID)
    var document: Dictionary = bundle.get("document", {})
    var radius := float(document.get("corridor", {}).get("selection_radius_m", {}).get("buildings", 0.0))
    if absf(radius - EXPECTED_BUILDING_SELECTION_RADIUS_M) > 0.001: _fail("building selection radius drifted"); return
    var coverage_clamped := radius < MAX_VISUAL_PROBE_M
    var polygons: Array[PackedVector2Array] = resolver._source_building_polygons(document)
    if polygons.is_empty(): _fail("source document contains no building polygons"); return
    var classification := String(_classify_source_context(0, polygons.size(), coverage_clamped).classification)
    print("AUTOMATIC_ROAD_359177328_SOURCE_CONTEXT_DIAGNOSTIC_GREEN: classification=%s coverage_clamped=%s human_visual_reject_still_binding=true destination_advertisable=false visual_acceptance=false jouable=false" % [classification, str(coverage_clamped).to_lower()])
    quit(0)
