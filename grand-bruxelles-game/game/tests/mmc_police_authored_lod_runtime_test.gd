extends SceneTree

const FLEET_SCRIPT := preload("res://game/scripts/belgian_police_fleet_runtime.gd")
const OVERLAY_SCRIPT := preload("res://game/scripts/mmc_police_authored_lod_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MMC_POLICE_AUTHORED_LOD_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var fleet := FLEET_SCRIPT.new()
    var overlay := OVERLAY_SCRIPT.new()
    root.add_child(fleet)
    root.add_child(overlay)
    var contract: Dictionary = overlay.call("get_contract") as Dictionary
    if int(contract.get("source_derived_lod_count", 0)) != 2:
        _fail("expected exactly two source-derived LODs")
        return
    for forbidden: String in ["changes_physics", "changes_collision", "changes_traffic_motion", "changes_geography"]:
        if bool(contract.get(forbidden, true)):
            _fail("forbidden mutation enabled: %s" % forbidden)
            return
    var expected_triangles: Array[int] = [2443, 2178]
    var expected_vertices: Array[int] = [1339, 1209]
    var profile_indices: Array[int] = [0, 4]
    for local_index: int in range(2):
        var vehicle := StaticBody3D.new()
        vehicle.name = "AuthoredLODVehicle_%d" % local_index
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(1.9, 0.9, 4.2)
        collision.shape = shape
        vehicle.add_child(collision)
        var fallback := Node3D.new()
        fallback.name = "ProductionVisual"
        vehicle.add_child(fallback)
        root.add_child(vehicle)
        var original_transform := vehicle.transform
        var original_shape := collision.shape
        if not bool(fleet.call("apply_profile_to_vehicle", vehicle, profile_indices[local_index])):
            _fail("fleet profile failed before overlay")
            return
        var holder := vehicle.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
        if holder == null:
            _fail("police holder missing")
            return
        var config: Dictionary = overlay.call("config_at", local_index) as Dictionary
        if not bool(overlay.call("install_on_holder", holder, config)):
            _fail("source-derived LOD failed to mount")
            return
        if vehicle.transform != original_transform or collision.shape != original_shape:
            _fail("vehicle transform or collision changed")
            return
        var authored := holder.get_node_or_null(NodePath("AuthoredSourceDerivedLOD")) as Node3D
        if authored == null:
            _fail("authored LOD node missing")
            return
        if int(authored.get_meta("source_triangles", 0)) != expected_triangles[local_index]:
            _fail("triangle count mismatch")
            return
        if int(authored.get_meta("source_vertices", 0)) != expected_vertices[local_index]:
            _fail("vertex count mismatch")
            return
        if not bool(holder.get_meta("authored_source_derived_lod", false)):
            _fail("source-derived metadata missing")
            return
        if bool(holder.get_meta("production_authorized_exact_third_party_geometry", true)):
            _fail("derived LOD must not claim exact source geometry authorization")
            return
        for body_name: String in OVERLAY_SCRIPT.BODY_CHILDREN:
            var old_body := holder.get_node_or_null(NodePath(body_name)) as Node3D
            if old_body != null and old_body.visible:
                _fail("procedural body still visible: %s" % body_name)
                return
        if not bool(overlay.call("install_on_holder", holder, config)):
            _fail("idempotent overlay reinstall failed")
            return
        var authored_count := 0
        for child: Node in holder.get_children():
            if child.name == "AuthoredSourceDerivedLOD":
                authored_count += 1
        if authored_count != 1:
            _fail("authored LOD duplicated")
            return
    await process_frame
    print("MMC_POLICE_AUTHORED_LOD_OK: source_derived=2 sedan_triangles=2443 coupe_triangles=2178 physics_unchanged=true collision_unchanged=true")
    quit(0)
