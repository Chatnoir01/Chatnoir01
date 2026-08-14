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

    var entrance := midi.get_node_or_null("MidiMainEntranceFonsny") as Node3D
    assert(entrance != null, "Fonsny entrance must exist")
    var glazing := entrance.get_node_or_null("EntranceGlazing") as MeshInstance3D
    var canopy := entrance.get_node_or_null("EntranceConcreteCanopy") as MeshInstance3D
    assert(glazing != null and canopy != null, "source-backed entrance witness surfaces must exist")

    var glazing_material := glazing.mesh.material as StandardMaterial3D
    var canopy_material := canopy.mesh.material as StandardMaterial3D
    assert(glazing_material != null and glazing_material.get_meta("brussels_material_family", "") == "glass_block", "entrance glazing must expose the authored glass-block family")
    assert(canopy_material != null and canopy_material.get_meta("brussels_material_family", "") == "architectural_concrete", "entrance canopy must expose the authored concrete family")
    assert(glazing_material.get_meta("source_identity", "") == "Midi heritage glass-block bays", "glass-block placement must retain source identity")
    assert(canopy_material.get_meta("source_identity", "") == "Midi heritage concrete canopy", "concrete placement must retain source identity")

    world.queue_free()
    await process_frame
    print("Midi concrete/glass-block material regression: PASS")
    quit(0)
