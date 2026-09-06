extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SPAWN := Vector2(0.0, 0.0)
const RAW_TARGET := Vector2(-10.0, 0.0)
const OPPOSITE_TARGET := Vector2(10.0, 0.0)


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_CORRIDOR_ANCHOR_HEADING_CONTRACT_FAIL: %s" % message)
    quit(1)


func _building(footprint: Array) -> Dictionary:
    return {"footprint": footprint}


func _document(anchors: Array, radius_m: float, buildings: Array) -> Dictionary:
    return {
        "corridor": {
            "selection_radius_m": {"roads": radius_m},
            "anchors": anchors,
        },
        "buildings": buildings,
    }


func _assert_unchanged(resolver: Node, document: Dictionary, label: String) -> void:
    var result: Dictionary = resolver._corridor_oriented_target(document, SPAWN, RAW_TARGET)
    var target := result.get("target", Vector2.ZERO) as Vector2
    if target != RAW_TARGET or bool(result.get("anchor_oriented", false)):
        _fail("%s must preserve the raw safe heading" % label)


func _run() -> void:
    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    var far_buildings: Array = [
        _building([[100.0, 100.0], [110.0, 100.0], [110.0, 110.0], [100.0, 110.0]])
    ]

    _assert_unchanged(
        resolver,
        _document([], 125.0, far_buildings),
        "missing source anchor",
    )

    _assert_unchanged(
        resolver,
        _document([{"name": "far", "x": 20.0, "z": 0.0}], 5.0, far_buildings),
        "source anchor outside source roads radius",
    )

    var safe_document := _document(
        [{"name": "near", "x": 20.0, "z": 0.0}],
        125.0,
        far_buildings,
    )
    var safe_result: Dictionary = resolver._corridor_oriented_target(safe_document, SPAWN, RAW_TARGET)
    var safe_target := safe_result.get("target", Vector2.ZERO) as Vector2
    if not bool(safe_result.get("anchor_oriented", false)):
        _fail("nearby source anchor with safer better-aligned opposite heading must orient")
        return
    if not safe_target.is_equal_approx(OPPOSITE_TARGET):
        _fail("safe source-anchor orientation must mirror only the heading, not move the spawn")
        return
    var safe_clearance := float(safe_result.get("source_view_corridor_clearance_m", 0.0))
    if not is_finite(safe_clearance) or safe_clearance < resolver.PLAYER_BODY_CLEARANCE_M:
        _fail("safe source-anchor orientation must retain player-body source clearance")
        return
    if not resolver._segment_clear_of_source_buildings(safe_document, SPAWN, safe_target):
        _fail("safe source-anchor orientation must remain exact-source building clear")
        return

    var blocking_buildings: Array = [
        _building([[4.0, -2.0], [6.0, -2.0], [6.0, 2.0], [4.0, 2.0]])
    ]
    _assert_unchanged(
        resolver,
        _document([{"name": "near", "x": 20.0, "z": 0.0}], 125.0, blocking_buildings),
        "opposite heading crossing a source building",
    )

    var malformed_radius := {
        "corridor": {
            "selection_radius_m": {"roads": "125"},
            "anchors": [{"name": "near", "x": 20.0, "z": 0.0}],
        },
        "buildings": far_buildings,
    }
    _assert_unchanged(resolver, malformed_radius, "non-numeric source roads radius")

    print("AUTOMATIC_ROAD_CORRIDOR_ANCHOR_HEADING_CONTRACT_GREEN: missing_anchor_unchanged=true out_of_radius_unchanged=true safe_near_anchor_oriented=true blocked_opposite_unchanged=true malformed_radius_unchanged=true spawn_unchanged=true source_thresholds_unchanged=true destination_advertisable=false visual_acceptance=false jouable_authorized=false")
    quit(0)
