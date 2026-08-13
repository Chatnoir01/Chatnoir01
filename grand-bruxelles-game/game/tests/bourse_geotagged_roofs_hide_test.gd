extends "res://game/tests/bourse_geotagged_camera_capture_test.gd"

func _hide_capture_noise(scene: Node) -> void:
    super._hide_capture_noise(scene)
    var roofs := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Roofs") as Node3D
    if roofs == null:
        push_error("BOURSE_ROOFS_HIDE_FAIL")
        return
    roofs.visible = false
    print("BOURSE_ROOFS_HIDE_OK")
