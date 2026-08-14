class_name StibSuedeRuntime
extends Node3D

## Runtime-first visualization of the official STIB/MIVB Suède / Zweden stop point.
## Source truth is limited to stop identity + CRS84 point. The physical marker below
## is an authored, logo-free visualization of that data point; it is NOT a surveyed
## shelter, timetable, service pattern, vehicle schedule or furniture reconstruction.

const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")

const stop_id: String = "2539"
const name_fr: String = "Suède"
const name_nl: String = "Zweden"
const source_crs84 := Vector2(4.33581842, 50.83409624)
const stop_anchor := Vector3(-856.297, 0.16, 868.715)

# Existing production Fonsny alignment. These vectors only orient the authored
# runtime presentation and waiting queue; they do not claim surveyed stop furniture.
const FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

var transit_stop: NpcTransitStop = null
var waiting_agents: Array[NpcAgent] = []
var visual_built: bool = false

func _ready() -> void:
    if transit_stop != null:
        return
    global_position = Vector3.ZERO
    _build_identity()
    _build_waiting_runtime()

func _build_identity() -> void:
    var root_node := Node3D.new()
    root_node.name = "StopIdentity"
    root_node.position = stop_anchor
    root_node.rotation.y = atan2(-FONSNY_AXIS.x, -FONSNY_AXIS.z)
    add_child(root_node)

    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.12, 0.14, 0.17, 1.0)
    metal.roughness = 0.72
    metal.metallic = 0.48

    var panel_material := StandardMaterial3D.new()
    panel_material.albedo_color = Color(0.075, 0.19, 0.36, 1.0)
    panel_material.roughness = 0.62

    var accent_material := StandardMaterial3D.new()
    accent_material.albedo_color = Color(0.78, 0.08, 0.09, 1.0)
    accent_material.roughness = 0.68

    _box(root_node, "SourcePointPole", Vector3(0.10, 2.75, 0.10), Vector3(0.0, 1.375, 0.0), metal)
    _box(root_node, "IdentityPanel", Vector3(1.48, 0.92, 0.09), Vector3(0.0, 2.52, 0.0), panel_material)
    _box(root_node, "BilingualAccent", Vector3(1.48, 0.10, 0.105), Vector3(0.0, 2.99, 0.0), accent_material)

    var label := Label3D.new()
    label.name = "BilingualStopName"
    label.text = "SUÈDE\nZWEDEN"
    label.font_size = 84
    label.pixel_size = 0.0066
    label.modulate = Color(0.98, 0.98, 0.97, 1.0)
    label.outline_size = 6
    label.outline_modulate = Color(0.02, 0.03, 0.05, 0.9)
    label.position = Vector3(0.0, 2.52, -0.052)
    label.rotation_degrees.y = 180.0
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    root_node.add_child(label)

    visual_built = true

func _build_waiting_runtime() -> void:
    transit_stop = NpcTransitStop.new()
    # One behavioral queue anchor is sufficient until a real vehicle exposes a
    # door. No vehicle arrival/capacity/service semantics are authored here.
    transit_stop.configure(
        stop_id,
        stop_anchor + FONSNY_AXIS * 1.25,
        FONSNY_AXIS,
        -FONSNY_AXIS,
        PackedFloat32Array([0.0]),
        0.90,
        6
    )

    for index in range(3):
        var passenger_id := 925390 + index
        var agent := NpcAgent.new()
        agent.name = "SuedeWaitingPassenger_%02d" % index
        agent.role = NpcBehaviorModel.Role.CIVILIAN
        agent.variation_seed = 540 + index * 17
        agent.position = stop_anchor - FONSNY_AXIS * (1.1 + float(index) * 0.95) + ROAD_SIDE * 0.35
        agent.add_to_group("living_city_agent")
        agent.add_to_group("stib_suede_waiting")
        agent.set_meta("source_anchor", "stib_stop_2539_suede_zweden")
        agent.set_meta("source_bounded_runtime", true)

        var visual := HUMANOID_VISUAL_SCRIPT.new() as Node3D
        visual.name = "VisibleHumanoid"
        visual.position.y = 0.90
        agent.add_child(visual)
        add_child(agent)
        agent.set_observer_position(stop_anchor)
        if agent.join_transit_stop(transit_stop, passenger_id, 0) < 0:
            push_error("STIB_SUEDE_RUNTIME: failed to join passenger %d" % passenger_id)
        waiting_agents.append(agent)

func _box(parent: Node3D, node_name: String, size: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position_value
    instance.material_override = material
    parent.add_child(instance)
    return instance
