extends SceneTree

const BODY_NAME := "GenericOsmSurfaceCollisionBody"
const OWNER_META := "grand_bruxelles_owner"
const OWNER_ID := "generic_osm_surface_collision_runtime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GENERIC_OSM_SURFACE_COLLISION_OWNER_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene did not instantiate as Node3D")
        return
    root.add_child(scene)

    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads_root == null:
        _fail("GeneratedRoads production root missing")
        return
    if scene.get_node_or_null("Player") == null:
        _fail("canonical Player missing")
        return

    # Reproduce a legitimate foreign child using the legacy runtime name.
    # Name alone must never be sufficient authority to suppress player support.
    var foreign := Node3D.new()
    foreign.name = BODY_NAME
    foreign.set_meta("foreign_owner_sentinel", true)
    roads_root.add_child(foreign)

    for _frame: int in range(48):
        await physics_frame

    if not is_instance_valid(foreign) or foreign.get_parent() != roads_root:
        _fail("foreign same-name node was removed or reparented")
        return
    if not bool(foreign.get_meta("foreign_owner_sentinel", false)):
        _fail("foreign same-name node metadata was mutated")
        return

    var owned_body: StaticBody3D = null
    for child: Node in roads_root.get_children():
        if child is StaticBody3D and str(child.get_meta(OWNER_META, "")) == OWNER_ID:
            if owned_body != null:
                _fail("multiple owned support bodies mounted")
                return
            owned_body = child as StaticBody3D

    if owned_body == null:
        _fail("owned player support was suppressed by foreign same-name node")
        return
    if int(owned_body.get_meta("road_support_surfaces", 0)) <= 0:
        _fail("owned support has no road surfaces")
        return
    if int(owned_body.get_meta("support_triangle_count", 0)) <= 0:
        _fail("owned support has no triangles")
        return
    if not bool(owned_body.get_meta("player_only_collision", false)):
        _fail("owned support lost player-only collision contract")
        return
    if not bool(owned_body.get_meta("visible_surfaces_only", false)):
        _fail("owned support lost visible-surface contract")
        return

    print("GENERIC_OSM_SURFACE_COLLISION_OWNER_OK: foreign_same_name_preserved=true owned_support_present=true roads=%d triangles=%d owner=%s" % [int(owned_body.get_meta("road_support_surfaces", 0)), int(owned_body.get_meta("support_triangle_count", 0)), OWNER_ID])
    quit(0)
