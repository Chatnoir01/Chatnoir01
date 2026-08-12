extends Node

@export var checkpoint_radius: float = 22.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var car: CharacterBody3D = get_node("../PrototypeCar")
@onready var mission_label: Label = get_node("../MissionLabel")

var _stage: int = 0
var _marker: CSGCylinder3D
var _marker_material: StandardMaterial3D

const MISSION_ID: String = "midi_to_centre_01"
const STATE_SCHEMA_VERSION: int = 1

const CHECKPOINTS: Array[Dictionary] = [
    {
        "name": "Place Anneessens",
        "position": Vector3(-272.04, 0.08, -217.07),
    },
    {
        "name": "Bourse / Beurs",
        "position": Vector3(81.54, 0.08, -664.58),
    },
    {
        "name": "Grand-Place",
        "position": Vector3(319.01, 0.08, -535.20),
    },
]


func _ready() -> void:
    _marker_material = StandardMaterial3D.new()
    _marker_material.albedo_color = Color(1.0, 0.78, 0.08, 0.72)
    _marker_material.emission_enabled = true
    _marker_material.emission = Color(1.0, 0.52, 0.04, 1.0)
    _marker_material.emission_energy_multiplier = 1.5
    _marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    _marker = CSGCylinder3D.new()
    _marker.name = "MissionCheckpoint"
    _marker.radius = 5.5
    _marker.height = 0.12
    _marker.sides = 32
    _marker.material = _marker_material
    _marker.use_collision = false
    _marker.visible = false
    add_child(_marker)
    _update_ui()


func _physics_process(_delta: float) -> void:
    if _stage == 0:
        if bool(car.call("has_driver")):
            _stage = 1
            _update_ui()
        return

    if _stage > CHECKPOINTS.size():
        return

    if not bool(car.call("has_driver")):
        mission_label.text = "MISSION 01 · MIDI → CENTRE\nRemonte dans la voiture · E"
        return

    var target: Dictionary = CHECKPOINTS[_stage - 1]
    var target_position: Vector3 = target["position"]
    var distance: float = car.global_position.distance_to(target_position)
    mission_label.text = (
        "MISSION 01 · MIDI → CENTRE\n%s · %.0f m" %
        [str(target["name"]), distance]
    )

    if distance <= checkpoint_radius:
        _stage += 1
        _update_ui()


func _update_ui() -> void:
    if _stage == 0:
        mission_label.text = "MISSION 01 · MIDI → CENTRE\nMonte dans la voiture · E"
        _marker.visible = false
        return

    if _stage > CHECKPOINTS.size():
        mission_label.text = "MISSION TERMINÉE · BIENVENUE À GRAND-PLACE\nPrototype 0.4 · Bruxelles est ouverte."
        _marker.visible = false
        return

    var target: Dictionary = CHECKPOINTS[_stage - 1]
    _marker.global_position = target["position"]
    _marker.visible = true
    mission_label.text = "MISSION 01 · MIDI → CENTRE\nRejoins %s" % str(target["name"])


func export_state() -> Dictionary:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "mission_id": MISSION_ID,
        "stage": _stage,
        "stage_count": get_stage_count(),
    }


func restore_state(state: Dictionary) -> bool:
    if int(state.get("schema_version", -1)) != STATE_SCHEMA_VERSION:
        return false
    if str(state.get("mission_id", "")) != MISSION_ID:
        return false
    if not state.has("stage"):
        return false

    var restored_stage: int = int(state["stage"])
    if restored_stage < 0 or restored_stage > get_stage_count():
        return false

    _stage = restored_stage
    if is_instance_valid(_marker) and is_instance_valid(mission_label):
        _update_ui()
    return true


func get_mission_id() -> String:
    return MISSION_ID


func get_stage() -> int:
    return _stage


func get_stage_count() -> int:
    return CHECKPOINTS.size() + 1
