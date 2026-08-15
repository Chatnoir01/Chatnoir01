extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const EXPECTED_SCRIPT := "res://game/scripts/midi_hero_zone_materials.gd"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    assert(packed != null, "main scene must load")
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame

    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    assert(midi != null, "MidiHeroZone must exist")
    assert(midi.get_script() != null and midi.get_script().resource_path == EXPECTED_SCRIPT, "Midi must keep the shared material wrapper")

    var station := midi.get_node_or_null("BruxellesMidiStation") as Node3D
    assert(station != null, "station root must exist")
    for block_name: String in ["FonsnyWingSouth", "FonsnyCentral", "FonsnyWingNorth"]:
        var block := station.get_node_or_null(block_name) as Node3D
        assert(block != null, "office block missing: " + block_name)
        var frames := block.get_node_or_null("AluminiumWindowFrames") as MultiMeshInstance3D
        var transoms := block.get_node_or_null("AluminiumWindowTransoms") as MultiMeshInstance3D
        var shades := block.get_node_or_null("AluminiumSunshades") as MultiMeshInstance3D
        assert(frames != null and transoms != null and shades != null, "source-backed aluminium vocabulary missing on " + block_name)
        var frame_material := frames.multimesh.mesh.material as StandardMaterial3D
        assert(frame_material != null, "aluminium material missing")
        assert(frame_material.get_meta("brussels_material_family", "") == "anodized_aluminium_window", "wrong material family")
        assert(frame_material.get_meta("source_identity", "") == "Midi heritage aluminium window frames and sunshades", "source identity missing")
        assert(frames.multimesh.instance_count > 20, "window vocabulary must cover substantial frontage")

    world.queue_free()
    await process_frame
    print("Midi aluminium window vocabulary regression: PASS")
    quit(0)
