extends SceneTree

const CELL_ID := "bxl-e149000-n169000-s500"
const CELL_BBOX := [149000.0, 169000.0, 149500.0, 169500.0]
const MANIFEST_PATH := "res://data/cell_manifests/bxl-e149000-n169000-s500.json"
const SOURCE_ROOT := "res://data/urbis/remaining_brussels/cells/bxl-e149000-n169000-s500/raw"
const REQUIRED_LAYERS := [
    "buildings.geojson",
    "street_surfaces.geojson",
    "street_axes.geojson",
]

func _initialize() -> void:
    var manifest := _read_json(MANIFEST_PATH)
    if manifest.is_empty():
        _fail("cell manifest missing or invalid")
        return
    if str(manifest.get("cell_id", "")) != CELL_ID:
        _fail("wrong cell id")
        return
    if str(manifest.get("crs", "")) != "EPSG:31370":
        _fail("cell CRS drifted")
        return
    var bbox: Array = manifest.get("bbox", [])
    if bbox.size() != 4:
        _fail("cell bbox missing")
        return
    for i in range(4):
        if absf(float(bbox[i]) - CELL_BBOX[i]) > 0.001:
            _fail("cell bbox drifted")
            return
    var maturity: Dictionary = manifest.get("maturity", {})
    if str(maturity.get("state", "")) != "data_ready":
        _fail("selected cell is no longer data_ready")
        return
    for layer_name in REQUIRED_LAYERS:
        var path := "%s/%s" % [SOURCE_ROOT, layer_name]
        var layer := _read_json(path)
        if layer.is_empty():
            _fail("required source layer missing: %s" % layer_name)
            return
        if str(layer.get("type", "")) != "FeatureCollection":
            _fail("source is not GeoJSON FeatureCollection: %s" % layer_name)
            return
        var features: Variant = layer.get("features", [])
        if not features is Array or features.is_empty():
            _fail("source layer has no features: %s" % layer_name)
            return
    print("IXELLES_RUNTIME_SLICE_GATE_OK: cell=%s bbox=%s sources=%d" % [CELL_ID, CELL_BBOX, REQUIRED_LAYERS.size()])
    quit(0)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _fail(message: String) -> void:
    push_error("IXELLES_RUNTIME_SLICE_GATE_FAIL: %s" % message)
    quit(1)
