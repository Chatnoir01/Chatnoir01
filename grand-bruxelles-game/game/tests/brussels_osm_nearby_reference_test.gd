extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)
const KINDS := ["tree", "street_lamp", "bollard"]

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_NEARBY_REFERENCE_FAIL: %s" % message)
    quit(1)

func _ordered_ids(rows: Array) -> Array[int]:
    var ids: Array[int] = []
    for row_variant: Variant in rows:
        ids.append(int((row_variant as Dictionary)["osm_id"]))
    return ids

func _reference_nearby(runtime: Node3D, kind: String, anchor: Vector3, radius_m: float, limit: int) -> Array:
    if limit <= 0:
        return []
    var candidates: Array = []
    var points := runtime.get("_points") as Dictionary
    var radius_sq := radius_m * radius_m
    for item_variant: Variant in points[kind] as Array:
        var item := item_variant as Dictionary
        var p: Vector3 = item["position"]
        var dx := p.x - anchor.x
        var dz := p.z - anchor.z
        var distance_sq := dx * dx + dz * dz
        if distance_sq <= radius_sq:
            candidates.append({
                "osm_id": int(item["osm_id"]),
                "position": p,
                "distance_sq": distance_sq,
            })
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var a_distance := float(a["distance_sq"])
        var b_distance := float(b["distance_sq"])
        if a_distance == b_distance:
            return int(a["osm_id"]) < int(b["osm_id"])
        return a_distance < b_distance
    )
    if candidates.size() > limit:
        candidates.resize(limit)
    return candidates

func _anchors_for(runtime: Node3D) -> Array[Vector3]:
    var anchors: Array[Vector3] = [JETTE_SPAWN]
    var points := runtime.get("_points") as Dictionary
    for kind: String in KINDS:
        var rows := points[kind] as Array
        if rows.is_empty():
            continue
        var indices := [0, int(rows.size() / 2), rows.size() - 1]
        for index_variant: Variant in indices:
            var p: Vector3 = (rows[int(index_variant)] as Dictionary)["position"]
            anchors.append(Vector3(p.x, JETTE_SPAWN.y, p.z))
    return anchors

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.set("data_path", JETTE_DATA)
    if not bool(runtime.call("_load_points")):
        _fail("could not load the canonical Jette OSM environment artifact")
        return
    if str(runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("source provenance changed while loading the Jette fixture")
        return
    if str(runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("license provenance changed while loading the Jette fixture")
        return

    var points := runtime.get("_points") as Dictionary
    var anchors := _anchors_for(runtime)
    var radii := [0.0, 1.0, 25.0, 100.0, 350.0, 1000.0]
    var limits := [0, 1, 2, 7, 31, 160, 220, 450]
    var comparisons := 0
    var non_empty_comparisons := 0

    for kind: String in KINDS:
        if (points[kind] as Array).is_empty():
            _fail("canonical Jette fixture has no %s points" % kind)
            return
        for anchor: Vector3 in anchors:
            for radius_variant: Variant in radii:
                var radius_m := float(radius_variant)
                runtime.set("render_radius_m", radius_m)
                for limit_variant: Variant in limits:
                    var limit := int(limit_variant)
                    var expected := _reference_nearby(runtime, kind, anchor, radius_m, limit)
                    var actual := runtime.call("_nearby", kind, anchor, limit) as Array
                    comparisons += 1
                    if not expected.is_empty():
                        non_empty_comparisons += 1
                    var expected_ids := _ordered_ids(expected)
                    var actual_ids := _ordered_ids(actual)
                    if actual_ids != expected_ids:
                        _fail("optimized selector diverged kind=%s anchor=(%.3f,%.3f) radius=%.3f limit=%d expected=%s actual=%s" % [kind, anchor.x, anchor.z, radius_m, limit, str(expected_ids), str(actual_ids)])
                        return
                    for index in range(expected.size()):
                        var expected_row := expected[index] as Dictionary
                        var actual_row := actual[index] as Dictionary
                        if (actual_row["position"] as Vector3) != (expected_row["position"] as Vector3):
                            _fail("optimized selector changed source position kind=%s osm_id=%d" % [kind, int(expected_row["osm_id"])])
                            return
                        if float(actual_row["distance_sq"]) != float(expected_row["distance_sq"]):
                            _fail("optimized selector changed distance ordering input kind=%s osm_id=%d" % [kind, int(expected_row["osm_id"])])
                            return

    if comparisons < 1000 or non_empty_comparisons <= 0:
        _fail("reference witness did not exercise enough real selection cases")
        return

    print("BRUSSELS_OSM_NEARBY_REFERENCE_OK: comparisons=%d non_empty=%d anchors=%d source=%s license=%s" % [comparisons, non_empty_comparisons, anchors.size(), str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)
