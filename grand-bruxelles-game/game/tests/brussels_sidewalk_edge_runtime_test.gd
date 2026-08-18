extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_sidewalk_edge_runtime.gd"

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("BRUSSELS_SIDEWALK_EDGE_RUNTIME_FAIL: %s" % message); quit(1)

func _box(name: String, size: Vector3, position: Vector3) -> CSGBox3D:
    var box := CSGBox3D.new(); box.name = name; box.size = size; box.position = position; box.use_collision = false; return box

func _run() -> void:
    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null: _fail("runtime script missing"); return
    var scene := Node3D.new(); scene.name = "SidewalkEdgeContractScene"; root.add_child(scene)
    var generated := Node3D.new(); generated.name = "GeneratedRoads"; scene.add_child(generated)
    var road_a := _box("Road_a_0", Vector3(6.0, 0.10, 18.0), Vector3(0.0, 0.025, 0.0))
    var a := _box("SidewalkA", Vector3(1.85, 0.12, 18.0), Vector3(3.0, 0.085, 0.0))
    var road_b := _box("Road_b_0", Vector3(8.0, 0.10, 24.0), Vector3(10.0, 0.025, 40.0))
    var b := _box("SidewalkB", Vector3(2.55, 0.12, 24.0), Vector3(14.0, 0.085, 40.0))
    generated.add_child(road_a); generated.add_child(a); generated.add_child(road_b); generated.add_child(b)
    var a_transform := a.global_transform; var a_size := a.size; var b_transform := b.global_transform; var b_size := b.size
    var runtime := runtime_script.new() as Node; root.add_child(runtime); runtime.call("bind_scene", scene); await process_frame
    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")): _fail("runtime failed to bind"); return
    if int(runtime.call("sidewalk_count")) != 2 or int(runtime.call("edge_count")) != 2: _fail("expected exactly one roadway-facing edge per sidewalk"); return
    if int(runtime.call("batch_count")) != 1 or int(runtime.call("collision_count")) != 0: _fail("cost contract changed"); return
    if not bool(runtime.call("geometry_unchanged")) or not bool(runtime.call("edge_visual_within_sidewalk_envelope")): _fail("geometry/envelope invariant failed"); return
    if not a.global_transform.is_equal_approx(a_transform) or not a.size.is_equal_approx(a_size) or not b.global_transform.is_equal_approx(b_transform) or not b.size.is_equal_approx(b_size): _fail("sidewalk transform/size changed"); return
    if str(a.get_meta("sidewalk_edge_material_family", "")) != "brussels_sidewalk_edge_v1" or bool(a.get_meta("sidewalk_edge_source_height_claimed", true)): _fail("provenance metadata invalid"); return
    print("BRUSSELS_SIDEWALK_EDGE_RUNTIME_OK: sidewalks=2 edges=2 batches=1 collisions=0 road_facing_only=true geometry_unchanged=true source_height_claimed=false")
    quit(0)
