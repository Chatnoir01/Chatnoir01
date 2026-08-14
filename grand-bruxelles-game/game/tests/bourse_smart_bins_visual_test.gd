extends SceneTree

const RUNTIME_PATH := "res://game/scripts/bourse_smart_bins_visual.gd"
const SOURCE_PATH := "res://data/provenance/bourse_smart_bins.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SMART_BINS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("runtime asset family missing")
        return
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("official placement provenance missing")
        return
    var runtime_script: Script = load(RUNTIME_PATH)
    var bins: Node = runtime_script.new()
    root.add_child(bins)
    await process_frame
    if int(bins.get("source_bin_count")) != 7:
        _fail("expected 7 source-backed Bourse-area placements")
        return
    if int(bins.get("rendered_bin_count")) != 7:
        _fail("expected every source-backed placement to render")
        return
    if not bool(bins.get("source_locations_are_official")):
        _fail("official-location contract missing")
        return
    if not bool(bins.get("visual_dimensions_are_authored")):
        _fail("authored-dimensions disclaimer missing")
        return
    if not bool(bins.get("contains_bourse_stairs_pair")):
        _fail("Bourse stair pair missing")
        return
    if float(bins.get("min_solar_panel_area_m2")) <= 0.12:
        _fail("solar-panel silhouette too small to read")
        return
    print("BOURSE_SMART_BINS_OK: source=%d rendered=%d stairs_pair=%s authored=%s" % [int(bins.get("source_bin_count")), int(bins.get("rendered_bin_count")), str(bins.get("contains_bourse_stairs_pair")), str(bins.get("visual_dimensions_are_authored"))])
    quit(0)
