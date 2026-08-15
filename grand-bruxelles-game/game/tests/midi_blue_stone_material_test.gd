extends SceneTree

const EXPECTED_SCRIPT := "res://game/scripts/midi_hero_zone_materials.gd"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    assert(packed != null, "main scene must load")
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame

    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    assert(midi != null, "MidiHeroZone must exist")
    assert(midi.get_script() != null, "MidiHeroZone must have a script")
    assert(midi.get_script().resource_path == EXPECTED_SCRIPT, "MidiHeroZone must use the source-backed material wrapper")

    var station := midi.get_node_or_null("BruxellesMidiStation") as Node3D
    var entrance := midi.get_node_or_null("MidiMainEntranceFonsny") as Node3D
    assert(station != null and entrance != null, "Midi station and Fonsny entrance must exist")

    var station_base := station.get_node_or_null("StationBaseBlueStone") as MeshInstance3D
    var entrance_wall := entrance.get_node_or_null("EntranceBlueStoneWall") as MeshInstance3D
    assert(station_base != null and entrance_wall != null, "blue-stone witness surfaces must exist")

    var base_material := station_base.mesh.material as StandardMaterial3D
    var entrance_material := entrance_wall.mesh.material as StandardMaterial3D
    assert(base_material != null and entrance_material != null, "blue-stone witness materials must exist")
    assert(base_material.get_meta("brussels_material_family", "") == "blue_stone", "station base must expose the blue-stone family")
    assert(entrance_material.get_meta("brussels_material_family", "") == "blue_stone", "entrance device must expose the blue-stone family")
    assert(base_material.get_meta("source_identity", "") == "Midi heritage blue-stone bases and entrance device", "blue-stone placement must retain source identity")
    assert(base_material.get_meta("source_geometry_unchanged", false), "material lot must preserve geometry")
    assert(base_material.get_meta("authored_pbr_values", false), "presentation PBR values must be explicit")
    assert(base_material.get_meta("authored_texture_scale", false), "presentation texture scale must be explicit")
    assert(not base_material.has_meta("source_block_dimensions"), "no unsourced blue-stone block dimensions may be authored")

    world.queue_free()
    await process_frame
    print("Midi blue-stone material regression: PASS")
    quit(0)
