extends "res://game/tests/bourse_geotagged_camera_capture_test.gd"

func _hide_capture_noise(scene: Node) -> void:
    super._hide_capture_noise(scene)
    var roofs := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Roofs") as Node3D
    # The base harness invokes this hook before and after deferred UrbIS hero mount.
    # Absence during the pre-mount pass is expected. The workflow requires a later
    # BOURSE_ROOFS_HIDE_OK marker, so a missing post-mount Roofs node still fails.
    if roofs == null:
        return
    roofs.visible = false
    print("BOURSE_ROOFS_HIDE_OK")
