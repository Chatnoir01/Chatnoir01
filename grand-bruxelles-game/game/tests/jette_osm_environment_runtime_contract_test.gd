extends SceneTree

const GENERIC_RUNTIME := "res://game/scripts/brussels_osm_environment_runtime.gd"
const JETTE_ZONE := "res://game/zones/laeken_jette/jette_phase2_zone.gd"
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector2(-687.700268506218, -4952.774160383269)
const LOCAL_RADIUS_M := 300.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("JETTE_OSM_ENVIRONMENT_CONTRACT_FAIL: %s" % message)
    quit(1)

func _read(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    return f.get_as_text() if f != null else ""

func _run() -> void:
    if not FileAccess.file_exists(GENERIC_RUNTIME):
        _fail("generic Brussels OSM environment runtime missing")
        return
    var generic := _read(GENERIC_RUNTIME)
    var lower := generic.to_lower()
    if lower.contains("jette"):
        _fail("generic renderer contains a Jette-specific literal")
        return
    for token in ["MultiMeshInstance3D", "tree", "street_lamp", "bollard"]:
        if not generic.contains(token):
            _fail("generic renderer missing contract token %s" % token)
            return
    for forbidden in ["StaticBody3D", "CollisionShape3D"]:
        if generic.contains(forbidden):
            _fail("visual renderer must not create collision owner %s" % forbidden)
            return

    var zone := _read(JETTE_ZONE)
    if not zone.contains(GENERIC_RUNTIME) or not zone.contains(JETTE_DATA):
        _fail("Jette zone does not configure generic runtime with City Machine artifact")
        return

    var parsed = JSON.parse_string(_read(JETTE_DATA))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("Jette environment artifact invalid")
        return
    var data := parsed as Dictionary
    if str(data.get("format", "")) != "grand-bruxelles-osm-zone-environment-v1":
        _fail("unexpected environment format")
        return
    var total := 0
    var local := {"tree": 0, "street_lamp": 0, "bollard": 0}
    for row_variant in data.get("environment_points", []):
        if not row_variant is Dictionary:
            continue
        var row := row_variant as Dictionary
        var kind := str(row.get("kind", ""))
        if not local.has(kind):
            _fail("unsupported source kind %s" % kind)
            return
        var pos = row.get("position", [])
        if not pos is Array or pos.size() < 2:
            _fail("bad source position")
            return
        total += 1
        var p := Vector2(float(pos[0]), float(pos[1]))
        if p.distance_to(JETTE_SPAWN) <= LOCAL_RADIUS_M:
            local[kind] = int(local[kind]) + 1
    if total != 4584:
        _fail("expected 4584 source points, got %d" % total)
        return
    if int(local["tree"]) + int(local["street_lamp"]) + int(local["bollard"]) <= 0:
        _fail("no source environment within %.0fm of production spawn" % LOCAL_RADIUS_M)
        return

    print("JETTE_OSM_ENVIRONMENT_CONTRACT_OK: total=%d local_300m=%s generic=true multimesh=true collisions=false" % [total, str(local)])
    quit(0)
