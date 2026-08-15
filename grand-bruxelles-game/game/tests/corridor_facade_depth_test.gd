extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_FACADE_DEPTH_FAIL: %s" % message)
    quit(1)

func _instance_count(node: Node) -> int:
    if node == null or not node is MultiMeshInstance3D:
        return 0
    var mm := (node as MultiMeshInstance3D).multimesh
    return mm.instance_count if mm != null else 0

func _color_key(color: Color) -> String:
    return "%.3f,%.3f,%.3f" % [color.r, color.g, color.b]

func _depth_key(depth: float) -> String:
    return "%.3f" % depth

func _transform_key(transform: Transform3D) -> String:
    var b := transform.basis
    var o := transform.origin
    return "%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f" % [
        o.x, o.y, o.z,
        b.x.x, b.x.y, b.x.z,
        b.y.x, b.y.y, b.y.z,
        b.z.x, b.z.y, b.z.z,
    ]

func _add_transform_counts(counts: Dictionary, mm: MultiMesh) -> void:
    for index: int in range(mm.instance_count):
        var key := _transform_key(mm.get_instance_transform(index))
        counts[key] = int(counts.get(key, 0)) + 1

func _trim_stats(details: Node, prefix: String) -> Dictionary:
    var total := 0
    var groups := 0
    var colors := {}
    for child: Node in details.get_children():
        if not child.name.begins_with(prefix) or not child is MultiMeshInstance3D:
            continue
        var mm := (child as MultiMeshInstance3D).multimesh
        if mm == null or mm.instance_count < 1:
            continue
        var box_mesh := mm.mesh as BoxMesh
        if box_mesh == null:
            _fail("%s group does not use expected low-cost BoxMesh" % prefix)
            return {}
        var material := box_mesh.material as StandardMaterial3D
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

    var window_node := details.get_node_or_null("CorridorFacadeWindows") as MultiMeshInstance3D
    var windows := _instance_count(window_node)
    var shopfront_node := details.get_node_or_null("CorridorShopfronts") as MultiMeshInstance3D
    var shopfronts := _instance_count(shopfront_node)
    var lintel_stats := _trim_stats(details, "CorridorFacadeLintels")
    var sill_stats := _trim_stats(details, "CorridorFacadeSills")
    var jamb_stats := _trim_stats(details, "CorridorFacadeJambs")
    if lintel_stats.is_empty() or sill_stats.is_empty() or jamb_stats.is_empty():
        return
    var lintels := int(lintel_stats.total)
    var sills := int(sill_stats.total)
    var jambs := int(jamb_stats.total)

    if windows < 1 or window_node == null or window_node.multimesh == null:
        _fail("baseline corridor windows disappeared")
        return
    if lintels != windows:
        _fail("every visible corridor window must receive exactly one lintel; windows=%d lintels=%d" % [windows, lintels])
        return
    if sills != windows:
        _fail("every visible corridor window must receive exactly one sill; windows=%d sills=%d" % [windows, sills])
        return
    if jambs != windows * 2:
        _fail("every visible corridor window must receive exactly two jambs; windows=%d jambs=%d" % [windows, jambs])
        return
    if int(lintel_stats.groups) < 4 or int(sill_stats.groups) < 4 or int(jamb_stats.groups) < 4:
        _fail("window trim remains globally synchronized; lintel_groups=%d sill_groups=%d jamb_groups=%d" % [lintel_stats.groups, sill_stats.groups, jamb_stats.groups])
        return
    if int(lintel_stats.colors) < 4 or int(sill_stats.colors) < 4 or int(jamb_stats.colors) < 4:
        _fail("window trim needs at least four restrained stone tones; lintel_colors=%d sill_colors=%d jamb_colors=%d" % [lintel_stats.colors, sill_stats.colors, jamb_stats.colors])
        return
    if shopfronts < 1 or shopfront_node == null or shopfront_node.multimesh == null:
        _fail("baseline corridor shopfronts disappeared")
        return

    var canopy_total := 0
    var canopy_groups := 0
    var canopy_distinct := {}
    var canopy_depths := {}
    for child: Node in details.get_children():
        if not child.name.begins_with("CorridorShopCanopies") or not child is MultiMeshInstance3D:
            continue
        var canopy_node := child as MultiMeshInstance3D
        var mm := canopy_node.multimesh
        if mm == null or mm.instance_count < 1:
            continue
        var box_mesh := mm.mesh as BoxMesh
        if box_mesh == null:
            _fail("canopy group does not use expected low-cost BoxMesh")
            return
        var material := box_mesh.material as StandardMaterial3D
        if material == null:
            _fail("canopy group has no StandardMaterial3D")
            return
        var color := material.albedo_color
        var max_channel := maxf(color.r, maxf(color.g, color.b))
        var min_channel := minf(color.r, minf(color.g, color.b))
        if max_channel > 0.30 or min_channel < 0.05:
            _fail("canopy palette escaped restrained street-level bounds: %s" % _color_key(color))
            return
        canopy_distinct[_color_key(color)] = true
        for index: int in range(mm.instance_count):
            var scale := mm.get_instance_transform(index).basis.get_scale().abs()
            if scale.z < 0.52 or scale.z > 0.92:
                _fail("canopy projection escaped plausible bounds: %.3f" % scale.z)
                return
            canopy_depths[_depth_key(scale.z)] = true
        canopy_total += mm.instance_count
        canopy_groups += 1

    if canopy_total != shopfronts:
        _fail("each existing shopfront must keep exactly one canopy; shops=%d canopies=%d" % [shopfronts, canopy_total])
        return
    if canopy_groups < 4 or canopy_distinct.size() < 4:
        _fail("shop canopies remain too synchronized in material; groups=%d distinct_colors=%d" % [canopy_groups, canopy_distinct.size()])
        return
    if canopy_depths.size() < 3:
        _fail("shop canopy silhouettes remain too synchronized; distinct_projections=%d" % canopy_depths.size())
        return

    var source_transforms := {}
    _add_transform_counts(source_transforms, shopfront_node.multimesh)
    var glass_transforms := {}
    var glass_total := 0
    var glass_groups := 0
    var glass_distinct := {}
    for child: Node in details.get_children():
        if not child.name.begins_with("CorridorShopfrontGlass") or not child is MultiMeshInstance3D:
            continue
        var glass_node := child as MultiMeshInstance3D
        var mm := glass_node.multimesh
        if mm == null or mm.instance_count < 1:
            continue
        var box_mesh := mm.mesh as BoxMesh
        if box_mesh == null:
            _fail("shopfront glass group does not use expected low-cost BoxMesh")
            return
        var material := box_mesh.material as StandardMaterial3D
        if material == null:
            _fail("shopfront glass group has no StandardMaterial3D")
            return
        var color := material.albedo_color
        if color.r < 0.025 or color.g < 0.045 or color.b < 0.055 or color.r > 0.16 or color.g > 0.20 or color.b > 0.24:
            _fail("shopfront glass tint escaped restrained bounds: %s" % _color_key(color))
            return
        if material.roughness < 0.14 or material.roughness > 0.34:
            _fail("shopfront glass roughness escaped restrained bounds: %.3f" % material.roughness)
            return
        if material.metallic < 0.08 or material.metallic > 0.30:
            _fail("shopfront glass reflectance escaped restrained bounds: %.3f" % material.metallic)
            return
        glass_distinct[_color_key(color)] = true
        glass_total += mm.instance_count
        glass_groups += 1
        _add_transform_counts(glass_transforms, mm)

    if shopfront_node.visible:
        _fail("uniform baseline shopfront glass must be hidden after exact replacement")
        return
    if glass_total != shopfronts:
        _fail("replacement glass must preserve every shopfront; shops=%d glass=%d" % [shopfronts, glass_total])
        return
    if glass_groups < 3 or glass_distinct.size() < 3:
        _fail("shopfront glass remains too synchronized; groups=%d distinct_tints=%d" % [glass_groups, glass_distinct.size()])
        return
    if source_transforms != glass_transforms:
        _fail("shopfront glass replacement changed or lost source transforms")
        return

    var window_source_transforms := {}
    _add_transform_counts(window_source_transforms, window_node.multimesh)
    var window_glass_transforms := {}
    var window_glass_total := 0
    var window_glass_groups := 0
    var window_glass_distinct := {}
    for child: Node in details.get_children():
        if not child.name.begins_with("CorridorWindowGlass") or not child is MultiMeshInstance3D:
            continue
        var window_glass_node := child as MultiMeshInstance3D
        var mm := window_glass_node.multimesh
        if mm == null or mm.instance_count < 1:
            continue
        var box_mesh := mm.mesh as BoxMesh
        if box_mesh == null:
            _fail("window glass group does not use expected low-cost BoxMesh")
            return
        var material := box_mesh.material as StandardMaterial3D
        if material == null:
            _fail("window glass group has no StandardMaterial3D")
            return
        var color := material.albedo_color
        if color.r < 0.035 or color.g < 0.055 or color.b < 0.065 or color.r > 0.15 or color.g > 0.18 or color.b > 0.21:
            _fail("window glass tint escaped restrained bounds: %s" % _color_key(color))
            return
        if material.roughness < 0.18 or material.roughness > 0.38:
            _fail("window glass roughness escaped restrained bounds: %.3f" % material.roughness)
            return
        if material.metallic < 0.06 or material.metallic > 0.24:
            _fail("window glass reflectance escaped restrained bounds: %.3f" % material.metallic)
            return
        window_glass_distinct[_color_key(color)] = true
        window_glass_total += mm.instance_count
        window_glass_groups += 1
        _add_transform_counts(window_glass_transforms, mm)

    if window_node.visible:
        _fail("uniform baseline window glass must be hidden after exact replacement")
        return
    if window_glass_total != windows:
        _fail("replacement window glass must preserve every window; windows=%d glass=%d" % [windows, window_glass_total])
        return
    if window_glass_groups < 4 or window_glass_distinct.size() < 4:
        _fail("upper window glass remains too synchronized; groups=%d distinct_tints=%d" % [window_glass_groups, window_glass_distinct.size()])
        return
    if window_source_transforms != window_glass_transforms:
        _fail("window glass replacement changed or lost source transforms")
        return

    print("CORRIDOR_FACADE_DEPTH_OK windows=%d lintels=%d sills=%d jambs=%d trim_groups=%d trim_colors=%d window_glass=%d window_groups=%d window_tints=%d shopfronts=%d canopies=%d canopy_groups=%d canopy_colors=%d canopy_depths=%d glass=%d glass_groups=%d glass_tints=%d" % [windows, lintels, sills, jambs, lintel_stats.groups, lintel_stats.colors, window_glass_total, window_glass_groups, window_glass_distinct.size(), shopfronts, canopy_total, canopy_groups, canopy_distinct.size(), canopy_depths.size(), glass_total, glass_groups, glass_distinct.size()])
    scene.queue_free()
    quit(0)
