extends SceneTree

const FLEET_SCRIPT := preload("res://game/scripts/belgian_police_fleet_runtime.gd")
const OVERLAY_SCRIPT := preload("res://game/scripts/mmc_police_authored_lod_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MMC_POLICE_V2_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var scene := Node3D.new()
    scene.name = "TestScene"
    root.add_child(scene)
    var reference := Node3D.new()
    reference.name = "ParkedCar_00"
    reference.position = Vector3(3.0, 0.46, -4.0)
    scene.add_child(reference)
    var overlay := OVERLAY_SCRIPT.new()
    scene.add_child(overlay)
    var contract: Dictionary = overlay.call("get_contract") as Dictionary
    if int(contract.get("source_derived_lod_count", 0)) != 2 or int(contract.get("project_cabin_count", 0)) != 2:
        _fail("V3 source geometry/interior contract mismatch")
        return
    if int(contract.get("project_body_closure_count", 0)) != 2 or int(contract.get("source_derived_detail_overlay_count", 0)) != 2:
        _fail("V3 closed-body/source-overlay contract mismatch")
        return
    if int(contract.get("police_officer_count", 0)) != 3 or int(contract.get("driveable_police_vehicle_count", 0)) != 1:
        _fail("V2 officer/driveable contract mismatch")
        return
    for forbidden: String in ["changes_existing_physics", "changes_existing_collision", "changes_traffic_motion", "changes_geography"]:
        if bool(contract.get(forbidden, true)):
            _fail("forbidden existing-world mutation enabled: %s" % forbidden)
            return
    var driveable := overlay.call("spawn_driveable_sedan", scene, reference) as RigidBody3D
    if driveable == null or not driveable.is_in_group("vehicle"):
        _fail("driveable police sedan was not registered as a vehicle")
        return
    if not driveable.has_method("enter_driver") or not driveable.has_method("exit_driver") or not driveable.has_method("has_driver"):
        _fail("existing enter/exit vehicle contract is missing")
        return
    if reference.visible:
        _fail("static parked sedan reference was not replaced")
        return
    var collision := driveable.get_node_or_null(NodePath("CollisionShape3D")) as CollisionShape3D
    var camera := driveable.get_node_or_null(NodePath("CameraPivot/SpringArm3D/Camera3D")) as Camera3D
    if collision == null or collision.shape == null or camera == null:
        _fail("driveable police sedan collision/camera hierarchy missing")
        return
    var holder := driveable.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
    if holder == null:
        _fail("driveable sedan police holder missing")
        return
    var sedan_config: Dictionary = overlay.call("config_at", 0) as Dictionary
    if not bool(overlay.call("install_on_holder", holder, sedan_config)):
        _fail("high fidelity sedan source LOD failed to mount")
        return
    if not bool(overlay.call("install_officers", holder, true)):
        _fail("sedan passenger officer failed to mount")
        return
    var sedan_lod := holder.get_node_or_null(NodePath("AuthoredSourceDerivedLOD")) as Node3D
    if sedan_lod == null or int(sedan_lod.get_meta("source_triangles", 0)) != 2697 or int(sedan_lod.get_meta("source_vertices", 0)) != 1465:
        _fail("sedan source-derived geometry counts mismatch")
        return
    if not bool(holder.get_meta("project_cabin_v2", false)) or int(holder.get_meta("officer_count", 0)) != 1:
        _fail("sedan interior/officer metadata missing")
        return
    var sedan_closure := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
    if sedan_closure == null or sedan_closure.get_node_or_null(NodePath("ClosedLowerBody")) == null or sedan_closure.get_node_or_null(NodePath("Windshield")) == null:
        _fail("sedan closed-body V3 hierarchy missing")
        return
    if not bool(holder.get_meta("source_lod_detail_overlay_preserved", false)):
        _fail("sedan source-derived detail overlay was not preserved")
        return

    var coupe := Node3D.new()
    coupe.name = "AmbientTraffic_03"
    scene.add_child(coupe)
    var fleet := FLEET_SCRIPT.new()
    if not bool(fleet.call("apply_profile_to_vehicle", coupe, 4)):
        _fail("coupe police profile failed")
        return
    var coupe_holder := coupe.get_node_or_null(NodePath("BelgianPoliceFleetVisual")) as Node3D
    var coupe_config: Dictionary = overlay.call("config_at", 1) as Dictionary
    if coupe_holder == null or not bool(overlay.call("install_on_holder", coupe_holder, coupe_config)):
        _fail("high fidelity coupe source LOD failed to mount")
        return
    if not bool(overlay.call("install_officers", coupe_holder, false)):
        _fail("coupe officers failed to mount")
        return
    var coupe_lod := coupe_holder.get_node_or_null(NodePath("AuthoredSourceDerivedLOD")) as Node3D
    if coupe_lod == null or int(coupe_lod.get_meta("source_triangles", 0)) != 2121 or int(coupe_lod.get_meta("source_vertices", 0)) != 1230:
        _fail("coupe source-derived geometry counts mismatch")
        return
    if int(coupe_holder.get_meta("officer_count", 0)) != 2:
        _fail("coupe must contain driver and passenger officers")
        return
    var coupe_closure := coupe_holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
    if coupe_closure == null or coupe_closure.get_node_or_null(NodePath("RoofPanel")) == null or coupe_closure.get_node_or_null(NodePath("RearWindow")) == null:
        _fail("coupe closed-body V3 hierarchy missing")
        return
    for closure: Node3D in [sedan_closure, coupe_closure]:
        for child: Node in closure.get_children():
            if child is CollisionObject3D or child is CollisionShape3D:
                _fail("V3 visual closure must never add collision")
                return
    await process_frame
    print("MMC_POLICE_V3_OK: source_geometry=true closed_body=2 source_overlay=2 project_cabins=2 officers=3 driveable_sedan=true enter_exit_contract=true existing_traffic_motion_unchanged=true")
    quit(0)
