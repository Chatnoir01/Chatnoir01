extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/civilian_vehicle_visual.gd")
const TRAFFIC_MANAGER_SCRIPT := preload("res://game/scripts/traffic_manager_npc_crossing_extension.gd")

const REQUIRED_PARTS := [
    "BodyShell",
    "GlassHouse",
    "RoofCap",
    "FrontBumper",
    "RearBumper",
    "FrontGrille",
    "MirrorLeft",
    "MirrorRight",
    "WheelFL",
    "WheelFR",
    "WheelRL",
    "WheelRR",
]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("REAL_CIVILIAN_VEHICLE_VISUAL_FAIL: %s" % message)
    quit(1)


func _mesh_count(node: Node) -> int:
    var total := 1 if node is MeshInstance3D else 0
    for child: Node in node.get_children():
        total += _mesh_count(child)
    return total


func _vertex_count(mesh_instance: MeshInstance3D) -> int:
    if mesh_instance == null or mesh_instance.mesh == null:
        return 0
    var total := 0
    for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
        var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
        if arrays.size() <= Mesh.ARRAY_VERTEX:
            continue
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        total += vertices.size()
    return total


func _assert_style(style: int, expected_name: String) -> bool:
    var host := Node3D.new()
    root.add_child(host)
    var visual := VISUAL_SCRIPT.new()
    visual.body_style = style
    host.add_child(visual)
    await process_frame

    if not visual.has_method("get_visual_contract"):
        _fail("visual contract API is missing")
        return false
    var contract: Dictionary = visual.call("get_visual_contract")
    if str(contract.get("quality", "")) != "realistic_european_car_v3":
        _fail("quality contract is not v3 for style %d" % style)
        return false
    if int(contract.get("body_stations", 0)) < 14:
        _fail("body needs at least 14 longitudinal shaping stations")
        return false
    if int(contract.get("ring_vertices", 0)) < 10:
        _fail("body cross-section needs at least 10 vertices for rounded shoulders")
        return false
    if str(contract.get("body_style", "")) != expected_name:
        _fail("wrong body style identity for style %d" % style)
        return false
    if float(contract.get("length_m", 0.0)) < 4.0 or float(contract.get("length_m", 0.0)) > 4.7:
        _fail("vehicle length is outside realistic compact European range")
        return false
    if float(contract.get("width_m", 0.0)) < 1.7 or float(contract.get("width_m", 0.0)) > 1.95:
        _fail("vehicle width is outside realistic compact European range")
        return false

    for required_name: String in REQUIRED_PARTS:
        if visual.get_node_or_null(required_name) == null:
            _fail("missing detailed part %s on %s" % [required_name, expected_name])
            return false

    var mesh_parts := _mesh_count(visual)
    if mesh_parts < 34:
        _fail("%s is still too primitive: only %d mesh parts" % [expected_name, mesh_parts])
        return false
    if mesh_parts > 66:
        _fail("%s uses too many draw-bearing mesh nodes: %d (>66)" % [expected_name, mesh_parts])
        return false

    var body := visual.get_node_or_null("BodyShell") as MeshInstance3D
    var glass := visual.get_node_or_null("GlassHouse") as MeshInstance3D
    var body_vertices := _vertex_count(body)
    var glass_vertices := _vertex_count(glass)
    if body_vertices < 420:
        _fail("%s body shell is still low density: %d vertices (<420)" % [expected_name, body_vertices])
        return false
    if glass_vertices < 240:
        _fail("%s glass house is still low density: %d vertices (<240)" % [expected_name, glass_vertices])
        return false

    for wheel_name: String in ["WheelFL", "WheelFR", "WheelRL", "WheelRR"]:
        var wheel := visual.get_node(wheel_name)
        var tire := wheel.get_node_or_null("Tire") as MeshInstance3D
        var rim := wheel.get_node_or_null("Rim") as MeshInstance3D
        var disc := wheel.get_node_or_null("BrakeDisc") as MeshInstance3D
        var caliper := wheel.get_node_or_null("BrakeCaliper") as MeshInstance3D
        var spoke_star := wheel.get_node_or_null("SpokeStar") as MeshInstance3D
        if tire == null or rim == null or disc == null or caliper == null:
            _fail("%s lacks tire/rim/brake/caliper detail" % wheel_name)
            return false
        if not tire.mesh is TorusMesh:
            _fail("%s tire must use a rounded torus sidewall, not a solid cylinder" % wheel_name)
            return false
        if not rim.mesh is TorusMesh:
            _fail("%s rim must be open so brake detail remains visible" % wheel_name)
            return false
        if spoke_star == null or _vertex_count(spoke_star) < 30:
            _fail("%s must consolidate five alloy spokes into one radial mesh" % wheel_name)
            return false
        for spoke_index: int in range(5):
            if wheel.get_node_or_null("Spoke%d" % spoke_index) != null:
                _fail("%s still uses separate spoke mesh nodes instead of one optimized star" % wheel_name)
                return false

    host.queue_free()
    await process_frame
    return true


func _run() -> void:
    if not await _assert_style(0, "sedan"):
        return
    if not await _assert_style(1, "hatchback"):
        return
    if not await _assert_style(2, "wagon"):
        return

    var manager := TRAFFIC_MANAGER_SCRIPT.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    manager.scooter_share = 0.0
    manager.motorcycle_share = 0.0
    manager.official_density_enabled = false
    root.add_child(manager)
    await process_frame

    var traffic_vehicle: Node3D = manager.call("_create_vehicle_node") as Node3D
    root.add_child(traffic_vehicle)
    await process_frame
    var upgrade := traffic_vehicle.get_node_or_null("VisualUpgrade")
    if upgrade == null or upgrade.get_script() != VISUAL_SCRIPT:
        _fail("moving traffic cars are not wired to the realistic visual builder")
        return
    var legacy_body := traffic_vehicle.get_node_or_null("Body") as VisualInstance3D
    var legacy_cabin := traffic_vehicle.get_node_or_null("Cabin") as VisualInstance3D
    if legacy_body == null or legacy_cabin == null or legacy_body.visible or legacy_cabin.visible:
        _fail("legacy traffic box body/cabin must remain hidden after the realistic upgrade")
        return

    print("REAL_CIVILIAN_VEHICLE_VISUAL_OK: v3 dense shells + open optimized alloy wheels; moving traffic wired")
    quit(0)
