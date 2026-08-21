extends Node3D

## City Machine adapter for Midi.
## It deliberately reuses the existing authoritative UrbIS Midi builder and the
## generic OSM environment runtime instead of introducing a second city pipeline.

const MIDI_BUILDER = preload("res://game/scripts/urbis_midi_builder.gd")
const OSM_ENVIRONMENT = preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const OSM_ENVIRONMENT_DATA := "res://data/osm/zones/midi/environment.game.json"

var _official_geometry: Node3D
var _osm_environment: Node3D


func _ready() -> void:
    _make_materials()
    _build_ground_reference()
    _build_official_geometry()
    _build_osm_environment()


func _make_materials() -> void:
    # Material ownership remains in urbis_midi_builder.gd.
    pass


func _build_ground_reference() -> void:
    # No synthetic ground: official UrbIS street surfaces and their collisions
    # are built by the existing Midi builder instantiated below.
    pass


func _build_official_geometry() -> void:
    if is_instance_valid(_official_geometry):
        return
    _official_geometry = MIDI_BUILDER.new()
    _official_geometry.name = "UrbISMidi"
    add_child(_official_geometry)


func _build_osm_environment() -> void:
    if is_instance_valid(_osm_environment):
        return
    _osm_environment = OSM_ENVIRONMENT.new()
    _osm_environment.name = "OSMEnvironment"
    _osm_environment.data_path = OSM_ENVIRONMENT_DATA
    add_child(_osm_environment)
