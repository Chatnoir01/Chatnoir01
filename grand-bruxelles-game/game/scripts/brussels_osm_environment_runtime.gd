extends Node3D
class_name BrusselsOsmEnvironmentRuntime

## Generic visual-only renderer for zone-scoped OSM environment artifacts.
## Source points own presence + horizontal position. Shared asset families own
## presentation dimensions; none of those dimensions are source measurements.

const SOURCE_FORMAT := "grand-bruxelles-osm-zone-environment-v1"
const EXPECTED_SOURCE := "OpenStreetMap contributors via Overpass API"
const EXPECTED_SOURCE_CRS := "EPSG:4326"
const EXPECTED_PROJECTION_CRS := "EPSG:31370"
const EXPECTED_LICENSE := "ODbL-1.0"
const EXPECTED_AXES := "X=east, Y=up, Z=south"
const EXPECTED_UNITS := "metres"
const SUPPORTED_KINDS := ["tree", "street_lamp", "bollard"]
const TREE_FAR_FOLIAGE_LOBE_INDICES := [0, 3, 6]

@export_file("*.json") var data_path := ""
@export var render_radius_m := 350.0
@export var refresh_distance_m := 80.0
@export var tree_full_detail_radius_m := 140.0
@export var max_trees := 450
@export var max_street_lamps := 220
@export var max_bollards := 160

var last_render_counts := {"tree": 0, "street_lamp": 0, "bollard": 0}
var last_tree_lod_counts := {"near": 0, "far": 0, "foliage_instances": 0}
var _points := {"tree": [], "street_lamp": [], "bollard": []}
var _last_anchor := Vector3(INF, INF, INF)
var _loaded_ok := false

func _ready() -> void:
    _loaded_ok = _load_points()
    if not _loaded_ok:
        set_process(false)
        return
    call_deferred("_refresh", true)

func _process(_delta: float) -> void:
    _refresh(false)

func loaded_ok() -> bool:
    return _loaded_ok

func _validate_document_contract(document: Dictionary) -> bool:
    if str(document.get("format", "")) != SOURCE_FORMAT:
        push_error("OSM environment artifact format mismatch")
        return false
    if str(document.get("source", "")) != EXPECTED_SOURCE:
        push_error("OSM environment artifact source mismatch")
        return false
    if str(document.get("license", "")) != EXPECTED_LICENSE:
        push_error("OSM environment artifact license mismatch")
        return false
    if str(document.get("source_crs", "")) != EXPECTED_SOURCE_CRS:
        push_error("OSM environment artifact source CRS mismatch")
        return false
    if str(document.get("projection_crs", "")) != EXPECTED_PROJECTION_CRS:
        push_error("OSM environment artifact projection CRS mismatch")
        return false
    var origin: Variant = document.get("game_origin", {})
    if not origin is Dictionary:
        push_error("OSM environment artifact game origin missing")
        return false
    var game_origin := origin as Dictionary
    if str(game_origin.get("axes", "")) != EXPECTED_AXES:
        push_error("OSM environment artifact axes mismatch")
        return false
    if str(game_origin.get("units", "")) != EXPECTED_UNITS:
        push_error("OSM environment artifact units mismatch")
        return false
    var rows: Variant = document.get("environment_points", [])
    if not rows is Array:
        push_error("OSM environment artifact points must be an array")
        return false
    var stats: Variant = document.get("stats", {})
    if not stats is Dictionary:
        push_error("OSM environment artifact stats missing")
        return false
    var expected_total := 0
    for kind: String in SUPPORTED_KINDS:
        if not (stats as Dictionary).has(kind):
            push_error("OSM environment artifact stats missing kind: %s" % kind)
            return false
        var count := int((stats as Dictionary).get(kind, -1))
        if count < 0:
            push_error("OSM environment artifact stats invalid kind: %s" % kind)
            return false
        expected_total += count
    if expected_total != (rows as Array).size():
        push_error("OSM environment artifact stats/point total mismatch")
        return false
    return true

