extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_WINDOW_TRIM_VARIATION_FAIL: %s" % message)
    quit(1)

func _color_key(color: Color) -> String:
    return "%.3f,%.3f,%.3f" % [color.r, color.g, color.b]

func _collect(details: Node, prefix: String) -> Dictionary:
    var total := 0
    var groups := 0
    var colors := {}
    for child: Node in details.get_children():
        if not child.name.begins_with(prefix) or not child is MultiMeshInstance3D:
            continue
        var mm := (child as MultiMeshInstance3D).multimesh
        if mm == null or mm.instance_count < 1:
            continue
        var mesh := mm.mesh as BoxMesh
        if mesh == null:
            _fail("%s group must keep the low-cost BoxMesh" % prefix)
            return {}
        var material := mesh.material as StandardMaterial3D
        if material == null:
            _fail("%s group has no StandardMaterial3D" % prefix)
            return {}
        var color := material.albedo_color
        if color.r < 0.38 or color.g < 0.36 or color.b < 0.31 or color.r > 0.68 or color.g > 0.65 or color.b > 0.58:
            _fail("%s color escaped restrained stone bounds: %s" % [prefix, _color_key(color)])
            return {}
        if material.roughness < 0.78 or material.roughness > 0.98:
            _fail("%s roughness escaped masonry bounds: %.3f" % [prefix, material.roughness])
            return {}
        total += mm.instance_count
        groups += 1
        colors[_color_key(color)] = true
    return {"total": total, "groups": groups, "colors": colors.size()}

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame

    var details := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails")
    if details == null:
        _fail("GeneratedFacadeDetails is missing")
        return
    var source := details.get_node_or_null("CorridorFacadeWindows") as MultiMeshInstance3D
    if source == null or source.multimesh == null:
        _fail("window transform source disappeared")
        return
    var windows := source.multimesh.instance_count
    if windows != 913:
        _fail("canonical upper-window count changed; expected=913 actual=%d" % windows)
        return

    var lintels := _collect(details, "CorridorFacadeLintels")
    var sills := _collect(details, "CorridorFacadeSills")
    var jambs := _collect(details, "CorridorFacadeJambs")
    if lintels.is_empty() or sills.is_empty() or jambs.is_empty():
        return
    if int(lintels.total) != windows or int(sills.total) != windows or int(jambs.total) != windows * 2:
        _fail("trim counts changed; windows=%d lintels=%d sills=%d jambs=%d" % [windows, lintels.total, sills.total, jambs.total])
        return
    if int(lintels.groups) < 4 or int(sills.groups) < 4 or int(jambs.groups) < 4:
        _fail("window trim remains globally synchronized; lintel_groups=%d sill_groups=%d jamb_groups=%d" % [lintels.groups, sills.groups, jambs.groups])
        return
    if int(lintels.colors) < 4 or int(sills.colors) < 4 or int(jambs.colors) < 4:
        _fail("window trim needs at least four restrained stone tones; lintel_colors=%d sill_colors=%d jamb_colors=%d" % [lintels.colors, sills.colors, jambs.colors])
        return

    print("CORRIDOR_WINDOW_TRIM_VARIATION_OK windows=%d lintels=%d sills=%d jambs=%d groups=%d colors=%d" % [windows, lintels.total, sills.total, jambs.total, lintels.groups, lintels.colors])
    scene.queue_free()
    quit(0)
