extends "res://game/tests/bourse_geotagged_camera_capture_test.gd"

func _hide_capture_noise(scene: Node) -> void:
    super._hide_capture_noise(scene)
    var node_path := OS.get_environment("BOURSE_DIAGNOSTIC_HIDE")
    if node_path.is_empty():
        return
    var spatial := scene.get_node_or_null(node_path) as Node3D
    if spatial != null:
        spatial.visible = false
        print("BOURSE_LAYER_HIDE: %s" % node_path)
