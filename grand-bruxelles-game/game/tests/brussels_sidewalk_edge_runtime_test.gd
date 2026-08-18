extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_sidewalk_edge_runtime.gd"

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("BRUSSELS_SIDEWALK_EDGE_RUNTIME_FAIL: %s" % message); quit(1)

func _box(name: String, size: Vector3, position: Vector3, rotation_y: float = 0.0) -> CSGBox3D:
    var box := CSGBox3D.new()
    box.name = name
    box.size = size
    box.position = position
    box.rotation.y = rotation_y
    box.use_collision = false
    return box

func _run() -> void:
    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null: _fail("runtime script missing"); return
    var scene := Node3D.new(); scene.name = "SidewalkEdgeContractScene"; root.add_child(scene)
    var generated := Node3D.new(); generated.name = "GeneratedRoads"; scene.add_child(generated)

    var road_a := _box("Road_a_0", Vector3(6.0, 0.10, 18.0), Vector3(0.0, 0.025, 0.0))
    var a := _box("SidewalkA", Vector3(1.85, 0.12, 18.0), Vector3(4.025, 0.085, 0.0))
    # Regression witness: a perpendicular road crosses the centre of road_a.
    # The fascia on SidewalkA must be split around this intersection instead of
    # drawing a rail-like strip through the crossing.
    var road_cross := _box("Road_cross_0", Vector3(6.0, 0.10, 12.0), Vector3(0.0, 0.025, 0.0), PI * 0.5)

    var road_b := _box("Road_b_0", Vector3(8.0, 0.10, 24.0), Vector3(10.0, 0.025, 40.0))
    var b := _box("SidewalkB", Vector3(2.55, 0.12, 24.0), Vector3(15.375, 0.085, 40.0))
    generated.add_child(road_a); generated.add_child(a); generated.add_child(road_cross); generated.add_child(road_b); generated.add_child(b)
    var a_transform := a.global_transform; var a_size := a.size; var b_transform := b.global_transform; var b_size := b.size

    # Production regression: SceneTree.current_scene may be null in runtime harnesses.
    # The runtime must discover GeneratedRoads from the live tree instead of relying on current_scene.
    var runtime := runtime_script.new() as Node; root.add_child(runtime)
    for _frame: int in range(8):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break
    if not bool(runtime.call("ready_complete")): _fail("runtime did not discover GeneratedRoads from SceneTree.root"); return
    if bool(runtime.call("failed")): _fail("runtime failed to auto-bind"); return

    var direct_interval: Vector2 = runtime.call("_intersection_interval", a, -0.905, -6.0, 6.0, road_cross)
    var cross_is_road := bool(runtime.call("_is_road", road_cross))
    print("BRUSSELS_SIDEWALK_EDGE_INTERSECTION_DIAGNOSTIC: cross_is_road=%s interval=(%.4f,%.4f) sidewalk_pos=(%.3f,%.3f) cross_pos=(%.3f,%.3f) cross_axis_x=(%.3f,%.3f) cross_axis_z=(%.3f,%.3f)" % [str(cross_is_road), direct_interval.x, direct_interval.y, a.global_position.x, a.global_position.z, road_cross.global_position.x, road_cross.global_position.z, road_cross.global_transform.basis.x.x, road_cross.global_transform.basis.x.z, road_cross.global_transform.basis.z.x, road_cross.global_transform.basis.z.z])
    if not cross_is_road: _fail("perpendicular witness is not classified as road"); return
    if direct_interval.y <= direct_interval.x: _fail("direct intersection interval rejected: (%.4f, %.4f)" % [direct_interval.x, direct_interval.y]); return

    if int(runtime.call("sidewalk_count")) != 2: _fail("sidewalk reuse count changed"); return
    if int(runtime.call("edge_count")) != 3: _fail("intersection-safe split missing after valid direct interval: expected 3 fascia segments from 2 sidewalks"); return
    if int(runtime.call("intersection_clip_count")) < 1: _fail("perpendicular-road intersection was not clipped"); return
    if int(runtime.call("batch_count")) != 1 or int(runtime.call("collision_count")) != 0: _fail("cost contract changed"); return
    if not bool(runtime.call("geometry_unchanged")) or not bool(runtime.call("edge_visual_within_sidewalk_envelope")): _fail("geometry/envelope invariant failed"); return
    if not a.global_transform.is_equal_approx(a_transform) or not a.size.is_equal_approx(a_size) or not b.global_transform.is_equal_approx(b_transform) or not b.size.is_equal_approx(b_size): _fail("sidewalk transform/size changed"); return
    if str(a.get_meta("sidewalk_edge_material_family", "")) != "brussels_sidewalk_edge_v1" or bool(a.get_meta("sidewalk_edge_source_height_claimed", true)): _fail("provenance metadata invalid"); return
    if not bool(a.get_meta("sidewalk_edge_intersection_clipped", false)): _fail("intersection clipping metadata missing"); return
    print("BRUSSELS_SIDEWALK_EDGE_RUNTIME_OK: auto_bind=root sidewalks=2 edges=3 intersection_clips>=1 batches=1 collisions=0 road_facing_only=true geometry_unchanged=true source_height_claimed=false")
    quit(0)
