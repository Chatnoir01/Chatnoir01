extends SceneTree

const CONTOUR_RUNTIME := preload("res://game/scripts/grand_place_complete_contour_runtime.gd")
const SOURCE_OWNER_ID := "1601883"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const OUTSIDE_DISTANCE_M := 2.5

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_OSM_MASK_HALO_CAPTURE_FAIL: " + message)
    quit(1)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.82
    return material

func _box(name_value: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = position
    instance.material_override = _material(color)
    return instance

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2 or str(args[0]) not in ["hidden", "visible"]:
        _fail("usage: -- <hidden|visible> <output.png>")
        return
    var expected_halo_visible := str(args[0]) == "visible"
    var expected_halo_masked := not expected_halo_visible
    var output_path := str(args[1])

    var runtime := CONTOUR_RUNTIME.new()
    var source_data: Dictionary = runtime.call("_read_owner", SOURCE_OWNER_ID)
    if source_data.is_empty():
        _fail("official UrbIS owner %s did not pass runtime source validation" % SOURCE_OWNER_ID)
        return
    var source: Dictionary = source_data.get("source", {})
    var expected_identity := "https://databrussels.be/id/building/%s" % SOURCE_OWNER_ID
    if str(source.get("building_2d_id", "")) != expected_identity:
        _fail("source building identity drifted")
        return
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        _fail("source CRS/license drifted")
        return
    if str(source.get("package_sha256", "")) != PACKAGE_SHA256:
        _fail("source package digest drifted")
        return

    var faces: Array = source_data.get("faces", [])
    var bounds: Rect2 = runtime.call("_horizontal_bounds", faces)
    if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
        _fail("official UrbIS owner produced empty horizontal bounds")
        return
    var center_xz := bounds.get_center()
    var inside_position := Vector3(center_xz.x, 1.0, center_xz.y)
    var halo_position := Vector3(bounds.end.x + OUTSIDE_DISTANCE_M, 1.0, center_xz.y)
    var far_position := Vector3(bounds.position.x - 4.0, 1.0, center_xz.y)

    root.size = Vector2i(640, 360)
    var scene := Node3D.new()
    scene.name = "MaskHaloWitness"
    root.add_child(scene)
    current_scene = scene

    # In-tree but deliberately non-canonical probe: transforms/global_position are valid,
    # while production discovery cannot mistake this nested topology for the real scene root.
    var probe_scene := Node3D.new()
    probe_scene.name = "DetachedMaskProbe"
    scene.add_child(probe_scene)
    var probe_osm := Node3D.new()
    probe_osm.name = "BrusselsOSM"
    probe_scene.add_child(probe_osm)
    var probe_generated := Node3D.new()
    probe_generated.name = "GeneratedBuildings"
    probe_osm.add_child(probe_generated)
    var probe_inside := Node3D.new()
    probe_inside.name = "InsideCandidate"
    probe_inside.position = inside_position
    probe_generated.add_child(probe_inside)
    var probe_halo := Node3D.new()
    probe_halo.name = "OutsideHaloCandidate"
    probe_halo.position = halo_position
    probe_generated.add_child(probe_halo)

    runtime.call("_mask_replaced_osm", SOURCE_OWNER_ID, bounds, probe_scene)
    var inside_masked := probe_inside.has_meta("replaced_by_urbis_building")
    var halo_masked := probe_halo.has_meta("replaced_by_urbis_building")
    if not inside_masked:
        _fail("anchor inside exact UrbIS bounds was not masked")
        return
    if halo_masked != expected_halo_masked:
        _fail("2.5 m outside-footprint anchor masked=%s expected=%s" % [halo_masked, expected_halo_masked])
        return
    var expected_masked_count := 2 if expected_halo_masked else 1
    if int(runtime.get("masked_osm_count")) != expected_masked_count:
        _fail("in-tree non-canonical probe masked count=%d expected=%d" % [int(runtime.get("masked_osm_count")), expected_masked_count])
        return

    # Separate render witness: it mirrors the proven probe state but deliberately does not
    # expose BrusselsOSM/GeneratedBuildings directly under current_scene.
    var witness_buildings := Node3D.new()
    witness_buildings.name = "WitnessBuildings"
    scene.add_child(witness_buildings)

    var footprint := _box("AuthoritativeFootprintBounds", Vector3(bounds.size.x, 0.10, bounds.size.y), Vector3(center_xz.x, 0.0, center_xz.y), Color(0.30, 0.32, 0.35, 1.0))
    scene.add_child(footprint)
    var inside := _box("InsideCandidate", Vector3(0.8, 2.0, 0.8), inside_position, Color(0.85, 0.20, 0.16, 1.0))
    inside.visible = not inside_masked
    witness_buildings.add_child(inside)
    var halo := _box("OutsideHaloCandidate", Vector3(0.8, 2.0, 0.8), halo_position, Color(0.10, 0.80, 0.95, 1.0))
    halo.visible = not halo_masked
    witness_buildings.add_child(halo)
    var far_reference := _box("FarReference", Vector3(0.8, 2.0, 0.8), far_position, Color(0.95, 0.75, 0.12, 1.0))
    scene.add_child(far_reference)

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
    light.light_energy = 1.4
    scene.add_child(light)
    var camera := Camera3D.new()
    var span := maxf(bounds.size.x, bounds.size.y)
    var view_distance := maxf(12.0, span * 1.35)
    camera.position = Vector3(center_xz.x + span * 0.15, maxf(7.0, span * 0.55), center_xz.y + view_distance)
    camera.fov = 52.0
    scene.add_child(camera)
    camera.look_at(Vector3(center_xz.x + 1.0, 0.8, center_xz.y), Vector3.UP)
    camera.current = true

    for _frame: int in range(8):
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("renderer returned no image")
        return
    var error := image.save_png(output_path)
    if error != OK:
        _fail("could not save PNG: %s" % error)
        return
    print("GRAND_PLACE_OSM_MASK_HALO_CAPTURE_OK: owner=%s source=%s crs=%s license=%s bounds=(%.3f,%.3f %.3fx%.3f) expected=%s halo_masked=%s outside_distance_m=%.1f masked=%d output=%s" % [SOURCE_OWNER_ID, expected_identity, str(source.get("crs", "")), str(source.get("license", "")), bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y, str(args[0]), halo_masked, OUTSIDE_DISTANCE_M, int(runtime.get("masked_osm_count")), output_path])
    probe_scene.free()
    quit(0)
