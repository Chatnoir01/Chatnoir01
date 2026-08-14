extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT_DIR := "res://artifacts/grand-place/townhall-slate-roof"
const SOURCE_PATH := "res://data/visual/grand_place_1655673_roof_identity.json"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(365.0, 1.72, -505.0)
const CAMERA_TARGET := Vector3(279.5, 38.0, -515.0)
const CAMERA_FOV := 64.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWNHALL_SLATE_ROOF_FAIL: %s" % message)
    quit(1)

func _capture(path: String) -> bool:
    for _frame: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _hide_noise(main: Node) -> void:
    for name_value: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls", "PrototypeLabel"]:
        var node := main.get_node_or_null(name_value)
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    for path: String in ["Player", "PrototypeCar", "TrafficManager", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node is Node3D:
            (node as Node3D).visible = false

func _run() -> void:
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("roof identity provenance missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("roof identity provenance invalid")
        return
    var data: Dictionary = parsed
    var source: Dictionary = data.get("material_identity_source", {})
    var contract: Dictionary = data.get("presentation_contract", {})
    if str(source.get("record", "")) != "Hotel de ville, Grand-Place 8, Urban 31125":
        _fail("heritage record drifted")
        return
    if str(source.get("fact", "")) != "vast slate gable roof pierced by four rows of hipped dormers":
        _fail("slate roof fact drifted")
        return
    if bool(contract.get("geometry_changed", true)) or bool(contract.get("dormers_authored", true)):
        _fail("source/presentation boundary drifted")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(16):
        await process_frame
    _hide_noise(main)

    var townhall := root.get_node_or_null("GrandPlaceOfficialLod2")
    if townhall == null or not townhall.has_method("set_sourced_roof_material"):
        _fail("Town Hall sourced roof material interface missing")
        return

    var camera := Camera3D.new()
    camera.fov = CAMERA_FOV
    camera.position = CAMERA_POSITION
    root.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    townhall.call("set_sourced_roof_material", false)
    if not await _capture(OUTPUT_DIR + "/before.png"):
        _fail("before capture failed")
        return
    townhall.call("set_sourced_roof_material", true)
    if not bool(townhall.call("sourced_roof_material_enabled")):
        _fail("sourced roof material did not enable")
        return
    if not await _capture(OUTPUT_DIR + "/after.png"):
        _fail("after capture failed")
        return

    print("GRAND_PLACE_TOWNHALL_SLATE_ROOF_OK")
    quit(0)
