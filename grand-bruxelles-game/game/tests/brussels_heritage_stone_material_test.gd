extends SceneTree

const MATERIALS_PATH := "res://game/scripts/brussels_heritage_stone_materials.gd"
const REFERENCE_PATH := "res://data/visual/brussels_heritage_stone_reference.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_HERITAGE_STONE_FAIL: %s" % message)
    quit(1)

func _close_color(actual: Color, expected: Color, tolerance: float = 0.015) -> bool:
    return absf(actual.r - expected.r) <= tolerance \
        and absf(actual.g - expected.g) <= tolerance \
        and absf(actual.b - expected.b) <= tolerance

func _run() -> void:
    if not ResourceLoader.exists(MATERIALS_PATH):
        _fail("shared material library missing")
        return
    if not FileAccess.file_exists(REFERENCE_PATH):
        _fail("reference/provenance file missing")
        return

    var library_script := load(MATERIALS_PATH)
    if library_script == null:
        _fail("material library did not load")
        return

    var white_stone: StandardMaterial3D = library_script.white_limestone()
    var blue_stone: StandardMaterial3D = library_script.blue_stone()
    if white_stone == null or blue_stone == null:
        _fail("stone materials were not created")
        return
    if not _close_color(white_stone.albedo_color, Color(0.72, 0.70, 0.64, 1.0)):
        _fail("white limestone color contract drifted")
        return
    if white_stone.roughness < 0.80 or white_stone.roughness > 0.92 or white_stone.metallic != 0.0:
        _fail("white limestone PBR response is implausible")
        return
    if not _close_color(blue_stone.albedo_color, Color(0.235, 0.255, 0.27, 1.0)):
        _fail("blue-stone color contract drifted")
        return
    if blue_stone.roughness < 0.78 or blue_stone.roughness > 0.90 or blue_stone.metallic != 0.0:
        _fail("blue-stone PBR response is implausible")
        return

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("reference file is invalid JSON")
        return
    var reference: Dictionary = parsed
    if str(reference.get("schema", "")) != "grand-bruxelles-heritage-stone-reference-v1":
        _fail("reference schema mismatch")
        return
    if not bool(reference.get("authored_materials_only", false)):
        _fail("reference must forbid copied distributable photo textures")
        return
    if not bool(reference.get("bourse_white_stone_source_backed", false)):
        _fail("Bourse white-stone use must be source-backed")
        return

    print("BRUSSELS_HERITAGE_STONE_OK: reusable white-limestone + blue-stone PBR contracts are source-bounded")
    quit(0)
