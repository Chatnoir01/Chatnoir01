extends Node

signal balance_changed(cash_cents: int)

const STATE_SCHEMA_VERSION := 1
const MAX_CASH_CENTS := 100_000_000

var _cash_cents := 0


func credit(amount_cents: int) -> bool:
    if amount_cents <= 0 or amount_cents > MAX_CASH_CENTS - _cash_cents:
        return false
    _cash_cents += amount_cents
    balance_changed.emit(_cash_cents)
    return true


func reset() -> void:
    _cash_cents = 0
    balance_changed.emit(_cash_cents)


func get_cash_cents() -> int:
    return _cash_cents


func export_state() -> Dictionary:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "cash_cents": _cash_cents,
    }


func can_restore_state(state: Dictionary) -> bool:
    if int(state.get("schema_version", -1)) != STATE_SCHEMA_VERSION:
        return false
    var cash_value: Variant = state.get("cash_cents", null)
    if not (cash_value is int or cash_value is float):
        return false
    var restored_cash_float := float(cash_value)
    if not is_finite(restored_cash_float) or restored_cash_float != floorf(restored_cash_float):
        return false
    return restored_cash_float >= 0.0 and restored_cash_float <= float(MAX_CASH_CENTS)


func restore_state(state: Dictionary) -> bool:
    if not can_restore_state(state):
        return false
    _cash_cents = int(state["cash_cents"])
    balance_changed.emit(_cash_cents)
    return true
