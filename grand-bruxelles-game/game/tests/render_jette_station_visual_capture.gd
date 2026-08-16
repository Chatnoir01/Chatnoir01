extends SceneTree

const OUTPUT := "res://artifacts/visual/jette_station_visual_1280x720.png"


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/jette_phase2_preview.tscn")
    if packed == null:
        push_error("JETTE_STATION_CAPTURE_FAIL: preview scene unavailable")
        quit(1)
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame

    var zone: Node = scene.get_node_or_null("JettePhase2Zone")
    var camera: Camera3D = scene.get_node_or_null("Camera3D") as Camera3D
    var hero: MeshInstance3D = zone.get_node_or_null("JetteStationOfficialFootprintHero") as MeshInstance3D if zone != null else null
    if camera == null or hero == null or hero.mesh == null:
        push_error("JETTE_STATION_CAPTURE_FAIL: station hero/camera unavailable")
        quit(1)
        return

    # Frame the actual UrbIS-owned station hero instead of relying on a distant
    # hard-coded overview camera. The witness therefore proves the station lot,
    # while remaining derived from loaded source-backed geometry.
    var local_aabb: AABB = hero.get_aabb()
    var center: Vector3 = hero.global_transform * local_aabb.get_center()
    var size: Vector3 = local_aabb.size
    var horizontal_extent: float = maxf(maxf(size.x, size.z), 12.0)
    var camera_height: float = maxf(size.y * 0.55, 5.5)
    var target_height: float = maxf(size.y * 0.28, 1.8)
    camera.global_position = center + Vector3(-horizontal_extent * 0.85, camera_height, horizontal_extent * 1.15)
    camera.look_at(center + Vector3(0.0, target_height, 0.0), Vector3.UP)
    camera.fov = 58.0

    var window: Window = root.get_window()
    window.size = Vector2i(1280, 720)
    await process_frame
    await process_frame

    var image: Image = root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        push_error("JETTE_STATION_CAPTURE_FAIL: viewport image empty")
        quit(1)
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
    var err: Error = image.save_png(OUTPUT)
    if err != OK:
        push_error("JETTE_STATION_CAPTURE_FAIL: save_png=%s" % err)
        quit(1)
        return

    print("JETTE_STATION_CAPTURE_OK: %s" % OUTPUT)
    scene.queue_free()
    await process_frame
    quit(0)
