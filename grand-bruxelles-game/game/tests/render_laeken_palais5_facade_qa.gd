extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_jette.tscn"
const OUTPUT_PATH := "res://palais5_facade_qa.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LAEKEN_PALAIS5_CAPTURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load(SCENE_PATH) as PackedScene
    if packed == null:
        _fail("Laeken/Jette scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    root.size = Vector2i(1280, 720)
    for _i in range(50):
        await process_frame

    var pass_node := scene.get_node_or_null("Palais5HeroPass")
    if pass_node == null or not bool(pass_node.get("hero_ready")):
        _fail("Palais 5 hero geometry is not ready")
        return
    var hero := pass_node.get_node_or_null("Palais5HeroGeometry") as Node3D
    if hero == null:
        _fail("Palais5HeroGeometry root missing")
        return

    # Diagnostic QA camera only. It is derived from the built facade transform and
    # is not claimed to reproduce any historical or contemporary source photo.
    var outward := -hero.global_transform.basis.z.normalized()
    var camera_position := hero.global_position + outward * 92.0 + Vector3.UP * 18.0
    var target_position := hero.global_position + hero.global_transform.basis.z.normalized() * 9.0 + Vector3.UP * 14.0

    var camera := Camera3D.new()
    camera.name = "Palais5FacadeQACamera"
    camera.fov = 54.0
    camera.near = 0.05
    camera.far = 6000.0
    scene.add_child(camera)
    camera.global_position = camera_position
    camera.look_at(target_position, Vector3.UP)
    camera.current = true

    for _i in range(12):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    await process_frame

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("empty viewport image")
        return
    if image.get_width() != 1280 or image.get_height() != 720:
        _fail("unexpected capture resolution")
        return
    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        _fail("save_png failed: %s" % error)
        return

    print("LAEKEN_PALAIS5_CAPTURE_OK: output=%s camera=%s target=%s fov=%.1f" % [OUTPUT_PATH, camera_position, target_position, camera.fov])
    scene.queue_free()
    await process_frame
    quit(0)
