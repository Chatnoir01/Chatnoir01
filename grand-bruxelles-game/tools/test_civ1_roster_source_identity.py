#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, struct, tempfile
from pathlib import Path
from civ1_roster_registration_truth import build_payload

REGISTRY_SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"
SOURCE = "https://example.invalid/source/shared-civilian.glb"

def glb(doc):
    payload = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((4 - len(payload) % 4) % 4)
    total = 20 + len(payload)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(payload), b"JSON") + payload

def entry(path, sha, role):
    return {
        "asset_path": path,
        "role": role,
        "sha256": sha,
        "source_url": SOURCE,
        "license": "CC0-1.0",
    }

def main():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel_a = "grand-bruxelles-game/assets/characters/civilian_identity_a.glb"
        rel_b = "grand-bruxelles-game/assets/characters/civilian_identity_b.glb"
        path_a, path_b = root / rel_a, root / rel_b
        path_a.parent.mkdir(parents=True)
        path_a.write_bytes(glb({"asset":"a"}))
        path_b.write_bytes(glb({"asset":"b"}))
        sha_a = hashlib.sha256(path_a.read_bytes()).hexdigest()
        sha_b = hashlib.sha256(path_b.read_bytes()).hexdigest()
        assert sha_a != sha_b

        payload = build_payload(
            {
                "schema": REGISTRY_SCHEMA,
                "entries": [entry(rel_a, sha_a, "civilian"), entry(rel_b, sha_b, "police")],
            },
            root,
        )

        assert "duplicate_source_url" in payload["blocking_reasons"]
        assert payload["eligible_count"] == 0
        assert payload["invalid_entry_count"] == 2
        assert all("duplicate_source_url" in item["blocking_reasons"] for item in payload["entries"])
    print("CIV1_ROSTER_SOURCE_IDENTITY_GREEN")

if __name__ == "__main__":
    main()
