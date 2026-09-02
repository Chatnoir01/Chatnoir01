extends SceneTree

const AUTOLOAD_NAME := "BrusselsOsmRoadSurfaceRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_IXELLES_OFFICIAL_SURFACE_AUTHORITY_FAIL: %s" % message)
    quit(1)

func _make_surface() -> MeshInstance3D:
    var surface := MeshInstance3D.new()
    surface.name = "StreetSurfaces_S"
    var baseline := StandardMaterial3D.new()
    baseline.albedo_color = Color(0.31, 0.32, 0.33, 1.0)
    surface.material_override = baseline
    return surface

func _add_ixelles_surface(scene_owner: Node3D) -> MeshInstance3D:
    var container := Node3D.new()
    container.name = "OfficialIxellesStreetSurfaces"
    scene_owner.add_child(container)
    var surface := _make_surface()
    container.add_child(surface)
    return surface

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null")
        return
    var runtime := root.get_node_or_null(AUTOLOAD_NAME)
    if runtime == null:
        _fail("canonical road surface runtime missing")
        return

    var foreign_wrapper := Node3D.new()
    foreign_wrapper.name = "ForeignEnvironmentOwner"
    root.add_child(foreign_wrapper)
    var foreign_main := Node3D.new()
    foreign_main.name = "Main"
    foreign_wrapper.add_child(foreign_main)
    var foreign_surface := _add_ixelles_surface(foreign_main)
    var foreign_material := foreign_surface.material_override

    for _frame: int in range(8):
        await process_frame

    if foreign_surface.material_override != foreign_material:
        _fail("foreign nested Ixelles surface material was mutated")
        return
    if foreign_surface.has_meta("ground_network_provider") or foreign_surface.has_meta("ground_network_presentation_family"):
        _fail("foreign nested Ixelles surface captured shared ground-network authority")
        return

    var viewport := SubViewport.new()
    viewport.name = "IxellesAuthorityViewport"
    root.add_child(viewport)
    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)
    var production_surface := _add_ixelles_surface(main)
    var production_legacy := production_surface.material_override

    for _frame: int in range(8):
        await process_frame

    if production_surface.material_override == production_legacy:
        _fail("authoritative Ixelles surface did not receive shared presentation")
        return
    if str(production_surface.get_meta("ground_network_provider", "")) != "UrbIS":
        _fail("authoritative Ixelles surface provider changed")
        return
    if bool(production_surface.get_meta("geometry_changed_by_ground_network_runtime", true)):
        _fail("runtime claimed Ixelles source geometry mutation")
        return
    if foreign_surface.material_override != foreign_material or foreign_surface.has_meta("ground_network_provider"):
        _fail("foreign Ixelles clone mutated after authoritative owner arrived")
        return

    print("BRUSSELS_IXELLES_OFFICIAL_SURFACE_AUTHORITY_OK: foreign_nested_rejected=true authoritative_root_viewport_main=true provider=UrbIS geometry_changed=false")
    quit(0)
