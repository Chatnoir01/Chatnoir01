extends Node

@onready var wallet: Node = get_node("../Wallet")


func _ready() -> void:
    for mission: Node in get_tree().get_nodes_in_group("rewarding_mission"):
        if mission.has_signal("mission_completed"):
            mission.connect("mission_completed", _on_mission_completed)


func _on_mission_completed(reward_cents: int) -> void:
    if reward_cents <= 0:
        return
    if not bool(wallet.call("credit", reward_cents)):
        push_error("Mission reward could not be credited")
