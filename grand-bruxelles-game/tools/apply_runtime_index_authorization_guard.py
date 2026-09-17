#!/usr/bin/env python3
"""Apply the preregistered runtime-index authorization repair byte-for-byte."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
EXPECTED_PRE_REPAIR_GIT_BLOB_SHA1 = "cf2b5e742e8967dc23f58a303412dd56df9bb9da"

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


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    raw = TARGET.read_bytes()
    current_blob = git_blob_sha1(raw)
    if current_blob != EXPECTED_PRE_REPAIR_GIT_BLOB_SHA1:
        raise SystemExit(f"refusing unexpected git_blob_sha1={current_blob}")
    text = raw.decode("utf-8")
    if text.count(OLD) != 1:
        raise SystemExit(f"refusing anchor_count={text.count(OLD)}")
    prefix, suffix = text.split(OLD)
    repaired = prefix + NEW + suffix
    if repaired.count(NEW) != 1 or repaired.count(OLD) != 0:
        raise SystemExit("replacement postcondition failed")
    if not repaired.startswith(prefix) or not repaired.endswith(suffix):
        raise SystemExit("byte-preservation postcondition failed")
    print(f"input_git_blob_sha1={current_blob}")
    print(f"output_git_blob_sha1={git_blob_sha1(repaired.encode('utf-8'))}")
    if args.write:
        TARGET.write_bytes(repaired.encode("utf-8"))
        print(f"wrote={TARGET}")
    else:
        print("dry_run=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
