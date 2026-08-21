extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const EXPECTED_DESIGN := "belgian-patrol-authored-v4"
const OUTPUT_DIR := "res://artifacts/qa/belgian_police"
const OUTPUT_PATH := OUTPUT_DIR + "/belgian_police_authored_v4.png"
const WITNESS_POSITION := Vector3(-647.8, 0.0, 617.5)
const WITNESS_YAW_DEGREES := 138.0


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    print("BELGIAN_POLICE_PED_VISUAL_FAIL: %s" % message)
    quit(1)


func _hide_capture_noise(main: Node3D, witness: NpcAgent) -> void:
    for path: String in ["Player", "PrototypeCar", "PhysicalCarB"]:
        var node := main.get_node_or_null(path) as Node3D
        if node != null:
            node.visible = false

    for group_name: String in ["ambient_pedestrian", "ambient_traffic", "living_city_agent", "police_officer"]:
        for node: Node in get_nodes_in_group(group_name):
            if node is Node3D and node != witness:
                (node as Node3D).visible = false

    # UI can be owned by autoloads outside the main scene and can appear late.
    # Hide from the SceneTree root, not only the gameplay scene.
    _hide_ui_recursive(root)


func _hide_ui_recursive(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
        return
    if node is Control:
        (node as Control).visible = false
        return
    for child: Node in node.get_children():
        _hide_ui_recursive(child)


func _police_in_scene(main: Node3D) -> Array[NpcAgent]:
    var result: Array[NpcAgent] = []
    for node: Node in get_nodes_in_group("police_officer"):
        if node is NpcAgent and (node == main or main.is_ancestor_of(node)):
            result.append(node as NpcAgent)
    return result


func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("could not load main scene")
        return
    var main := packed.instantiate() as Node3D
    if main == null:
        _fail("could not instantiate main scene")
        return
    root.add_child(main)
    current_scene = main

    var runtime := root.get_node_or_null("BelgianPolicePedRuntime")
    var visible_city := root.get_node_or_null("VisibleCityRuntime")
    if runtime == null or not runtime.has_method("upgrade_agent"):
        _fail("BelgianPolicePedRuntime autoload unavailable")
        return
    if visible_city == null or not visible_city.has_method("ensure_zone_for_test"):
        _fail("VisibleCityRuntime autoload unavailable")
        return

    visible_city.call("ensure_zone_for_test", "midi")
    for _frame: int in range(20):
        await process_frame

    var police := _police_in_scene(main)
    if police.size() < 2:
        _fail("expected existing Midi behavioral police, got %d" % police.size())
        return
    if main.get_node_or_null("BelgianPolicePed") != null:
        _fail("standalone BelgianPolicePed must not exist")
        return

    for agent: NpcAgent in police:
        if not runtime.call("upgrade_agent", agent, true):
            _fail("could not upgrade existing police %s" % agent.name)
            return
        if not agent.is_in_group("police_officer"):
            _fail("behavioral police group lost during upgrade")
            return
        if str(agent.get_meta("visual_design", "")) != EXPECTED_DESIGN:
            _fail("upgraded police missing design metadata")
            return
        var legacy := agent.get_node_or_null("VisibleHumanoid") as Node3D
        if legacy != null and legacy.visible:
            _fail("legacy police visual remains visible on %s" % agent.name)
            return
        var visual := agent.get_node_or_null("BelgianPoliceVisual") as Node3D
        if visual == null or visual.get_node_or_null("CC0PoliceBody") == null:
            _fail("public authored visual missing on existing police %s" % agent.name)
            return

    var metrics: Dictionary = runtime.call("get_runtime_metrics")
    if int(metrics.get("upgraded_police_count", 0)) < police.size():
        _fail("not all behavioral police were upgraded")
        return
    if bool(metrics.get("standalone_actor_spawned", true)):
        _fail("standalone actor metric drifted")
        return

    # Use one of the real behavioral Midi officers as the witness. Repositioning is
    # test-only so the proof camera cannot accidentally end up behind a facade.
    var witness := police[0]
    witness.movement_held = true
    witness.velocity = Vector3.ZERO
    witness.global_position = WITNESS_POSITION
    witness.rotation_degrees.y = WITNESS_YAW_DEGREES
    runtime.call("sync_agent_for_test", witness)

    _hide_capture_noise(main, witness)

    var camera := Camera3D.new()
    camera.name = "BelgianPoliceAuthoredWitnessCamera"
    camera.fov = 46.0
    camera.near = 0.05
    main.add_child(camera)
    # Same proven Midi staging area as the v3 witness, but farther back for a full-body frame.
    var local_camera_offset := Vector3(3.20, 1.85, -6.20)
    camera.global_position = witness.global_position + witness.global_transform.basis * local_camera_offset
    camera.look_at(witness.global_position + Vector3(0.0, 1.02, 0.0), Vector3.UP)
    camera.current = true

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    for _frame: int in range(18):
        # Late autoload UI must stay out of the evidence image as well.
        _hide_capture_noise(main, witness)
        await process_frame

    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _fail("viewport capture is empty")
        return
    if image.get_width() != 1280 or image.get_height() != 720:
        _fail("unexpected capture size %dx%d" % [image.get_width(), image.get_height()])
        return
    if image.save_png(OUTPUT_PATH) != OK:
        _fail("could not save witness PNG")
        return

    print("BELGIAN_POLICE_PED_VISUAL_OK path=%s design=%s existing_npc=true standalone=false real_midi=true staged_safe_camera=true public_cc0=true" % [OUTPUT_PATH, EXPECTED_DESIGN])
    quit(0)
