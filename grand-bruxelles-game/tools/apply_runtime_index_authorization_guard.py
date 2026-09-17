#!/usr/bin/env python3
"""Apply the preregistered runtime-index authorization repair without reconstructing the GDScript.

Fail closed unless the input blob is exactly the reviewed pre-repair blob and every
replacement anchor occurs exactly once. This tool intentionally changes only the
_load_runtime_index authorization block.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
EXPECTED_PRE_REPAIR_SHA256 = "b92efc5a26f7f4ad3c62bcedf9b3f12f9d2b948f03124db6d31eb3a8c15cb73b"

OLD = '''    if not bool(index.get("source_lookup_only", false)):
        return false
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary:
        return false
    var auth := authorization as Dictionary
    if not bool(auth.get("source_lookup_only", false)):
        return false
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool(auth.get(forbidden, true)):
            return false

    var documents: Variant = index.get("documents", [])
'''

NEW = '''    var index_source_lookup_only: Variant = index.get("source_lookup_only", false)
    if typeof(index_source_lookup_only) != TYPE_BOOL or not bool(index_source_lookup_only):
        return false
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary:
        return false
    var auth := authorization as Dictionary
    var allowed_authorization_keys: Array[String] = ["source_lookup_only", "render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized", "destination_advertisable"]
    for authorization_key: Variant in auth.keys():
        if typeof(authorization_key) != TYPE_STRING or not allowed_authorization_keys.has(str(authorization_key)):
            return false
    var source_lookup_only: Variant = auth.get("source_lookup_only", false)
    if typeof(source_lookup_only) != TYPE_BOOL or not bool(source_lookup_only):
        return false
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        var forbidden_value: Variant = auth.get(forbidden, true)
        if typeof(forbidden_value) != TYPE_BOOL or bool(forbidden_value):
            return false
    var destination_advertisable: Variant = auth.get("destination_advertisable", true)
    if typeof(destination_advertisable) != TYPE_BOOL or bool(destination_advertisable):
        return false

    var documents: Variant = index.get("documents", [])
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="replace the reviewed anchor in place")
    parser.add_argument("--allow-current-sha", action="store_true", help="use the current file SHA as the precondition; for connector-reviewed exact-head use only")
    args = parser.parse_args()

    raw = TARGET.read_bytes()
    text = raw.decode("utf-8")
    current_sha = digest(raw)
    if not args.allow_current_sha and current_sha != EXPECTED_PRE_REPAIR_SHA256:
        raise SystemExit(f"refusing unexpected input sha256={current_sha}")
    if text.count(OLD) != 1:
        raise SystemExit(f"refusing anchor_count={text.count(OLD)}")
    repaired = text.replace(OLD, NEW, 1)
    if repaired.count(NEW) != 1 or repaired.count(OLD) != 0:
        raise SystemExit("replacement postcondition failed")
    before_prefix, before_suffix = text.split(OLD)
    after_prefix, after_suffix = repaired.split(NEW)
    if before_prefix != after_prefix or before_suffix != after_suffix:
        raise SystemExit("byte-preservation postcondition failed")
    print(f"input_sha256={current_sha}")
    print(f"output_sha256={digest(repaired.encode('utf-8'))}")
    if args.write:
        TARGET.write_text(repaired, encoding="utf-8", newline="")
        print(f"wrote={TARGET}")
    else:
        print("dry_run=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
