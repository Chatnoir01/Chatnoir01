extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const EXPECTED_SCRIPT := "res://game/scripts/midi_fonsny_arrival_identity.gd"

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
    assert(midi.get_script() != null and midi.get_script().resource_path == EXPECTED_SCRIPT, "Midi must use Fonsny arrival wrapper")

    var entrance := midi.get_node_or_null("MidiMainEntranceFonsny") as Node3D
    assert(entrance != null, "Fonsny entrance must exist")
    var frame := entrance.get_node_or_null("FonsnyThreeBayArrivalFrame") as Node3D
    assert(frame != null, "source-backed three-bay frame must exist")
    assert(frame.get_node_or_null("BayDivider_1") != null, "first three-bay divider missing")
    assert(frame.get_node_or_null("BayDivider_2") != null, "second three-bay divider missing")
    assert(frame.get_node_or_null("BayCrossRail") != null, "concrete cross rail missing")

    var columns := 0
    for child in entrance.get_children():
        if child is MeshInstance3D and child.name == "EntranceColumn":
            columns += 1
            var column := child as MeshInstance3D
            var material := column.mesh.material as StandardMaterial3D if column.mesh != null else null
            assert(material != null, "porch column material missing")
            assert(material.get_meta("brussels_material_family", "") == "architectural_concrete", "porch columns must reuse shipped #323 concrete identity")
            assert(column.get_meta("geometry_unchanged", false), "column geometry must remain unchanged")
    assert(columns == 4, "existing four authored porch columns must be preserved")

    var glazing := entrance.get_node_or_null("EntranceGlazing") as MeshInstance3D
    assert(glazing != null and glazing.mesh is BoxMesh, "existing entrance glazing must remain")
    var size := (glazing.mesh as BoxMesh).size
    assert(is_equal_approx(size.y, 3.65) and is_equal_approx(size.z, 18.8), "existing authored glazing envelope must not change")

    world.queue_free()
    await process_frame
    print("Midi Fonsny three-bay arrival regression: PASS")
    quit(0)
