extends "res://game/tests/midi_automatic_road_direct_spawn_witness_test_base.gd"

# JSON.parse_string may materialize numeric IDs as Variant numeric values whose
# concrete type differs from Array[int].  The witness must compare OSM IDs by
# validated integral numeric value, not Variant type identity.
func _runtime_index_source_sha(candidate_ids: Array[int]) -> String:
    const INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
    const SOURCE_RELATIVE := "data/osm/vertical_slice_01.game.json"
    const INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
    if not FileAccess.file_exists(INDEX_PATH):
        return ""
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
    if not parsed is Dictionary:
        return ""
    var index := parsed as Dictionary
    if str(index.get("format", "")) != INDEX_FORMAT or not bool(index.get("source_lookup_only", false)):
        return ""
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary or not bool((authorization as Dictionary).get("source_lookup_only", false)):
        return ""
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool((authorization as Dictionary).get(forbidden, true)):
            return ""
    var documents: Variant = index.get("documents", [])
    if not documents is Array:
        return ""
    for raw_document: Variant in documents:
        if not raw_document is Dictionary:
            continue
        var descriptor := raw_document as Dictionary
        if str(descriptor.get("path", "")) != SOURCE_RELATIVE:
            continue
        var road_ids: Variant = descriptor.get("road_ids", [])
        var expected_sha := str(descriptor.get("sha256", "")).strip_edges().to_lower()
        if expected_sha.length() != 64 or not road_ids is Array:
            return ""
        for candidate_id: int in candidate_ids:
            if not _contains_osm_id(road_ids, candidate_id):
                return ""
        return expected_sha
    return ""
