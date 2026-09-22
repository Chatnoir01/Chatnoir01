#!/usr/bin/env python3
"""Fail-closed policy gate for Character/NPC third-party asset intake."""
from __future__ import annotations
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path, PurePosixPath

SHA256 = re.compile(r"^[0-9a-f]{64}$")
UAL = "Universal Animation Library"
WINDOWS_DEVICES = {
    "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$",
    *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10)),
    "COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³",
}
WINDOWS_FORBIDDEN_CHARS = set('<>:"|?*')
MAX_COMPONENT_UTF8_BYTES = 255
MAX_COMPONENT_UTF16_UNITS = 255
RUNTIME_CHARACTER_EXTENSIONS = {".glb", ".gltf", ".fbx", ".anim", ".res", ".tres"}


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _credible_sha256(value: object) -> bool:
    """Reject malformed and obvious sentinel/placeholder digests from evidence."""
    return isinstance(value, str) and bool(SHA256.fullmatch(value)) and len(set(value)) > 1


def _reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict:
    """Build a JSON object without silently accepting last-key-wins ambiguity."""
    out: dict = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON object key: {key!r}")
        out[key] = value
    return out


def _strict_json_loads(text: str) -> object:
    return json.loads(
        text,
        parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)),
        object_pairs_hook=_reject_duplicate_keys,
    )


def _is_unicode_noncharacter(ch: str) -> bool:
    cp = ord(ch)
    return 0xFDD0 <= cp <= 0xFDEF or (cp & 0xFFFF) in {0xFFFE, 0xFFFF}


def _safe_payload_name(name: object) -> bool:
    if not isinstance(name, str) or not name or "\\" in name or "\x00" in name:
        return False
    p = PurePosixPath(name)
    if not p.parts or p.is_absolute() or p.as_posix() != name or any(part in {"", ".", ".."} for part in p.parts):
        return False
    for part in p.parts:
        if unicodedata.normalize("NFC", part) != part:
            return False
        if (any(unicodedata.category(ch) in {"Cc", "Cf", "Cs"} or _is_unicode_noncharacter(ch) for ch in part)
                or any(ch in WINDOWS_FORBIDDEN_CHARS for ch in part)
                or part.endswith((" ", "."))):
            return False
        try:
            utf8_len = len(part.encode("utf-8", errors="strict"))
            utf16_units = len(part.encode("utf-16-le", errors="strict")) // 2
        except UnicodeEncodeError:
            return False
        if utf8_len > MAX_COMPONENT_UTF8_BYTES or utf16_units > MAX_COMPONENT_UTF16_UNITS:
            return False
        if part.split(".", 1)[0].upper() in WINDOWS_DEVICES:
            return False
    return True


def _portable_payload_identity(name: str) -> str:
    return unicodedata.normalize("NFC", name).casefold()


def _has_runtime_character_payload(payloads: dict) -> bool:
    return any(
        isinstance(name, str) and PurePosixPath(name).suffix.casefold() in RUNTIME_CHARACTER_EXTENSIONS
        for name in payloads
    )


def validate(doc: dict) -> list[str]:
    errors: list[str] = []
    candidates = doc.get("candidates")
    if not isinstance(candidates, list):
        return ["candidates must be a list"]
    matches = [c for c in candidates if isinstance(c, dict) and c.get("name") == UAL]
    if len(matches) != 1:
        return [f"expected exactly one {UAL} candidate"]
    c = matches[0]
    adopted = doc.get("adopted")
    if not isinstance(adopted, list):
        errors.append("adopted must be a list")
        adopted = []
    elif any(not isinstance(name, str) for name in adopted):
        errors.append("adopted entries must all be strings")
    if adopted.count(UAL) > 1:
        errors.append(f"adopted must contain {UAL} at most once")

    listed_adopted = UAL in adopted
    decision_adopted = c.get("decision") == "ADOPT"
    if listed_adopted != decision_adopted:
        errors.append(f"{UAL} adoption state must agree between adopted list and candidate decision")
    is_adopted = listed_adopted and decision_adopted

    if c.get("pack_specific_license_claim") != "CC0-1.0":
        errors.append("UAL pack-specific license claim is no longer the audited CC0-1.0")
    if c.get("publisher_general_license_current") != "QAL-1.0":
        errors.append("UAL publisher general-license observation changed; re-audit required")

    if is_adopted:
        snapshot = c.get("license_snapshot_sha256")
        archive = c.get("acquired_archive_sha256")
        payloads = c.get("imported_payload_sha256")
        if not _credible_sha256(snapshot):
            errors.append("adoption requires a non-placeholder license_snapshot_sha256")
        if not _credible_sha256(archive):
            errors.append("adoption requires a non-placeholder acquired_archive_sha256")
        if not isinstance(payloads, dict) or not payloads:
            errors.append("adoption requires non-empty imported_payload_sha256 map")
        else:
            if any(not _safe_payload_name(k) for k in payloads):
                errors.append("every imported payload key must be a safe canonical portable relative POSIX path")
            safe_names = [k for k in payloads if isinstance(k, str) and _safe_payload_name(k)]
            identities = [_portable_payload_identity(k) for k in safe_names]
            if len(identities) != len(set(identities)):
                errors.append("imported payload paths must be unique under Unicode NFC + casefold")
            if any(not _credible_sha256(v) for v in payloads.values()):
                errors.append("every imported payload requires a non-placeholder lowercase SHA-256")
            if not _has_runtime_character_payload(payloads):
                errors.append("adoption requires at least one imported runtime character/animation payload")
        for flag in ("godot_4_7_1_qualified", "web_gl_qualified", "retarget_ab_qualified", "foot_slide_grounding_qualified", "performance_budget_qualified", "player_view_1280x720_qualified"):
            if c.get(flag) is not True:
                errors.append(f"adoption requires literal true: {flag}")
    else:
        if c.get("decision") not in {"HOLD_FOR_LICENSE_SNAPSHOT_AND_RETARGET_AB", "REJECT", "ADOPT"}:
            errors.append("non-adopted UAL must remain explicitly HOLD or REJECT")
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: character_asset_intake_policy.py <audit.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        doc = _strict_json_loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: unreadable strict JSON: {exc}", file=sys.stderr)
        return 1
    if not isinstance(doc, dict):
        print("FAIL: top-level JSON must be an object", file=sys.stderr)
        return 1
    errors = validate(doc)
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print(f"PASS: Character asset intake policy ({_sha256_file(path)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
