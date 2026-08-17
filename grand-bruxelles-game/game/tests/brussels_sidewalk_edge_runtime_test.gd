extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_sidewalk_edge_runtime.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SIDEWALK_EDGE_RUNTIME_FAIL: %s" % message)
    quit(1)

func _sidewalk(width: float, length: float, position: Vector3, angle: float) -> CSGBox3D:
    var box := CSGBox3D.new()
    box.size = Vector3(width, 0.12, length)
    box.position = position
    box.rotation.y = angle
    box.use_collision = false
    return box

func _run() -> void:
    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null:
        _fail("runtime script missing"); return
    var scene := Node3D.new()
    scene.name = "SidewalkEdgeContractScene"
    root.add_child(scene)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    scene.add_child(roads)
    var a := _sidewalk(1.85, 18.0, Vector3(5.0, 0.085, 2.0), 0.2)
    var b := _sidewalk(2.55, 24.0, Vector3(-7.0, 0.085, -3.0), -0.4)
    roads.add_child(a); roads.add_child(b)
    var a_transform := a.global_transform; var a_size := a.size
    var b_transform := b.global_transform; var b_size := b.size

    var runtime := runtime_script.new() as Node
    root.add_child(runtime)
    runtime.call("bind_scene", scene)
    await process_frame
    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")):
        _fail("runtime failed to bind"); return
    if int(runtime.call("sidewalk_count")) != 2:
        _fail("expected 2 sidewalks"); return
    if int(runtime.call("edge_count")) != 4:
        _fail("expected 4 edge instances"); return
    if int(runtime.call("batch_count")) != 1:
        _fail("expected one MultiMesh batch"); return
    if int(runtime.call("collision_count")) != 0:
        _fail("edge presentation must add zero collisions"); return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("runtime reports sidewalk geometry mutation"); return
    if not bool(runtime.call("edge_visual_within_sidewalk_envelope")):
        _fail("edge visual escapes existing sidewalk envelope"); return
    if not a.global_transform.is_equal_approx(a_transform) or not a.size.is_equal_approx(a_size):
        _fail("first sidewalk transform/size changed"); return
    if not b.global_transform.is_equal_approx(b_transform) or not b.size.is_equal_approx(b_size):
        _fail("second sidewalk transform/size changed"); return
    if str(a.get_meta("sidewalk_edge_material_family", "")) != "brussels_sidewalk_edge_v1":
        _fail("material family metadata missing"); return
    if bool(a.get_meta("sidewalk_edge_source_height_claimed", true)):
        _fail("unsupported source curb-height claim"); return
    print("BRUSSELS_SIDEWALK_EDGE_RUNTIME_OK: sidewalks=2 edges=4 batches=1 collisions=0 geometry_unchanged=true source_height_claimed=false")
    quit(0)
