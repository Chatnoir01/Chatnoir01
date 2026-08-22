extends SceneTree

const CONTOUR_RUNTIME := preload("res://game/scripts/grand_place_complete_contour_runtime.gd")
const BOUNDS := Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
const HALO_POSITION := Vector3(3.5, 1.0, 0.0)

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
    var output_path := str(args[1])

    root.size = Vector2i(640, 360)
    var scene := Node3D.new()
    scene.name = "MaskHaloWitness"
    root.add_child(scene)
    current_scene = scene

    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene.add_child(osm)
    var generated := Node3D.new()
    generated.name = "GeneratedBuildings"
    osm.add_child(generated)

    # Exact authoritative horizontal footprint: x/z = [-1, 1].
    # The cyan candidate is 2.5 m outside that footprint: it was incorrectly
    # swallowed by the old 3 m halo, but must survive the exact 0 m mask.
    var footprint := _box("AuthoritativeFootprint", Vector3(2.0, 0.10, 2.0), Vector3(0.0, 0.0, 0.0), Color(0.30, 0.32, 0.35, 1.0))
    scene.add_child(footprint)
    var inside := _box("InsideCandidate", Vector3(0.8, 2.0, 0.8), Vector3(0.0, 1.0, 0.0), Color(0.85, 0.20, 0.16, 1.0))
    generated.add_child(inside)
    var halo := _box("OutsideHaloCandidate", Vector3(0.8, 2.0, 0.8), HALO_POSITION, Color(0.10, 0.80, 0.95, 1.0))
    generated.add_child(halo)
    var far_reference := _box("FarReference", Vector3(0.8, 2.0, 0.8), Vector3(-4.0, 1.0, 0.0), Color(0.95, 0.75, 0.12, 1.0))
    scene.add_child(far_reference)

    var runtime := CONTOUR_RUNTIME.new()
    runtime.call("_mask_replaced_osm", "fixture-owner", BOUNDS, scene)

    if inside.visible:
        _fail("anchor inside exact UrbIS bounds was not masked")
        return
    if halo.visible != expected_halo_visible:
        _fail("2.5 m outside-footprint anchor visibility=%s expected=%s" % [halo.visible, expected_halo_visible])
        return
    if expected_halo_visible and halo.has_meta("replaced_by_urbis_building"):
        _fail("outside-footprint anchor received replacement ownership metadata")
        return
    if not expected_halo_visible and not halo.has_meta("replaced_by_urbis_building"):
        _fail("legacy 3 m reproducer did not tag the outside-footprint anchor")
        return

    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
    light.light_energy = 1.4
    scene.add_child(light)
    var camera := Camera3D.new()
    camera.position = Vector3(4.5, 7.0, 12.0)
    camera.fov = 52.0
    scene.add_child(camera)
    camera.look_at(Vector3(0.3, 0.8, 0.0), Vector3.UP)
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
    print("GRAND_PLACE_OSM_MASK_HALO_CAPTURE_OK: expected=%s actual=%s outside_distance_m=2.5 masked=%d output=%s" % [str(args[0]), halo.visible, int(runtime.get("masked_osm_count")), output_path])
    quit(0)
