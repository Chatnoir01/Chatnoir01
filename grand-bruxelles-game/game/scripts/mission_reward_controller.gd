extends Node

@onready var mission: Node = get_node("../MissionDriveToCenter")
@onready var wallet: Node = get_node("../Wallet")


func _ready() -> void:
    mission.mission_completed.connect(_on_mission_completed)


func _on_mission_completed(reward_cents: int) -> void:
    if reward_cents <= 0:
        return
    if not bool(wallet.call("credit", reward_cents)):
        push_error("Mission reward could not be credited")