func _load_points() -> bool:
    for kind: String in SUPPORTED_KINDS:
        (_points[kind] as Array).clear()
    _last_anchor = Vector3(INF, INF, INF)
    if data_path.is_empty() or not FileAccess.file_exists(data_path):
        push_error("OSM environment artifact missing: %s" % data_path)
        return false
    var file := FileAccess.open(data_path, FileAccess.READ)
    if file == null:
        push_error("OSM environment artifact unreadable: %s" % data_path)
        return false
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("OSM environment artifact invalid JSON object")
        return false
    var document := parsed as Dictionary
    if not _validate_document_contract(document):
        return false
    var actual_counts := {"tree": 0, "street_lamp": 0, "bollard": 0}
    for row_variant in document.get("environment_points", []):
        if not row_variant is Dictionary:
            push_error("OSM environment point must be an object")
            return false
        var row := row_variant as Dictionary
        var kind := str(row.get("kind", ""))
        if kind not in SUPPORTED_KINDS:
            push_error("Unsupported OSM environment kind: %s" % kind)
            return false
        var osm_id := int(row.get("osm_id", 0))
        if osm_id <= 0:
            push_error("OSM environment point missing OSM id")
            return false
        var position = row.get("position", [])
        if not position is Array or position.size() < 2:
            push_error("OSM environment point missing X/Z position")
            return false
        (_points[kind] as Array).append({
            "osm_id": osm_id,
            "position": Vector3(float(position[0]), 0.0, float(position[1])),
        })
        actual_counts[kind] = int(actual_counts[kind]) + 1
    var stats := document.get("stats", {}) as Dictionary
    for kind: String in SUPPORTED_KINDS:
        if int(actual_counts[kind]) != int(stats.get(kind, -1)):
            push_error("OSM environment artifact stats mismatch for kind: %s" % kind)
            for clear_kind: String in SUPPORTED_KINDS:
                (_points[clear_kind] as Array).clear()
            return false
    set_meta("source", str(document.get("source", "")))
    set_meta("license", str(document.get("license", "")))
    set_meta("source_crs", str(document.get("source_crs", "")))
    set_meta("projection_crs", str(document.get("projection_crs", "")))
    set_meta("source_dimensions_measured", false)
    return true

func _target() -> Node3D:
    var player := get_tree().get_first_node_in_group("player") as Node3D
    if player != null:
        return player
    var scene := get_tree().current_scene
    return scene.get_node_or_null("Player") as Node3D if scene != null else null

func _refresh(force: bool) -> void:
    var target := _target()
    if target == null:
        return
    var anchor := target.global_position
    if not force and _last_anchor != Vector3(INF, INF, INF) and anchor.distance_to(_last_anchor) < refresh_distance_m:
        return
    _last_anchor = anchor
    _rebuild(anchor)

func _nearby(kind: String, anchor: Vector3, limit: int) -> Array:
    var rows: Array = []
    var radius_sq := render_radius_m * render_radius_m
    for item_variant in _points[kind]:
        var item := item_variant as Dictionary
        var p: Vector3 = item["position"]
        var dx := p.x - anchor.x
        var dz := p.z - anchor.z
        var distance_sq := dx * dx + dz * dz
        if distance_sq <= radius_sq:
            rows.append({"osm_id": item["osm_id"], "position": p, "distance_sq": distance_sq})
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if float(a["distance_sq"]) == float(b["distance_sq"]):
            return int(a["osm_id"]) < int(b["osm_id"])
        return float(a["distance_sq"]) < float(b["distance_sq"])
    )
    if rows.size() > limit:
        rows.resize(limit)
    return rows

func _rebuild(anchor: Vector3) -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    var trees := _nearby("tree", anchor, max_trees)
    var lamps := _nearby("street_lamp", anchor, max_street_lamps)
    var bollards := _nearby("bollard", anchor, max_bollards)
    last_render_counts = {"tree": trees.size(), "street_lamp": lamps.size(), "bollard": bollards.size()}
    _build_tree_batches(trees)
    _build_lamp_batches(lamps)
    _build_bollard_batches(bollards)
    set_meta("render_counts", last_render_counts.duplicate(true))
    set_meta("tree_lod_counts", last_tree_lod_counts.duplicate(true))
    print("BRUSSELS_OSM_ENVIRONMENT_READY: %s radius=%.0fm tree_lod=%s" % [JSON.stringify(last_render_counts), render_radius_m, JSON.stringify(last_tree_lod_counts)])

