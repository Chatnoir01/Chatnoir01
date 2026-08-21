extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/belgian_police_ped_runtime.gd")
const EXPECTED_DESIGN := "belgian-patrol-authored-v4"
const EXPECTED_PUBLIC_BODY := "res://assets/characters/player_character.glb"

func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BELGIAN_POLICE_PED_RUNTIME_FAIL: %s" % message)
    quit(1)


func _visible_forbidden_prop(node: Node) -> String:
    var forbidden := ["dagger", "sword", "crossbow", "bow", "quiver", "arrow", "shield", "weapon", "knife", "throwable", "cape"]
    var lower := node.name.to_lower()
    if node is VisualInstance3D and (node as VisualInstance3D).visible:
        for token: String in forbidden:
            if token in lower:
                return str(node.get_path())
    for child: Node in node.get_children():
        var found := _visible_forbidden_prop(child)
        if not found.is_empty():
            return found
    return ""


func _count_named_children(node: Node, expected_name: String) -> int:
    var count := 0
    for child: Node in node.get_children():
        if child.name == expected_name:
            count += 1
    return count


func _run() -> void:
    var host := Node3D.new()
    host.name = "PolicePedTestHost"
    root.add_child(host)

    var agent := NpcAgent.new()
    agent.name = "BehaviorPolice_Test"
    agent.role = NpcBehaviorModel.Role.POLICE
    agent.variation_seed = 7100

    var legacy := Node3D.new()
    legacy.name = "VisibleHumanoid"
    legacy.visible = true
    agent.add_child(legacy)

    host.add_child(agent)
    agent.add_to_group("police_officer")
    var original_instance_id := agent.get_instance_id()
    var original_role := agent.role

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "PoliceRuntimeUnderTest"
    root.add_child(runtime)

    if not runtime.upgrade_agent(agent, true):
        _fail("runtime did not upgrade the existing NpcAgent")
        return
    if agent.get_instance_id() != original_instance_id or agent.role != original_role:
        _fail("behavioral police identity/role changed")
        return
    if not agent.is_in_group("police_officer") or not agent.is_in_group("belgian_police"):
        _fail("behavioral/public police groups missing")
        return
    if legacy.visible:
        _fail("legacy VisibleHumanoid stayed visible")
        return
    if host.get_node_or_null("BelgianPolicePed") != null:
        _fail("runtime spawned a forbidden standalone police actor")
        return

    var visual := agent.get_node_or_null("BelgianPoliceVisual") as Node3D
    if visual == null:
        _fail("BelgianPoliceVisual missing on existing NpcAgent")
        return
    var body := visual.get_node_or_null("CC0PoliceBody") as Node3D
    if body == null:
        _fail("committed CC0 character body missing")
        return
    if absf(body.position.y) > 0.001:
        _fail("public body is not grounded on ground-origin NpcAgent: y=%.3f" % body.position.y)
        return
    if str(visual.get_meta("body_source", "")) != EXPECTED_PUBLIC_BODY:
        _fail("public body source drifted")
        return
    if str(visual.get_meta("body_license", "")) != "CC0-1.0":
        _fail("public body license drifted")
        return
    if str(agent.get_meta("visual_design", "")) != EXPECTED_DESIGN:
        _fail("agent design version missing")
        return
    if str(visual.get_meta("visual_design", "")) != EXPECTED_DESIGN:
        _fail("visual design version missing")
        return

    var required_parts := ["PatrolVest", "FrontIdentityBand", "RearIdentityBand", "CapCrown", "CapVisor", "DutyBelt", "Radio", "RadioAntenna", "BodyCamera", "BodyCameraLens", "Holster", "BilingualPoliceLabel"]
    for part_name: String in required_parts:
        if visual.get_node_or_null(part_name) == null:
            _fail("authored patrol part missing: %s" % part_name)
            return

    var forbidden_visible := _visible_forbidden_prop(body)
    if not forbidden_visible.is_empty():
        _fail("adventurer prop still visible: %s" % forbidden_visible)
        return

    if not runtime.upgrade_agent(agent, true):
        _fail("idempotent upgrade returned false")
        return
    if _count_named_children(agent, "BelgianPoliceVisual") != 1:
        _fail("duplicate upgraded visual created")
        return
    if runtime.mount_into(host, true) != agent:
        _fail("backward-compatible mount_into did not return the existing behavioral police")
        return

    var metrics := runtime.get_runtime_metrics()
    if int(metrics.get("upgraded_police_count", 0)) != 1:
        _fail("unexpected upgraded police count")
        return
    if bool(metrics.get("standalone_actor_spawned", true)):
        _fail("standalone actor metric must stay false")
        return
    if not bool(metrics.get("preserves_npc_agent", false)):
        _fail("NpcAgent preservation metric missing")
        return
    if str(metrics.get("visual_source", "")) != "public_cc0_authored":
        _fail("public authored source not active")
        return
    if bool(metrics.get("redistribution_authorized", true)):
        _fail("local GTA-derived redistribution gate must remain closed")
        return
    if not bool(metrics.get("public_visual_redistribution_authorized", false)):
        _fail("public CC0 visual must be redistributable")
        return
    if str(metrics.get("public_visual_license", "")) != "CC0-1.0":
        _fail("public visual license metric drifted")
        return
    if str(metrics.get("design_version", "")) != EXPECTED_DESIGN:
        _fail("runtime metrics design version drifted")
        return
    if bool(metrics.get("changes_navigation", true)) or bool(metrics.get("changes_police_response", true)):
        _fail("visual upgrade changed behavioral ownership")
        return
    if runtime.set_police_animation("invalid"):
        _fail("invalid animation accepted")
        return
    if not runtime.set_police_animation("idle"):
        _fail("authored body exposes no usable idle animation")
        return

    agent.velocity = Vector3(0.8, 0.0, 0.0)
    runtime.sync_agent_for_test(agent)
    agent.velocity = Vector3.ZERO
    runtime.sync_agent_for_test(agent)

    print("BELGIAN_POLICE_PED_RUNTIME_OK existing_npc=true standalone=false public_cc0=true grounded=true legacy_hidden=true animation_sync=true")
    runtime.queue_free()
    host.queue_free()
    quit(0)
