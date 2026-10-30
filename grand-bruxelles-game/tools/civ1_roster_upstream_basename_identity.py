#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import unicodedata
from pathlib import Path, PurePosixPath


class DuplicateJSONKeyError(ValueError):
    pass


class NonStandardJSONConstantError(ValueError):
    pass


class InvalidUTF8StatusError(ValueError):
    pass


SOURCE_ROOT = "assets/characters/civilians/civ1/source/"
WINDOWS_MAX_COMPONENT_UTF16_UNITS = 255


def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateJSONKeyError(key)
        result[key] = value
    return result


def _reject_nonstandard_constant(value: str):
    raise NonStandardJSONConstantError(value)


def load_status(path: Path) -> object:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise InvalidUTF8StatusError(f"invalid UTF-8 at byte {exc.start}") from exc
    return json.loads(text, object_pairs_hook=_reject_duplicate_keys, parse_constant=_reject_nonstandard_constant)


def _is_windows_device_leaf(leaf: str) -> bool:
    stem = leaf.split(".", 1)[0].upper()
    if stem in {"CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"}:
        return True
    return len(stem) == 4 and stem[:3] in {"COM", "LPT"} and stem[3] in "123456789\u00b9\u00b2\u00b3"


def _utf16_code_units(value: str) -> int:
    try:
        return len(value.encode("utf-16-le")) // 2
    except UnicodeEncodeError:
        return WINDOWS_MAX_COMPONENT_UTF16_UNITS + 1


def _portable_segment(segment: str) -> bool:
    return bool(segment) and segment not in (".", "..") and (
        segment.rstrip(" .") == segment
        and unicodedata.normalize("NFC", segment) == segment
        and not any(unicodedata.category(char).startswith("C") for char in segment)
        and _utf16_code_units(segment) <= WINDOWS_MAX_COMPONENT_UTF16_UNITS
        and not any(char in '<>:"\\|?*' for char in segment)
        and not _is_windows_device_leaf(segment)
    )


def _canonical_leaf(path: str) -> str | None:
    parts = path.split("/")
    if (
        "\\" in path
        or path.startswith("/")
        or (parts and len(parts[0]) == 2 and parts[0][0].isalpha() and parts[0][1] == ":")
        or not all(_portable_segment(part) for part in parts)
    ):
        return None
    leaf = PurePosixPath(path).name
    raw_leaf = parts[-1]
    if raw_leaf != leaf:
        return None
    return leaf


def _windows_identity(path: str) -> str:
    return "/".join(part.casefold() for part in path.split("/"))


def mismatches(status: object) -> list[dict[str, str]]:
    if not isinstance(status, dict):
        return [{"source_path": "<status>", "upstream_path": "<invalid>"}]
    manifest = status.get("source_manifest")
    if not isinstance(manifest, dict):
        return [{"source_path": "<manifest>", "upstream_path": "<invalid>"}]
    bad: list[dict[str, str]] = []
    seen_source_windows: dict[str, str] = {}
    seen_upstream_windows: dict[str, str] = {}
    for source_path, record in manifest.items():
        if not isinstance(source_path, str) or not isinstance(record, dict):
            bad.append({"source_path": str(source_path), "upstream_path": "<invalid>"})
            continue
        upstream_path = record.get("upstream_path")
        if not isinstance(upstream_path, str):
            bad.append({"source_path": source_path, "upstream_path": "<missing>"})
            continue
        if not source_path.startswith(SOURCE_ROOT) or source_path == SOURCE_ROOT:
            bad.append({"source_path": source_path, "upstream_path": upstream_path})
            continue
        source_leaf = _canonical_leaf(source_path)
        upstream_leaf = _canonical_leaf(upstream_path)
        if source_leaf is None or upstream_leaf is None or source_leaf != upstream_leaf:
            bad.append({"source_path": source_path, "upstream_path": upstream_path})
            continue
        source_key = _windows_identity(source_path)
        upstream_key = _windows_identity(upstream_path)
        source_alias = seen_source_windows.get(source_key)
        upstream_alias = seen_upstream_windows.get(upstream_key)
        if (source_alias is not None and source_alias != source_path) or (upstream_alias is not None and upstream_alias != upstream_path):
            bad.append({"source_path": source_path, "upstream_path": upstream_path})
            continue
        seen_source_windows[source_key] = source_path
        seen_upstream_windows[upstream_key] = upstream_path
    return bad


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("status", type=Path)
    args = parser.parse_args()
    try:
        status = load_status(args.status)
    except (OSError, UnicodeError, json.JSONDecodeError, DuplicateJSONKeyError, NonStandardJSONConstantError, InvalidUTF8StatusError) as exc:
        print(f"CIV1_UPSTREAM_BASENAME_IDENTITY_ERROR {exc}")
        return 2
    bad = mismatches(status)
    if bad:
        print("CIV1_UPSTREAM_BASENAME_IDENTITY_MISMATCH " + json.dumps(bad, sort_keys=True))
        return 2
    print("CIV1_UPSTREAM_BASENAME_IDENTITY_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
