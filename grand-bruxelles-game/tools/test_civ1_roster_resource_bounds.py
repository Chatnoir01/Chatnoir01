#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

import civ1_roster_resource_bounds as bounds
import civ1_roster_source_readiness as readiness


def _paths(root: Path):
    status = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
    payload = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source/civ.glb"
    status.parent.mkdir(parents=True, exist_ok=True)
    payload.parent.mkdir(parents=True, exist_ok=True)
    return status, payload


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        status, payload = _paths(root)
        payload.write_bytes(b"GLB!")
        doc = {
            "source_paths": ["assets/characters/civilians/civ1/source/civ.glb"],
            "source_manifest": {
                "assets/characters/civilians/civ1/source/civ.glb": {"size_bytes": 4}
            },
        }
        status.write_text(json.dumps(doc), encoding="utf-8")
        assert bounds.status_within_bound(root), "small regular status must pass the pre-read bound"
        assert bounds.payload_sizes_match_manifest(root, doc), "manifest-bound payload size must pass"
        assert readiness._read_regular_single_link(status, readiness.MAX_STATUS_BYTES) is not None, "canonical reader must accept bounded status"
        assert readiness._read_regular_single_link(payload, 4) == b"GLB!", "canonical reader must accept exact-size payload"

        payload.write_bytes(b"GLB!!")
        assert not bounds.payload_sizes_match_manifest(root, doc), "size mismatch must fail before payload hashing/read"
        assert readiness._read_regular_single_link(payload, 4) is None, "canonical reader must reject payload larger than manifest bound"

        payload.write_bytes(b"GLB!")
        with status.open("wb") as stream:
            stream.truncate(bounds.MAX_STATUS_BYTES + 1)
        assert not bounds.status_within_bound(root), "oversized sparse status must fail before JSON read"
        assert readiness._read_regular_single_link(status, readiness.MAX_STATUS_BYTES) is None, "canonical reader must reject oversized status before reading it"
        assert not readiness.source_ready(root), "canonical readiness must fail closed on oversized status"

    print("CIV1_ROSTER_RESOURCE_BOUNDS_REGRESSION_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
