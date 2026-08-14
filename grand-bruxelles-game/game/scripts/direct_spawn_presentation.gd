extends Node

## Presentation-only framing for browser/direct-location entry points.
## This never changes source geography or landmark geometry.

const ATOMIUM_DIRECT_FOV_DEGREES := 48.0
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"
const BASE_VISUAL_PATH := "MeshInstance3D"
const UPGRADE_VISUAL_PATH := "VisualUpgrade"


func _ready() -> void:
    call_deferred("_apply_startup_args")


func _apply_startup_args() -> void:
    var args := OS.get_cmdline_user_args()
    if not _wants_atomium(args):
        return
    for _frame: int in range(24):
        var player := get_tree().root.find_child("Player", true, false)
        if player != null and apply_to_player(player, args):
            return
        await get_tree().process_frame
    push_warning("DirectSpawnPresentation: Atomium player camera unavailable")


func _wants_atomium(args: PackedStringArray) -> bool:
    for arg: String in args:
        if arg.strip_edges().to_lower() == "spawn=atomium":
            return true
    return false


func apply_to_player(player: Node, args: PackedStringArray) -> bool:
    if player == null or not _wants_atomium(args):
        return false
    var camera := player.get_node_or_null(CAMERA_PATH) as Camera3D
    if camera == null:
        return false
    camera.fov = ATOMIUM_DIRECT_FOV_DEGREES

    # The direct Atomium URL is a presentation witness. Keep the third-person
    # camera position but remove the avatar occluder so the landmark itself is
    # judgeable. This does not alter player collision, movement or world data.
    var base_visual := player.get_node_or_null(BASE_VISUAL_PATH) as CanvasItem
    if base_visual != null:
        base_visual.visible = false
    var upgrade_visual := player.get_node_or_null(UPGRADE_VISUAL_PATH) as Node3D
    if upgrade_visual != null:
        upgrade_visual.visible = false

    player.set_meta("atomium_direct_presentation_fov_degrees", ATOMIUM_DIRECT_FOV_DEGREES)
    player.set_meta("atomium_direct_presentation_avatar_hidden", true)
    print("ATOMIUM_DIRECT_PRESENTATION_READY: fov=%.1f avatar_hidden=true" % ATOMIUM_DIRECT_FOV_DEGREES)
    return true