func _batch(name_value: String, mesh: Mesh, transforms: Array) -> void:
    if transforms.is_empty():
        return
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index] as Transform3D)
    var instance := MultiMeshInstance3D.new()
    instance.name = name_value
    instance.multimesh = multimesh
    instance.set_meta("source_dimensions_measured", false)
    add_child(instance)

func _build_tree_batches(rows: Array) -> void:
    if rows.is_empty():
        last_tree_lod_counts = {"near": 0, "far": 0, "foliage_instances": 0}
        return
    var materials := BrusselsStreetTreeAsset.create_materials()
    var trunk: Array = []
    var dark: Array = []
    var light: Array = []
    var near_count := 0
    var far_count := 0
    var full_detail_radius_sq := tree_full_detail_radius_m * tree_full_detail_radius_m
    for row_variant in rows:
        var row := row_variant as Dictionary
        var base: Vector3 = row["position"]
        var osm_id := int(row["osm_id"])
        trunk.append(BrusselsStreetTreeAsset.trunk_transform(base))
        var lobe_indices: Array = []
        if float(row.get("distance_sq", 0.0)) <= full_detail_radius_sq:
            near_count += 1
            for index in range(BrusselsStreetTreeAsset.FOLIAGE_LOBE_COUNT):
                lobe_indices.append(index)
        else:
            far_count += 1
            lobe_indices.assign(TREE_FAR_FOLIAGE_LOBE_INDICES)
        for index_variant in lobe_indices:
            var index := int(index_variant)
            var transform := BrusselsStreetTreeAsset.foliage_lobe_transform(base, osm_id, index)
            (light if BrusselsStreetTreeAsset.foliage_is_light(index) else dark).append(transform)
    last_tree_lod_counts = {"near": near_count, "far": far_count, "foliage_instances": dark.size() + light.size()}
    _batch("TreeTrunks", BrusselsStreetTreeAsset.create_trunk_mesh(materials["trunk"]), trunk)
    _batch("TreeFoliageDark", BrusselsStreetTreeAsset.create_foliage_mesh(materials["foliage_dark"]), dark)
    _batch("TreeFoliageLight", BrusselsStreetTreeAsset.create_foliage_mesh(materials["foliage_light"]), light)

func _build_lamp_batches(rows: Array) -> void:
    if rows.is_empty():
        return
    var materials := BrusselsStreetLampAsset.create_materials()
    var poles: Array = []
    var arms: Array = []
    var luminaires: Array = []
    for row_variant in rows:
        var base: Vector3 = (row_variant as Dictionary)["position"]
        poles.append(BrusselsStreetLampAsset.pole_transform(base))
        arms.append(BrusselsStreetLampAsset.arm_transform(base))
        luminaires.append(BrusselsStreetLampAsset.luminaire_transform(base))
    _batch("LampPoles", BrusselsStreetLampAsset.create_pole_mesh(materials["metal"]), poles)
    _batch("LampArms", BrusselsStreetLampAsset.create_arm_mesh(materials["metal"]), arms)
    _batch("LampLuminaires", BrusselsStreetLampAsset.create_luminaire_mesh(materials["luminaire"]), luminaires)

func _build_bollard_batches(rows: Array) -> void:
    if rows.is_empty():
        return
    var materials := BrusselsBollardAsset.create_materials()
    var bodies: Array = []
    var caps: Array = []
    for row_variant in rows:
        var base: Vector3 = (row_variant as Dictionary)["position"]
        bodies.append(BrusselsBollardAsset.body_transform(base))
        caps.append(BrusselsBollardAsset.cap_transform(base))
    _batch("BollardBodies", BrusselsBollardAsset.create_body_mesh(materials["body"]), bodies)
    _batch("BollardCaps", BrusselsBollardAsset.create_cap_mesh(materials["cap"]), caps)
