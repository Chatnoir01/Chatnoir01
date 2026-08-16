extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_DATA := "res://data/urbis/anneessens/place_identity.game.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_PLACE_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame in range(12):
        await process_frame

    var identity := root.get_node_or_null("AnneessensPlaceIdentity")
    if identity == null:
        _fail("production Anneessens identity runtime missing")
        return
    if not FileAccess.file_exists(SOURCE_DATA):
        _fail("official Anneessens source slice missing")
        return
    if not bool(identity.get("source_loaded")):
        _fail("official Anneessens source slice did not load")
        return
    if str(identity.get_meta("placement_semantics", "")) != "official_surface_centroid_containing_production_anchor":
        _fail("monument placement semantics drifted")
        return
    if str(identity.get_meta("heritage_record", "")) != "Place Anneessens / Urban 10003005":
        _fail("heritage identity source drifted")
        return
    if bool(identity.get_meta("dimensions_surveyed", true)):
        _fail("authored monument dimensions must never be claimed as surveyed")
        return
    print("ANNEESSENS_PLACE_IDENTITY_OK")
    quit(0)
