#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
DIGEST_VALIDATOR = PROJECT / "tools" / "validate_road_destination_source_lock.py"
CROSSWALK_VALIDATOR = PROJECT / "tools" / "validate_required_building_urbis_crosswalk_lock.py"
LOCK = PROJECT / "data" / "osm" / "road_destination_sources.lock.json"
SOURCE = PROJECT / "data" / "osm" / "vertical_slice_01.game.json"
SOURCE_KEY = "data/osm/vertical_slice_01.game.json"


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=PROJECT, capture_output=True, text=True, check=False)


def main() -> int:
    source_doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    lock_doc = json.loads(LOCK.read_text(encoding="utf-8"))
    building = source_doc["corridor"]["required_buildings"][0]
    assert building["osm_type"] == "way" and building["osm_id"] == 13494623
    height = building["evidence"]["height"]
    assert height["dataset_id"] == "e9ec2aa4-cffd-11ee-bccc-00090ffe0001"

    # Causal witness: keep the top-level crosswalk and approval untouched, but drift
    # the official LoD2 evidence identity. Recompute the document digest exactly as a
    # malicious/accidental source rewrite could. The digest validator currently accepts
    # this; the semantic evidence lock must reject it independently of the digest.
    height["dataset_id"] = "e9ec2aa4-cffd-11ee-bccc-00090ffe9999"

    with tempfile.TemporaryDirectory(prefix="gb-bourse-evidence-lock-") as tmp:
        root = Path(tmp)
        source_root = root / "data" / "osm"
        source_root.mkdir(parents=True)
        source_path = source_root / "vertical_slice_01.game.json"
        source_bytes = json.dumps(source_doc, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
        source_path.write_bytes(source_bytes)

        lock_doc["documents"][SOURCE_KEY] = hashlib.sha256(source_bytes).hexdigest()
        lock_path = source_root / "road_destination_sources.lock.json"
        lock_path.write_text(json.dumps(lock_doc, sort_keys=True, allow_nan=False), encoding="utf-8")

        digest_only = run([
            sys.executable,
            str(DIGEST_VALIDATOR),
            "--source-root",
            str(source_root),
            "--lock",
            str(lock_path),
        ])
        assert digest_only.returncode == 0, digest_only.stdout + digest_only.stderr

        semantic = run([sys.executable, str(CROSSWALK_VALIDATOR), "--source", str(source_path)])
        assert semantic.returncode != 0, (
            "Bourse official evidence identity drift remained accepted after digest recomputation; "
            "the semantic lock must fail closed\n" + semantic.stdout + semantic.stderr
        )

    print("REQUIRED_BUILDING_EVIDENCE_IDENTITY_LOCK_TEST_OK network_used=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
