extends RefCounted

## Reads, authenticates, and parses one source document from one immutable byte capture.
## The caller remains responsible for canonicalizing path; this primitive still
## validates the digest boundary itself so malformed descriptors fail closed.

static func _canonical_expected_sha256(raw_sha: String) -> String:
    if raw_sha.length() != 64:
        return ""
    for index: int in range(raw_sha.length()):
        var code := raw_sha.unicode_at(index)
        var decimal := code >= 48 and code <= 57
        var lowercase_hex := code >= 97 and code <= 102
        if not decimal and not lowercase_hex:
            return ""
    return raw_sha


static func load_document(path: String, expected_sha: String) -> Dictionary:
    if path.is_empty():
        return {}
    var canonical_expected_sha := _canonical_expected_sha256(expected_sha)
    if canonical_expected_sha.is_empty():
        return {}

    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}

    var expected_length := file.get_length()
    if expected_length <= 0:
        file.close()
        return {}

    var bytes := file.get_buffer(expected_length)
    var read_error := file.get_error()
    file.close()
    if bytes.size() != expected_length or read_error != OK:
        return {}

    var hashing := HashingContext.new()
    if hashing.start(HashingContext.HASH_SHA256) != OK:
        return {}
    if hashing.update(bytes) != OK:
        return {}
    var actual_sha := hashing.finish().hex_encode().to_lower()
    if actual_sha.is_empty() or actual_sha != canonical_expected_sha:
        return {}

    # JSON sources are canonical UTF-8 text. Reject malformed UTF-8 instead of
    # allowing decoder replacement characters to create a parsed document that
    # is not a lossless representation of the authenticated byte capture.
    var json_text := bytes.get_string_from_utf8()
    if json_text.is_empty() or json_text.to_utf8_buffer() != bytes:
        return {}
    var parsed: Variant = JSON.parse_string(json_text)
    if not parsed is Dictionary:
        return {}

    return {
        "document": parsed as Dictionary,
        "source_sha256": actual_sha,
    }
