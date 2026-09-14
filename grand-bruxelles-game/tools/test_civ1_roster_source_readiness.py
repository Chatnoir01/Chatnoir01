#!/usr/bin/env python3
from __future__ import annotations
import json, tempfile
from pathlib import Path
from civ1_roster_source_readiness import blocking_entries, source_ready


def main():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        status = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
        status.parent.mkdir(parents=True)
        registry = {
            "schema": "grand-bruxelles-civ1-roster-registry-v1",
            "entries": [
                {"asset_path": "grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}
            ],
        }

        blocked_status = {
            "production_authorized": False,
            "activation_ready": False,
            "source_package_present": False,
            "blocker": "source_not_ready",
        }
        status.write_text(json.dumps(blocked_status), encoding="utf-8")
        assert source_ready(root) is False
        assert blocking_entries(registry, root) == [
            "grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"
        ]

        source_path = "assets/characters/civilians/civ1/source/body.glb"
        source_file = root / "grand-bruxelles-game" / source_path
        source_file.parent.mkdir(parents=True)
        source_file.write_bytes(b"civ1-source-body")
        ready_status = {
            "candidate_id": "CIV-1",
            "production_authorized": True,
            "activation_ready": True,
            "source_package_present": True,
            "blocker": None,
            "character_source": {"license_evidence": {"unresolved_components": []}},
            "source_paths": [source_path],
            "source_manifest": {
                source_path: {
                    "license_scope_verified": True,
                    "git_blob_sha1": "3914b89458e542b73f0168b0bf80c8e356e78f9c",
                    "size_bytes": 16,
                }
            },
        }
        status.write_text(json.dumps(ready_status), encoding="utf-8")
        assert source_ready(root) is True
        assert blocking_entries(registry, root) == []

        # A manifest path must identify a real regular source file, not merely
        # resolve to matching bytes through an alias. The historical gate used
        # Path.resolve(), so an in-root symlink to an identical blob passed.
        backing_file = source_file.with_name("body-backing.glb")
        source_file.unlink()
        backing_file.write_bytes(b"civ1-source-body")
        source_file.symlink_to(backing_file.name)
        status.write_text(json.dumps(ready_status), encoding="utf-8")
        assert source_ready(root) is False, (
            "CIV-1 readiness must reject symlinked source paths even when the target remains "
            "inside the source root and has the declared bytes"
        )
        source_file.unlink()
        backing_file.unlink()
        source_file.write_bytes(b"civ1-source-body")

        missing_source = json.loads(json.dumps(ready_status))
        source_file.unlink()
        status.write_text(json.dumps(missing_source), encoding="utf-8")
        assert source_ready(root) is False, (
            "source_package_present=true must be grounded in an actual source file"
        )
        source_file.write_bytes(b"civ1-source-body")

        tampered_source = json.loads(json.dumps(ready_status))
        source_file.write_bytes(b"tampered-civ1-source")
        status.write_text(json.dumps(tampered_source), encoding="utf-8")
        assert source_ready(root) is False, (
            "CIV-1 readiness must bind each source file to its declared Git blob SHA-1 and size"
        )
        source_file.write_bytes(b"civ1-source-body")

        missing_integrity = json.loads(json.dumps(ready_status))
        del missing_integrity["source_manifest"][source_path]["git_blob_sha1"]
        status.write_text(json.dumps(missing_integrity), encoding="utf-8")
        assert source_ready(root) is False, (
            "every ready source manifest record must carry immutable Git blob identity"
        )

        unresolved_license = json.loads(json.dumps(ready_status))
        unresolved_license["character_source"]["license_evidence"]["unresolved_components"] = [
            "body.glb#embedded_animation_payload"
        ]
        status.write_text(json.dumps(unresolved_license), encoding="utf-8")
        assert source_ready(root) is False, (
            "CIV-1 must not become roster-ready while license evidence still lists "
            "unresolved components"
        )

        unverified_manifest = json.loads(json.dumps(ready_status))
        unverified_manifest["source_manifest"][source_path]["license_scope_verified"] = False
        status.write_text(json.dumps(unverified_manifest), encoding="utf-8")
        assert source_ready(root) is False, (
            "CIV-1 must not become roster-ready while any source manifest item has "
            "license_scope_verified=false"
        )

        wrong_candidate = json.loads(json.dumps(ready_status))
        wrong_candidate["candidate_id"] = "OTHER"
        status.write_text(json.dumps(wrong_candidate), encoding="utf-8")
        assert source_ready(root) is False, "readiness status must be bound to CIV-1 identity"

        stale_blocker = json.loads(json.dumps(ready_status))
        stale_blocker["blocker"] = "independently_licensed_idle_walk_run_not_verified"
        status.write_text(json.dumps(stale_blocker), encoding="utf-8")
        assert source_ready(root) is False, "ready flags must not override an active blocker"

        manifest_mismatch = json.loads(json.dumps(ready_status))
        manifest_mismatch["source_paths"].append(
            "assets/characters/civilians/civ1/source/hair.glb"
        )
        status.write_text(json.dumps(manifest_mismatch), encoding="utf-8")
        assert source_ready(root) is False, "source_paths and source_manifest must match exactly"

    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")


if __name__ == "__main__":
    main()
