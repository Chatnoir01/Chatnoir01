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


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _safe_payload_name(name: object) -> bool:
    if not isinstance(name, str) or not name or "\\" in name or "\x00" in name:
        return False
    p = PurePosixPath(name)
    # Require one canonical spelling. PurePosixPath otherwise silently folds
    # repeated separators, './' components and trailing separators, allowing
    # multiple evidence keys to address the same extracted payload. A bare '.'
    # is a special case: PurePosixPath('.') has no parts and serializes as '.',
    # so reject paths that do not identify at least one real file component.
    if not p.parts or p.is_absolute() or p.as_posix() != name or any(part in {"", ".", ".."} for part in p.parts):
        return False
    for part in p.parts:
        # Payload evidence must remain materializable on the Windows target as
        # well as POSIX. Reject controls/surrogates and every Win32-reserved
        # filename character; slash is already the component separator and
        # backslash is rejected before parsing.
        if (any(unicodedata.category(ch) in {"Cc", "Cs"} for ch in part)
                or any(ch in WINDOWS_FORBIDDEN_CHARS for ch in part)
                or part.endswith((" ", "."))):
            return False
        # Win32 also reserves DOS device aliases, including the ISO-8859-1
        # superscript forms COM¹/²/³ and LPT¹/²/³ plus console input/output.
        # Extensions do not make these aliases safe (for example COM¹.glb).
        if part.split(".", 1)[0].upper() in WINDOWS_DEVICES:
            return False
    return True


def _portable_payload_identity(name: str) -> str:
    """Identity on case-insensitive, Unicode-normalizing filesystems."""
    return unicodedata.normalize("NFC", name).casefold()


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
    is_adopted = UAL in adopted or c.get("decision") == "ADOPT"

    # Metadata alone may describe a candidate, but must never authorize intake.
    if c.get("pack_specific_license_claim") != "CC0-1.0":
        errors.append("UAL pack-specific license claim is no longer the audited CC0-1.0")
    if c.get("publisher_general_license_current") != "QAL-1.0":
        errors.append("UAL publisher general-license observation changed; re-audit required")

    if is_adopted:
        snapshot = c.get("license_snapshot_sha256")
        archive = c.get("acquired_archive_sha256")
        payloads = c.get("imported_payload_sha256")
        if not isinstance(snapshot, str) or not SHA256.fullmatch(snapshot):
            errors.append("adoption requires license_snapshot_sha256")
        if not isinstance(archive, str) or not SHA256.fullmatch(archive):
            errors.append("adoption requires acquired_archive_sha256")
        if not isinstance(payloads, dict) or not payloads:
            errors.append("adoption requires non-empty imported_payload_sha256 map")
        else:
            if any(not _safe_payload_name(k) for k in payloads):
                errors.append("every imported payload key must be a safe canonical portable relative POSIX path")
            safe_names = [k for k in payloads if isinstance(k, str) and _safe_payload_name(k)]
            identities = [_portable_payload_identity(k) for k in safe_names]
            if len(identities) != len(set(identities)):
                errors.append("imported payload paths must be unique under Unicode NFC + casefold")
            if any(not isinstance(v, str) or not SHA256.fullmatch(v) for v in payloads.values()):
                errors.append("every imported payload requires a lowercase SHA-256")
        for flag in ("godot_4_7_1_qualified", "web_gl_qualified", "retarget_ab_qualified", "player_view_1280x720_qualified"):
            if c.get(flag) is not True:
                errors.append(f"adoption requires literal true: {flag}")
    else:
        if c.get("decision") not in {"HOLD_FOR_LICENSE_SNAPSHOT_AND_RETARGET_AB", "REJECT"}:
            errors.append("non-adopted UAL must remain explicitly HOLD or REJECT")
    return errors


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: character_asset_intake_policy.py <audit.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        doc = json.loads(path.read_text(encoding="utf-8"), parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        print(f"FAIL: unreadable strict JSON: {exc}", file=sys.stderr)
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
