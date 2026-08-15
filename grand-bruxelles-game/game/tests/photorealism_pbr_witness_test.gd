extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUTPUT_DIR := "res://artifacts/visual"
const BEFORE_PATH := OUTPUT_DIR + "/photoreal_pbr_before.png"
const AFTER_PATH := OUTPUT_DIR + "/photoreal_pbr_after.png"
const WIDTH := 1280
const HEIGHT := 720
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

var _failed := false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate() as Node3D
    if world == null:
        _fail("main scene did not instantiate")
        return
    root.add_child(world)
    current_scene = world
    for _frame in range(8):
        await process_frame

    var midi := world.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null:
        _fail("MidiHeroZone missing")
        return

    var snapshots := _collect_pbr_material_snapshots(midi)
    if snapshots.size() < 3:
        _fail("not enough tagged PBR materials for isolated witness: %d" % snapshots.size())
        return

    var camera := Camera3D.new()
    camera.name = "PhotorealPbrWitnessCamera"
    camera.position = ENTRANCE + ROAD_SIDE * 16.0 + Vector3(0.0, 1.65, 0.0)
    camera.fov = 58.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 3.6, 0.0), Vector3.UP)
    camera.current = true

    # Freeze gameplay so the two captures differ only by the PBR response maps.
    world.process_mode = Node.PROCESS_MODE_DISABLED
    _set_pbr_enabled(snapshots, false)
    await process_frame
    await RenderingServer.frame_post_draw
    var before := root.get_viewport().get_texture().get_image()
    if before == null or before.get_width() != WIDTH or before.get_height() != HEIGHT:
        _fail("before capture must be 1280x720")
        return
    if before.save_png(BEFORE_PATH) != OK:
        _fail("could not save PBR-off witness")
        return

    _set_pbr_enabled(snapshots, true)
    await process_frame
    await RenderingServer.frame_post_draw
    var after := root.get_viewport().get_texture().get_image()
    if after == null or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        _fail("after capture must be 1280x720")
        return
    if after.save_png(AFTER_PATH) != OK:
        _fail("could not save PBR-on witness")
        return

    var over1 := 0
    var over3 := 0
    var over8 := 0
    var total := WIDTH * HEIGHT
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(
                absf(a.r - b.r) * 255.0,
                maxf(absf(a.g - b.g) * 255.0, absf(a.b - b.b) * 255.0)
            )
            if delta > 1.0:
                over1 += 1
            if delta > 3.0:
                over3 += 1
            if delta > 8.0:
                over8 += 1
    var ratio1 := float(over1) / float(total)
    var ratio3 := float(over3) / float(total)
    var ratio8 := float(over8) / float(total)
    print("PHOTOREAL_PBR_DELTA over1=%d ratio1=%.6f over3=%d ratio3=%.6f over8=%d ratio8=%.6f materials=%d" % [
        over1, ratio1, over3, ratio3, over8, ratio8, snapshots.size()
    ])
    # This gate only rejects a zero-impact implementation. Human full-frame
    # inspection decides whether the visible gain is good enough to merge.
    if ratio1 < 0.0002:
        _fail("PBR maps have effectively zero visible impact in pedestrian frame")
        return

    print("PHOTOREAL_PBR_WITNESS_OK")
    quit(0)

func _collect_pbr_material_snapshots(midi: Node3D) -> Array[Dictionary]:
    var snapshots: Array[Dictionary] = []
    var seen: Dictionary = {}
    for candidate: Node in midi.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := candidate as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() < 1:
            continue
        var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
        if material == null or not bool(material.get_meta("photoreal_normal_map", false)):
            continue
        var key := material.get_instance_id()
        if seen.has(key):
            continue
        seen[key] = true
        snapshots.append({
            "material": material,
            "base_roughness": float(material.get_meta("photoreal_base_roughness", material.roughness)),
            "normal_enabled": material.normal_enabled,
            "normal_texture": material.normal_texture,
            "normal_scale": material.normal_scale,
            "roughness": material.roughness,
            "roughness_texture": material.roughness_texture,
        })
    return snapshots

func _set_pbr_enabled(snapshots: Array[Dictionary], enabled: bool) -> void:
    for snapshot: Dictionary in snapshots:
        var material := snapshot.get("material") as StandardMaterial3D
        if material == null:
            continue
        if enabled:
            material.normal_enabled = bool(snapshot.get("normal_enabled", true))
            material.normal_texture = snapshot.get("normal_texture") as Texture2D
            material.normal_scale = float(snapshot.get("normal_scale", 1.0))
            material.roughness = float(snapshot.get("roughness", 1.0))
            material.roughness_texture = snapshot.get("roughness_texture") as Texture2D
        else:
            material.normal_enabled = false
            material.normal_texture = null
            material.roughness_texture = null
            material.roughness = float(snapshot.get("base_roughness", 0.9))

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error("PHOTOREAL_PBR_WITNESS_FAIL: " + message)
    print("PHOTOREAL_PBR_WITNESS_FAIL: " + message)
    quit(1)
