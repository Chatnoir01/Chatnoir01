extends RefCounted
class_name SaveGameStore

const SCHEMA_VERSION: int = 1
const MAX_SAVE_BYTES: int = 4 * 1024 * 1024


static func write_snapshot(path: String, payload: Dictionary) -> Dictionary:
    if path.is_empty():
        return _error("invalid_path")

    var payload_json: String = JSON.stringify(payload)
    var envelope: Dictionary = {
        "schema_version": SCHEMA_VERSION,
        "payload_json": payload_json,
        "payload_sha256": _sha256(payload_json),
    }
    var envelope_json: String = JSON.stringify(envelope)
    if envelope_json.to_utf8_buffer().size() > MAX_SAVE_BYTES:
        return _error("save_too_large")

    var absolute_path: String = ProjectSettings.globalize_path(path)
    var directory: String = absolute_path.get_base_dir()
    var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
    if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
        return _error("create_directory_failed", mkdir_error)

    var temp_path: String = absolute_path + ".tmp"
    var backup_path: String = absolute_path + ".bak"
    _remove_if_exists(temp_path)
    _remove_if_exists(backup_path)

    var temp_file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
    if temp_file == null:
        return _error("open_temp_failed", FileAccess.get_open_error())
    temp_file.store_string(envelope_json)
    temp_file.flush()
    temp_file.close()

    var had_previous: bool = FileAccess.file_exists(absolute_path)
    if had_previous:
        var backup_error: Error = DirAccess.rename_absolute(absolute_path, backup_path)
        if backup_error != OK:
            _remove_if_exists(temp_path)
            return _error("backup_existing_failed", backup_error)

    var promote_error: Error = DirAccess.rename_absolute(temp_path, absolute_path)
    if promote_error != OK:
        if had_previous and FileAccess.file_exists(backup_path):
            DirAccess.rename_absolute(backup_path, absolute_path)
        _remove_if_exists(temp_path)
        return _error("promote_temp_failed", promote_error)

    _remove_if_exists(backup_path)
    return {"ok": true, "error": ""}


static func read_snapshot(path: String) -> Dictionary:
    if path.is_empty():
        return _error("invalid_path")
    if not FileAccess.file_exists(path):
        return _error("not_found")

    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return _error("open_failed", FileAccess.get_open_error())
    if file.get_length() > MAX_SAVE_BYTES:
        file.close()
        return _error("save_too_large")
    var envelope_text: String = file.get_as_text()
    file.close()

    var parsed_envelope: Variant = JSON.parse_string(envelope_text)
    if not parsed_envelope is Dictionary:
        return _error("invalid_json")
    var envelope: Dictionary = parsed_envelope
    if int(envelope.get("schema_version", -1)) != SCHEMA_VERSION:
        return _error("unsupported_schema")

    var payload_json: String = str(envelope.get("payload_json", ""))
    var expected_sha: String = str(envelope.get("payload_sha256", ""))
    if payload_json.is_empty() or expected_sha.is_empty():
        return _error("missing_payload")
    if _sha256(payload_json) != expected_sha:
        return _error("checksum_mismatch")

    var parsed_payload: Variant = JSON.parse_string(payload_json)
    if not parsed_payload is Dictionary:
        return _error("invalid_payload")
    return {"ok": true, "error": "", "payload": parsed_payload}


static func _sha256(text: String) -> String:
    var context: HashingContext = HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(text.to_utf8_buffer())
    return context.finish().hex_encode()


static func _remove_if_exists(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(path)


static func _error(code: String, os_error: int = OK) -> Dictionary:
    return {"ok": false, "error": code, "os_error": os_error}
