extends SceneTree

const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"

var _original_index_text := ""


func _initialize() -> void:
    call_deferred("_run")


func _restore_index() -> void:
    if _original_index_text.is_empty():
        return
    var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(_original_index_text)
        file.close()


func _fail(message: String) -> void:
    _restore_index()
    push_error("AUTOMATIC_ROAD_RUNTIME_INDEX_IDENTITY_FAIL: %s" % message)
    quit(1)


func _mutated_index() -> Dictionary:
    var parsed: Variant = JSON.parse_string(_original_index_text)
    if not parsed is Dictionary:
        _fail("runtime index is not a dictionary")
        return {}
    return parsed as Dictionary


func _write_index(index: Dictionary) -> bool:
    var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
    if file == null:
        _fail("cannot open runtime index for mutation")
        return false
    file.store_string(JSON.stringify(index, "  "))
    file.close()
    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)
    var accepted := resolver._load_runtime_index()
    resolver.free()
    _restore_index()
    return accepted


func _write_mutated_first_id(value: Variant) -> bool:
    var index := _mutated_index()
    var documents: Variant = index.get("documents", [])
    if not documents is Array or documents.is_empty() or not documents[0] is Dictionary:
        _fail("runtime index has no first document")
        return false
    var first_document := documents[0] as Dictionary
    var road_ids: Variant = first_document.get("road_ids", [])
    if not road_ids is Array or road_ids.is_empty():
        _fail("runtime index has no first road id")
        return false
    (road_ids as Array)[0] = value
    first_document["road_ids"] = road_ids
    (documents as Array)[0] = first_document
    index["documents"] = documents
    return _write_index(index)


func _write_mutated_first_path(value: String) -> bool:
    var index := _mutated_index()
    var documents: Variant = index.get("documents", [])
    if not documents is Array or documents.is_empty() or not documents[0] is Dictionary:
        _fail("runtime index has no first document")
        return false
    var first_document := documents[0] as Dictionary
    first_document["path"] = value
    (documents as Array)[0] = first_document
    index["documents"] = documents
    return _write_index(index)


func _run() -> void:
    if not FileAccess.file_exists(INDEX_PATH):
        _fail("runtime index missing")
        return
    _original_index_text = FileAccess.get_file_as_string(INDEX_PATH)
    var original: Variant = JSON.parse_string(_original_index_text)
    if not original is Dictionary:
        _fail("runtime index JSON invalid")
        return
    var documents: Variant = (original as Dictionary).get("documents", [])
    if not documents is Array or documents.is_empty() or not documents[0] is Dictionary:
        _fail("runtime index has no source document")
        return
    var ids: Variant = (documents[0] as Dictionary).get("road_ids", [])
    if not ids is Array or ids.is_empty():
        _fail("runtime index has no road identity")
        return
    var first_id := float((ids as Array)[0])
    if not is_finite(first_id) or first_id <= 0.0 or floor(first_id) != first_id:
        _fail("baseline road identity is not a positive exact JSON integer")
        return

    if _write_mutated_first_id(str(int(first_id))):
        _fail("numeric string road identity was coerced and accepted")
        return
    if _write_mutated_first_id(first_id + 0.5):
        _fail("fractional road identity was truncated and accepted")
        return
    if _write_mutated_first_id(true):
        _fail("boolean road identity was coerced and accepted")
        return
    if _write_mutated_first_path("res://../outside-project.json"):
        _fail("runtime index source path escaped project root")
        return
    if _write_mutated_first_path("../outside-project.json"):
        _fail("relative runtime index source path escaped project root")
        return
    if _write_mutated_first_path("data//osm/vertical_slice_01.game.json"):
        _fail("runtime index source path with duplicate separators was silently canonicalized")
        return
    if _write_mutated_first_path("data/osm/vertical_slice_01.game.json/"):
        _fail("runtime index source path with trailing separator was silently canonicalized")
        return

    _restore_index()
    print("AUTOMATIC_ROAD_RUNTIME_INDEX_IDENTITY_GREEN: numeric_string_rejected=true fractional_rejected=true bool_rejected=true path_traversal_rejected=true ambiguous_separators_rejected=true valid_source_unchanged=true destination_advertisable=false jouable=false")
    quit(0)
