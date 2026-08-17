extends Node

const IDENTITY_RESOLVER := preload("res://game/scripts/player_identity_resolver.gd")
const BADGE_NODE_NAME := "PlayerFallbackIdentityBadge"
const KAYKIT_PATH := "res://assets/characters/player_character.glb"
const MAX_RUNTIME_WAIT_FRAMES := 180

var _badge_layer: CanvasLayer
var _badge_panel: PanelContainer
var _badge_label: Label
var _runtime_wait_frames: int = 0

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    if _try_refresh_badge():
        set_process(false)
        return
    _runtime_wait_frames += 1
    if _runtime_wait_frames >= MAX_RUNTIME_WAIT_FRAMES:
        _set_badge_text("PLAYER FALLBACK · VISUAL UNRESOLVED")
        set_process(false)

static func resolve_runtime_scene(tree: SceneTree) -> Node:
    if tree == null or tree.root == null:
        return null
    var current := tree.current_scene
    if current != null and current.get_node_or_null("Player/VisualUpgrade") != null:
        return current
    for child: Node in tree.root.get_children():
        if child.get_node_or_null("Player/VisualUpgrade") != null:
            return child
    return null

static func runtime_visual_ready(scene: Node) -> bool:
    if scene == null:
        return false
    var visual := scene.get_node_or_null("Player/VisualUpgrade")
    return visual != null and visual.is_inside_tree() and visual.is_node_ready()

static func badge_text_for_identity(identity: Dictionary) -> String:
    if String(identity.get("regime", "")) != "PLAYER_FALLBACK":
        return ""
    var resolved_path := String(identity.get("resolved_path", ""))
    var fallback_kind := String(identity.get("fallback_kind", ""))
    if fallback_kind == "authored" and resolved_path == KAYKIT_PATH:
        return "PLAYER FALLBACK · KAYKIT ROGUE"
    if fallback_kind == "authored":
        return "PLAYER FALLBACK · AUTHORED"
    return "PLAYER FALLBACK · PROCEDURAL"

func refresh_badge() -> void:
    _try_refresh_badge()

func _try_refresh_badge() -> bool:
    var scene := resolve_runtime_scene(get_tree())
    if not runtime_visual_ready(scene):
        return false
    var visual: Node = scene.get_node_or_null("Player/VisualUpgrade")
    var identity: Dictionary = IDENTITY_RESOLVER.classify_runtime_visual(visual)
    var badge_text := badge_text_for_identity(identity)
    if badge_text.is_empty():
        _remove_badge()
    else:
        _set_badge_text(badge_text)
    return true

func _set_badge_text(text: String) -> void:
    _ensure_badge()
    _badge_label.text = text

func _ensure_badge() -> void:
    if is_instance_valid(_badge_layer):
        return
    _badge_layer = CanvasLayer.new()
    _badge_layer.name = BADGE_NODE_NAME
    _badge_layer.layer = 90
    add_child(_badge_layer)

    _badge_panel = PanelContainer.new()
    _badge_panel.name = "Panel"
    _badge_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _badge_panel.position = Vector2(-300.0, 16.0)
    _badge_panel.custom_minimum_size = Vector2(284.0, 34.0)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.03, 0.04, 0.05, 0.82)
    panel_style.border_width_left = 2
    panel_style.border_width_top = 2
    panel_style.border_width_right = 2
    panel_style.border_width_bottom = 2
    panel_style.border_color = Color(0.92, 0.62, 0.16, 0.95)
    panel_style.corner_radius_top_left = 4
    panel_style.corner_radius_top_right = 4
    panel_style.corner_radius_bottom_left = 4
    panel_style.corner_radius_bottom_right = 4
    panel_style.content_margin_left = 10.0
    panel_style.content_margin_right = 10.0
    panel_style.content_margin_top = 6.0
    panel_style.content_margin_bottom = 6.0
    _badge_panel.add_theme_stylebox_override("panel", panel_style)
    _badge_layer.add_child(_badge_panel)

    _badge_label = Label.new()
    _badge_label.name = "Label"
    _badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _badge_label.add_theme_font_size_override("font_size", 14)
    _badge_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.78, 1.0))
    _badge_panel.add_child(_badge_label)

func _remove_badge() -> void:
    if is_instance_valid(_badge_layer):
        _badge_layer.queue_free()
    _badge_layer = null
    _badge_panel = null
    _badge_label = null
