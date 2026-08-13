extends "res://game/tests/bourse_geotagged_camera_capture_test.gd"

var _roofs_hidden_once := false

func _hide_capture_noise(scene: Node) -> void:
    super._hide_capture_noise(scene)
    var roofs := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Roofs") as Node3D
    # The base harness invokes this hook before and after deferred UrbIS hero mount.
    # The pre-mount pass is not a failure; the post-mount pass must find and hide Roofs.
    if roofs == null:
        return
    roofs.visible = false
    _roofs_hidden_once = true
    print("BOURSE_ROOFS_HIDE_OK")

func _validate_capture_scene(scene: Node) -> bool:
    if not super._validate_capture_scene(scene):
        return false
    if not _roofs_hidden_once:
        push_error("BOURSE_ROOFS_HIDE_FAIL")
        return false
    return true
