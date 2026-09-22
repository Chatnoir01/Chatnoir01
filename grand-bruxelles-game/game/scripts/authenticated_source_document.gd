extends RefCounted

## Reads, authenticates, and parses one source document from one immutable byte capture.
## The caller remains responsible for canonicalizing path and expected SHA-256.

static func load_document(path: String, expected_sha: String) -> Dictionary:
    if path.is_empty() or expected_sha.is_empty():
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}

    var expected_length := file.get_length()
    if expected_length <= 0:
        return {}

    var bytes := file.get_buffer(expected_length)
    if bytes.size() != expected_length:
        return {}

    var hashing := HashingContext.new()
    if hashing.start(HashingContext.HASH_SHA256) != OK:
        return {}
    if hashing.update(bytes) != OK:
        return {}
    var actual_sha := hashing.finish().hex_encode().to_lower()
    if actual_sha.is_empty() or actual_sha != expected_sha:
        return {}

    var json_text := bytes.get_string_from_utf8()
    if json_text.is_empty():
        return {}
    var parsed: Variant = JSON.parse_string(json_text)
    if not parsed is Dictionary:
        return {}

    return {
        "document": parsed as Dictionary,
        "source_sha256": actual_sha,
    }
