extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const SUPPORT_BODY_NAME := "GenericOsmSurfaceCollisionBody"
const DEDICATED_SUPPORT_LAYER := 1 << 19
const MAX_READY_FRAMES := 240

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GENERIC_OSM_GROUND_ISOLATION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene did not instantiate")
        return
    root.add_child(scene)

    var support_body: StaticBody3D = null
    var roads_root: Node = null
    for _frame: int in range(MAX_READY_FRAMES):
        await physics_frame
        roads_root = scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
        if roads_root == null:
            continue
        support_body = roads_root.get_node_or_null(SUPPORT_BODY_NAME) as StaticBody3D
        if support_body != null:
            await physics_frame
            break

    if support_body == null:
        _fail("generic OSM support body did not materialize")
        return
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("canonical Player CharacterBody3D missing")
        return
    var vehicle := scene.get_node_or_null("PrototypeCar") as CollisionObject3D
    if vehicle == null:
        _fail("canonical PrototypeCar collision object missing")
        return

    if support_body.collision_layer != DEDICATED_SUPPORT_LAYER:
        _fail("support must use dedicated player-only layer %d, got %d" % [DEDICATED_SUPPORT_LAYER, support_body.collision_layer])
        return
    if support_body.collision_mask != 0:
        _fail("static support must not query unrelated bodies; mask=%d" % support_body.collision_mask)
        return
    if (player.collision_mask & DEDICATED_SUPPORT_LAYER) == 0:
        _fail("canonical Player did not opt into dedicated generic support layer")
        return
    if (vehicle.collision_mask & DEDICATED_SUPPORT_LAYER) != 0:
        _fail("PrototypeCar must remain isolated from player-only generic support")
        return
    if not bool(support_body.get_meta("player_only_collision", false)):
        _fail("support player-only collision contract metadata missing")
        return

    print("GENERIC_OSM_GROUND_ISOLATION_OK: support_layer=%d support_mask=0 player_opt_in=true prototype_car_opt_in=false player_only_collision=true" % DEDICATED_SUPPORT_LAYER)
    quit(0)
