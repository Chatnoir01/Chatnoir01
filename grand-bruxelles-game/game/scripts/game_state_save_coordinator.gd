extends RefCounted
class_name GameStateSaveCoordinator

const SaveStore = preload("res://game/scripts/save_game_store.gd")
const PAYLOAD_SCHEMA_VERSION: int = 1

static func save_domains(path: String, providers: Dictionary) -> Dictionary:
    if providers.is_empty():
        return _error("no_providers")
    var domains: Dictionary = {}
    var keys: Array = providers.keys()
    keys.sort()
    for key_value in keys:
        var key := str(key_value)
        if key.is_empty():
            return _error("invalid_domain")
        var provider: Object = providers[key_value]
        if provider == null or not is_instance_valid(provider) or not provider.has_method("export_state"):
            return _error("unsupported_provider", key)
        var exported: Variant = provider.call("export_state")
        if not exported is Dictionary:
            return _error("invalid_domain_state", key)
        domains[key] = (exported as Dictionary).duplicate(true)
    return SaveStore.write_snapshot(path, {
        "schema_version": PAYLOAD_SCHEMA_VERSION,
        "domains": domains,
    })

static func load_domains(path: String, providers: Dictionary) -> Dictionary:
    if providers.is_empty():
        return _error("no_providers")
    var read_result: Dictionary = SaveStore.read_snapshot(path)
    if not bool(read_result.get("ok", false)):
        return read_result
    var payload_value: Variant = read_result.get("payload", null)
    if not payload_value is Dictionary:
        return _error("invalid_payload")
    var payload: Dictionary = payload_value
    if int(payload.get("schema_version", -1)) != PAYLOAD_SCHEMA_VERSION:
        return _error("unsupported_payload_schema")
    var domains_value: Variant = payload.get("domains", null)
    if not domains_value is Dictionary:
        return _error("missing_domains")
    var domains: Dictionary = domains_value

    var keys: Array = providers.keys()
    keys.sort()
    var backups: Dictionary = {}

    for key_value in keys:
        var key := str(key_value)
        if not domains.has(key):
            return _error("domain_not_found", key)
        var provider: Object = providers[key_value]
        if provider == null or not is_instance_valid(provider):
            return _error("invalid_provider", key)
        if not provider.has_method("export_state") or not provider.has_method("restore_state") or not provider.has_method("can_restore_state"):
            return _error("unsupported_provider", key)
        var state_value: Variant = domains[key]
        if not state_value is Dictionary:
            return _error("invalid_domain_state", key)
        var state: Dictionary = state_value
        if not bool(provider.call("can_restore_state", state.duplicate(true))):
            return _error("restore_precheck_rejected", key)
        var current_value: Variant = provider.call("export_state")
        if not current_value is Dictionary:
            return _error("invalid_live_state", key)
        backups[key] = (current_value as Dictionary).duplicate(true)

    var applied: Array[String] = []
    for key_value in keys:
        var key := str(key_value)
        var provider: Object = providers[key_value]
        var state: Dictionary = domains[key]
        if not bool(provider.call("restore_state", state.duplicate(true))):
            for rollback_key in applied:
                var rollback_provider: Object = providers[rollback_key]
                rollback_provider.call("restore_state", (backups[rollback_key] as Dictionary).duplicate(true))
            return {
                "ok": false,
                "error": "restore_rejected",
                "domain": key,
                "rolled_back": true,
            }
        applied.append(key)

    return {"ok": true, "error": "", "domains_restored": applied}

static func _error(code: String, domain: String = "") -> Dictionary:
    return {"ok": false, "error": code, "domain": domain}
