extends SceneTree

const SLICE_SCRIPT := preload("res://game/zones/ixelles/ixelles_microslice.gd")
const CELL_WEST := 149000.0
const CELL_SOUTH := 169000.0
const SPACING_M := 2.0
const MAX_ALLOWED_DELTA_M := 0.002

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_DTM_GODOT_TRANSFORM_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _run() -> void:
    var world := Node3D.new()
    world.name = "IxellesDtmTransformProbe"
    root.add_child(world)

    var slice = SLICE_SCRIPT.new()
    slice.name = "IxellesMicroSlice"
    world.add_child(slice)

    for _frame: int in range(4):
        await process_frame
        await physics_frame

    if not _expect(bool(slice.runtime_loaded), "production Ixelles micro-slice did not become ready"):
        return
    if not _expect(slice.find_child("OfficialIxellesDTMCollision", true, false) != null, "production DTM collision body missing"):
        return

    # Deliberately asymmetric rows/columns make a north/south or east/west mirror
    # impossible to hide behind smooth terrain or a centre-only sample.
    var samples: Array[Vector2i] = [
        Vector2i(20, 20),
        Vector2i(20, 200),
        Vector2i(70, 145),
        Vector2i(155, 65),
        Vector2i(205, 210),
        Vector2i(230, 35),
    ]
    var max_delta_m := 0.0
    var worst_sample := Vector2i.ZERO
    var state := world.get_world_3d().direct_space_state

    for sample: Vector2i in samples:
        var row := sample.x
        var col := sample.y
        var e := CELL_WEST + float(col) * SPACING_M
        var n := CELL_SOUTH + float(row) * SPACING_M
        var p: Vector3 = slice.lambert_to_game(e, n)
        var expected_y := float(slice.sample_height(p.x, p.z))
        var query := PhysicsRayQueryParameters3D.create(
            Vector3(p.x, expected_y + 120.0, p.z),
            Vector3(p.x, expected_y - 120.0, p.z)
        )
        query.collision_mask = 1
        query.collide_with_areas = false
        query.collide_with_bodies = true
        var hit := state.intersect_ray(query)
        if not _expect(not hit.is_empty(), "no PhysicsServer hit at grid row=%d col=%d" % [row, col]):
            return
        var hit_position: Vector3 = hit.get("position", Vector3.INF)
        if not _expect(hit_position.is_finite(), "non-finite PhysicsServer hit at row=%d col=%d" % [row, col]):
            return
        var delta_m := absf(hit_position.y - expected_y)
        if delta_m > max_delta_m:
            max_delta_m = delta_m
            worst_sample = sample

    if not _expect(max_delta_m <= MAX_ALLOWED_DELTA_M, "render/collision transform divergence %.6f m at row=%d col=%d" % [max_delta_m, worst_sample.x, worst_sample.y]):
        return

    print("IXELLES_DTM_GODOT_TRANSFORM_OK: samples=%d max_delta_m=%.6f vertical_reference=%.6f" % [samples.size(), max_delta_m, float(slice.vertical_reference_absolute_m)])
    world.queue_free()
    quit(0)
