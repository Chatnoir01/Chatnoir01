extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 359177328

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_CSG_POSITIVE_SHAPE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    var subtraction_only := CSGCombiner3D.new()
    subtraction_only.name = "Road_%d_SubtractionOnly" % ROAD_ID
    world.add_child(subtraction_only)
    var subtract_box := CSGBox3D.new()
    subtract_box.operation = CSGShape3D.OPERATION_SUBTRACTION
    subtraction_only.add_child(subtract_box)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("subtraction-only CSG combiner was accepted as positive rendered road geometry")
        return
    subtraction_only.queue_free()
    await process_frame

    var intersection_only := CSGCombiner3D.new()
    intersection_only.name = "Road_%d_IntersectionOnly" % ROAD_ID
    world.add_child(intersection_only)
    var intersect_box := CSGBox3D.new()
    intersect_box.operation = CSGShape3D.OPERATION_INTERSECTION
    intersection_only.add_child(intersect_box)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("intersection-only CSG combiner was accepted as positive rendered road geometry")
        return
    intersection_only.queue_free()
    await process_frame

    var nested_subtraction := CSGCombiner3D.new()
    nested_subtraction.name = "Road_%d_NestedSubtraction" % ROAD_ID
    world.add_child(nested_subtraction)
    var subtractive_wrapper := CSGCombiner3D.new()
    subtractive_wrapper.operation = CSGShape3D.OPERATION_SUBTRACTION
    nested_subtraction.add_child(subtractive_wrapper)
    var nested_union_box := CSGBox3D.new()
    nested_union_box.operation = CSGShape3D.OPERATION_UNION
    subtractive_wrapper.add_child(nested_union_box)
    await process_frame
    if resolver._road_is_rendered(world, ROAD_ID):
        _fail("UNION geometry under a subtractive combiner wrapper was accepted as positive rendered road geometry")
        return
    nested_subtraction.queue_free()
    await process_frame

    var union_combiner := CSGCombiner3D.new()
    union_combiner.name = "Road_%d_Union" % ROAD_ID
    world.add_child(union_combiner)
    var union_box := CSGBox3D.new()
    union_box.operation = CSGShape3D.OPERATION_UNION
    union_combiner.add_child(union_box)
    await process_frame
    if not resolver._road_is_rendered(world, ROAD_ID):
        _fail("union CSG combiner was incorrectly rejected as rendered road geometry")
        return

    print("AUTOMATIC_ROAD_CSG_POSITIVE_SHAPE_GREEN: road_id=%d subtraction_only_rejected=true intersection_only_rejected=true nested_subtractive_union_rejected=true union_accepted=true destination_advertisable=false jouable=false" % ROAD_ID)
    quit(0)
