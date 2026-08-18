extends SceneTree

const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_PATH := "res://game/scripts/brussels_osm_marking_truth_runtime.gd"
const POLICY_FAMILY := "brussels_osm_marking_truth_v1"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_MARKING_TRUTH_FAIL: %s" % message)
    quit(1)

func _init() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("OSM runtime slice missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("OSM runtime slice invalid")
        return
    var data := parsed as Dictionary
    var roads: Array = data.get("roads", [])
    if roads.is_empty():
        _fail("OSM road slice empty")
        return
    var unsupported_fields := ["lanes", "turn:lanes", "lane_markings", "marking", "divider", "centre_line", "center_line"]
    for raw: Variant in roads:
        if typeof(raw) != TYPE_DICTIONARY:
            _fail("road entry is not a dictionary")
            return
        var road := raw as Dictionary
        for field: String in unsupported_fields:
            if road.has(field):
                _fail("unexpected marking evidence field present: %s" % field)
                return
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("reusable marking-truth runtime missing")
        return
    var runtime_text := FileAccess.get_file_as_string(RUNTIME_PATH)
    if not runtime_text.contains(POLICY_FAMILY):
        _fail("runtime policy family missing")
        return
    if not runtime_text.contains("source_backed_lane_marking"):
        _fail("runtime does not require explicit source-backed marking metadata")
        return
    print("BRUSSELS_OSM_MARKING_TRUTH_OK: roads=%d retained_marking_fields=0 family=%s" % [roads.size(), POLICY_FAMILY])
    quit(0)
