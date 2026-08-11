extends RefCounted

const DEFAULT_DELAY_S := 4.0
const BASE_TOW_EUR := 55.0
const ROADSIDE_REPAIR_AMOUNT := 72.0

var state: String = "idle"
var requested_at_s: float = 0.0
var ready_at_s: float = 0.0
var quote_eur: float = 0.0


func estimate_quote(body_damage: float, mechanical_damage: float) -> float:
    var body := clampf(body_damage, 0.0, 100.0)
    var mechanical := clampf(mechanical_damage, 0.0, 100.0)
    return round(BASE_TOW_EUR + body * 0.45 + mechanical * 0.85)


func request_recovery(
    body_damage: float,
    mechanical_damage: float,
    now_seconds: float,
    delay_seconds: float = DEFAULT_DELAY_S
) -> Dictionary:
    if state == "requested":
        return snapshot(now_seconds)
    state = "requested"
    requested_at_s = now_seconds
    ready_at_s = now_seconds + maxf(0.0, delay_seconds)
    quote_eur = estimate_quote(body_damage, mechanical_damage)
    return snapshot(now_seconds)


func is_ready(now_seconds: float) -> bool:
    return state == "requested" and now_seconds >= ready_at_s


func remaining_seconds(now_seconds: float) -> float:
    if state != "requested":
        return 0.0
    return maxf(0.0, ready_at_s - now_seconds)


func complete_recovery(now_seconds: float) -> Dictionary:
    if not is_ready(now_seconds):
        return snapshot(now_seconds)
    state = "recovered"
    return snapshot(now_seconds)


func reset() -> void:
    state = "idle"
    requested_at_s = 0.0
    ready_at_s = 0.0
    quote_eur = 0.0


func get_roadside_repair_amount() -> float:
    return ROADSIDE_REPAIR_AMOUNT


func snapshot(now_seconds: float) -> Dictionary:
    return {
        "state": state,
        "quote_eur": quote_eur,
        "remaining_seconds": remaining_seconds(now_seconds),
        "ready": is_ready(now_seconds),
        "roadside_repair_amount": ROADSIDE_REPAIR_AMOUNT,
    }
