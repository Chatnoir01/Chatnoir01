extends Node

@onready var wallet: Node = get_node("../Wallet")
@onready var wallet_label: Label = get_node("../WalletLabel")


func _ready() -> void:
    wallet.balance_changed.connect(_on_balance_changed)
    _on_balance_changed(int(wallet.call("get_cash_cents")))


func _on_balance_changed(cash_cents: int) -> void:
    var euros := cash_cents / 100
    var cents := cash_cents % 100
    wallet_label.text = "%d €" % euros if cents == 0 else "%d,%02d €" % [euros, cents]
