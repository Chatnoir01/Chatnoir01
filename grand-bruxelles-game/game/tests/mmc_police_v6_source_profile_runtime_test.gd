extends SceneTree

const V6_SCRIPT := preload("res://game/scripts/mmc_police_v6_source_profile_tuner.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MMC_POLICE_V6_SOURCE_PROFILE_FAIL: %s" % message)
    quit(1)

func _holder(profile_id: String) -> Node3D:
    var holder := Node3D.new()
    holder.name = "BelgianPoliceFleetVisual"
    holder.set_meta("police_profile_id", profile_id)
    var legacy := Node3D.new()
    legacy.name = "PoliceBodySilhouetteV5"
    holder.add_child(legacy)
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
    var tuner := V6_SCRIPT.new()
    scene.add_child(tuner)
    var contract: Dictionary = tuner.call("get_contract") as Dictionary
    if not bool(contract.get("renderer_only", false)) or not bool(contract.get("source_profile_derived", false)):
        _fail("source-derived renderer-only contract missing")
        return
    for forbidden: String in ["changes_existing_physics", "changes_existing_collision", "changes_traffic_motion", "changes_geography"]:
        if bool(contract.get(forbidden, true)):
            _fail("forbidden mutation enabled: %s" % forbidden)
            return
    var profiles: Array[String] = ["brussels_capitale_sedan", "brussels_rapid_response_coupe"]
    for profile_id: String in profiles:
        var holder := _holder(profile_id)
        var before: Transform3D = holder.transform
        scene.add_child(holder)
        if not bool(tuner.call("install_source_profile", holder, profile_id)):
            _fail("install failed for %s" % profile_id)
            return
        var shell := holder.get_node_or_null(NodePath("PoliceBodySourceProfileV6")) as Node3D
        if shell == null or not bool(shell.get_meta("renderer_only", false)) or not bool(shell.get_meta("source_profile_derived", false)):
            _fail("V6 source shell missing for %s" % profile_id)
            return
        if int(shell.get_meta("lower_section_count", 0)) != 19 or int(shell.get_meta("roof_section_count", 0)) != 13:
            _fail("source section counts mismatch for %s" % profile_id)
            return
        var lower := shell.get_node_or_null(NodePath("SourceProfileLowerHull")) as MeshInstance3D
        var roof := shell.get_node_or_null(NodePath("SourceProfileRoofSkin")) as MeshInstance3D
        if lower == null or lower.mesh == null or roof == null or roof.mesh == null:
            _fail("source-derived meshes missing for %s" % profile_id)
            return
        var legacy := holder.get_node_or_null(NodePath("PoliceBodySilhouetteV5")) as Node3D
        if legacy == null or legacy.visible:
            _fail("V5 shell was not superseded for %s" % profile_id)
            return
        var closure := holder.get_node_or_null(NodePath("PoliceBodyClosureV3")) as Node3D
        for child_name: String in ["ClosedLowerBody", "HoodClosure", "TrunkClosure", "RoofPanel"]:
            var old_piece := closure.get_node_or_null(NodePath(child_name)) as Node3D
            if old_piece == null or old_piece.visible:
                _fail("legacy closure still visible: %s/%s" % [profile_id, child_name])
                return
        if holder.transform != before:
            _fail("holder transform changed for %s" % profile_id)
            return
        if holder.find_children("*", "CollisionShape3D", true, false).size() != 0:
            _fail("V6 introduced collision for %s" % profile_id)
            return
        var first_id: int = shell.get_instance_id()
        if not bool(tuner.call("install_source_profile", holder, profile_id)):
            _fail("idempotent install failed for %s" % profile_id)
            return
        var second := holder.get_node_or_null(NodePath("PoliceBodySourceProfileV6")) as Node3D
        if second == null or second.get_instance_id() != first_id:
            _fail("duplicate V6 shell created for %s" % profile_id)
            return
    print("MMC_POLICE_V6_SOURCE_PROFILE_OK: profiles=2 lower_sections=38 roof_sections=26 collision_changes=0 physics_changes=0")
    quit(0)
