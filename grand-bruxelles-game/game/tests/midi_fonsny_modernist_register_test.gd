extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const PROVENANCE := "res://docs/provenance/midi_fonsny_modernist_register.json"
const BLOCKS := ["FonsnyWingSouth", "FonsnyCentral", "FonsnyWingNorth"]

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    assert(packed != null, "main scene must load")
    var world := packed.instantiate()
    get_root().add_child(world)
    await process_frame

    var station := world.get_node_or_null("MidiHeroZone/BruxellesMidiStation") as Node3D
    assert(station != null, "Midi station hero must exist")
    var total_windows := 0
    for block_name: String in BLOCKS:
        var block := station.get_node_or_null(block_name) as Node3D
        assert(block != null, "missing Fonsny office block: " + block_name)
        var window_count := 0
        for child in block.get_children():
            if child is MeshInstance3D and String(child.name).begins_with("Window_"):
                window_count += 1
        assert(window_count > 0, block_name + " must retain existing source-informed window openings")
        total_windows += window_count

        var register := block.get_node_or_null("ModernistFacadeRegister") as Node3D
        assert(register != null, block_name + " must receive the reusable modernist register")
        var sunshades := register.get_node_or_null("Sunshades") as MultiMeshInstance3D
        var transoms := register.get_node_or_null("Transoms") as MultiMeshInstance3D
        var vertical_frames := register.get_node_or_null("VerticalFrames") as MultiMeshInstance3D
        var bottom_rails := register.get_node_or_null("BottomRails") as MultiMeshInstance3D
        assert(sunshades != null and sunshades.multimesh != null, "sunshade register missing")
        assert(transoms != null and transoms.multimesh != null, "transom register missing")
        assert(vertical_frames != null and vertical_frames.multimesh != null, "aluminium vertical-frame register missing")
        assert(bottom_rails != null and bottom_rails.multimesh != null, "aluminium bottom-rail register missing")
        assert(sunshades.multimesh.instance_count == window_count, "one sunshade per existing opening")
        assert(transoms.multimesh.instance_count == window_count, "one transom per existing opening")
        assert(vertical_frames.multimesh.instance_count == window_count * 2, "two aluminium jambs per existing opening")
        assert(bottom_rails.multimesh.instance_count == window_count, "one lower aluminium rail per existing opening")
        assert(bool(register.get_meta("source_geometry_unchanged", false)), "module must preserve source-informed massing")
        assert(bool(register.get_meta("authored_dimensions_not_measured", false)), "authored dimensions must remain explicit")

        var relief := register.get_node_or_null("ProjectingBrickSpandrels") as MultiMeshInstance3D
        if block_name == "FonsnyCentral":
            assert(relief != null and relief.multimesh != null, "no. 47 centre body must carry source-backed projecting-brick spandrel relief")
            assert(relief.multimesh.instance_count == window_count, "relief cadence must derive from existing openings")
        else:
            assert(relief == null, "projecting-brick relief must not be generalized to undocumented wings")

    assert(total_windows >= 300, "frontage treatment must remain a broad normal-player cue, not a micro patch")

    assert(FileAccess.file_exists(PROVENANCE), "provenance manifest missing")
    var raw := FileAccess.get_file_as_string(PROVENANCE)
    var parsed: Variant = JSON.parse_string(raw)
    assert(parsed is Dictionary, "provenance must parse")
    var data := parsed as Dictionary
    assert(int((data.get("source", {}) as Dictionary).get("urban_id", 0)) == 9423, "heritage Urban ID must remain pinned")
    assert(String(data.get("asset_family", "")) == "brussels_modernist_window_register", "reusable asset family identity must remain pinned")

    world.queue_free()
    await process_frame
    print("Midi Fonsny modernist register regression: PASS windows=%d" % total_windows)
    quit(0)
