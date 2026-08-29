extends SceneTree

const V5_SCRIPT := preload("res://game/scripts/mmc_police_v5_silhouette_tuner.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MMC_POLICE_V5_SILHOUETTE_FAIL: %s" % message)
    quit(1)

func _holder(profile_id: String) -> Node3D:
    var holder := Node3D.new()
    holder.name = "BelgianPoliceFleetVisual"
    holder.set_meta("police_profile_id", profile_id)
    var closure := Node3D.new()
    closure.name = "PoliceBodyClosureV3"
    holder.add_child(closure)
    for child_name: String in ["ClosedLowerBody", "HoodClosure", "TrunkClosure", "RoofPanel"]:
        var piece := MeshInstance3D.new()
        piece.name = child_name
        piece.mesh = BoxMesh.new()
        closure.add_child(piece)
    return holder

func _run() -> void:
    var scene := Node3D.new()
    root.add_child(scene)
    var tuner := V5_SCRIPT.new()
    scene.add_child(tuner)
    var contract: Dictionary = tuner.call("get_contract") as Dictionary
    if not bool(contract.get("renderer_only", false)) or not bool(contract.get("project_owned_silhouette", false)):
        _fail("renderer-only/project-owned contract missing")
        return
    for forbidden: String in ["changes_existing_physics", "changes_existing_collision", "changes_traffic_motion", "changes_geography"]:
        if bool(contract.get(forbidden, true)):
            _fail("forbidden mutation enabled: %s" % forbidden)
            return
    var profiles: Array[String] = ["brussels_capitale_sedan", "brussels_rapid_response_coupe"]
    for profile_id: String in profiles:
        var holder := _holder(profile_id)
        holder.position = Vector3(3.0, 0.5, -2.0)
        var before: Transform3D = holder.transform
        scene.add_child(holder)
        if not bool(tuner.call("install_silhouette", holder, profile_id)):
            _fail("install failed for %s" % profile_id)
            return
        var shell := holder.get_node_or_null(NodePath("PoliceBodySilhouetteV5")) as Node3D
        if shell == null or not bool(shell.get_meta("renderer_only", false)):
            _fail("shell missing for %s" % profile_id)
            return
        var lower := shell.get_node_or_null(NodePath("SmoothLowerHull")) as MeshInstance3D
        var roof := shell.get_node_or_null(NodePath("CurvedRoofSkin")) as MeshInstance3D
        if lower == null or lower.mesh == null or roof == null or roof.mesh == null:
            _fail("smooth body meshes missing for %s" % profile_id)
            return
        if lower.mesh.get_surface_count() != 1 or roof.mesh.get_surface_count() != 1:
            _fail("unexpected surface count for %s" % profile_id)
            return
        if holder.transform != before:
            _fail("vehicle visual transform changed for %s" % profile_id)
            return
        if holder.find_children("*", "CollisionShape3D", true, false).size() != 0:
            _fail("V5 introduced collision geometry for %s" % profile_id)
            return
        var closure := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
        for child_name: String in ["ClosedLowerBody", "HoodClosure", "TrunkClosure", "RoofPanel"]:
            var old_piece := closure.get_node_or_null(NodePath(child_name)) as Node3D
            if old_piece == null or old_piece.visible:
                _fail("box closure still visible: %s/%s" % [profile_id, child_name])
                return
        var first_shell_id: int = shell.get_instance_id()
        if not bool(tuner.call("install_silhouette", holder, profile_id)):
            _fail("idempotent install failed for %s" % profile_id)
            return
        var second_shell := holder.get_node_or_null(NodePath("PoliceBodySilhouetteV5")) as Node3D
        if second_shell == null or second_shell.get_instance_id() != first_shell_id:
            _fail("duplicate shell created for %s" % profile_id)
            return
    print("MMC_POLICE_V5_SILHOUETTE_OK: profiles=2 smooth_hulls=2 curved_roofs=2 collision_changes=0 physics_changes=0")
    quit(0)
