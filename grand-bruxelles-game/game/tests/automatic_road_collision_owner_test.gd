extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 359177328
const OTHER_ROAD_ID := 363843330
const ROAD_IDS_META := "road_support_osm_ids"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_COLLISION_OWNER_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)

    var canonical_ground := StaticBody3D.new()
    canonical_ground.name = "Ground"
    root.add_child(canonical_ground)
    if resolver._ground_hit_is_authorized(canonical_ground, canonical_ground, ROAD_ID):
        _fail("canonical ground was accepted for a positive road id")
        return
    if not resolver._ground_hit_is_authorized(canonical_ground, canonical_ground, 0):
        _fail("canonical ground legacy/no-road fallback was rejected")
        return

    var support := StaticBody3D.new()
    root.add_child(support)

    support.set_meta(ROAD_IDS_META, [ROAD_ID])
    if resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("matching road identity was accepted without the canonical collision owner")
        return

    support.set_meta("grand_bruxelles_owner", "generic_osm_surface_collision_runtime")
    support.remove_meta(ROAD_IDS_META)
    if resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("road-support collider without an OSM road identity set was accepted")
        return

    support.set_meta(ROAD_IDS_META, [OTHER_ROAD_ID])
    if resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("road-support collider without the requested OSM road was accepted")
        return

    support.set_meta(ROAD_IDS_META, [true])
    if resolver._ground_hit_is_authorized(support, null, 1):
        _fail("bool road identity was accepted as integer OSM identity")
        return

    support.set_meta(ROAD_IDS_META, [0, ROAD_ID])
    if resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("non-positive road identity was accepted inside a matching identity set")
        return

    support.set_meta(ROAD_IDS_META, [ROAD_ID, ROAD_ID])
    if resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("duplicate road identity was accepted inside collision metadata")
        return

    support.set_meta(ROAD_IDS_META, [ROAD_ID, "bad"])
    if resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("malformed road identity set was accepted because the requested road appeared before invalid metadata")
        return

    support.set_meta(ROAD_IDS_META, [OTHER_ROAD_ID, ROAD_ID])
    if not resolver._ground_hit_is_authorized(support, null, ROAD_ID):
        _fail("matching road-support collider was rejected")
        return

    print("AUTOMATIC_ROAD_COLLISION_OWNER_GREEN: road_id=%d positive_road_generic_ground_rejected=true legacy_ground_fallback_accepted=true missing_owner_rejected=true missing_identity_rejected=true mismatched_identity_rejected=true bool_identity_rejected=true nonpositive_identity_rejected=true duplicate_identity_rejected=true malformed_identity_set_rejected=true exact_identity_accepted=true destination_advertisable=false jouable=false" % ROAD_ID)
    quit(0)
