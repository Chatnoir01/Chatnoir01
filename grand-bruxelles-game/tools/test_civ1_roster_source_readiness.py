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

        ready_status = {
            "candidate_id": "CIV-1",
            "production_authorized": True,
            "activation_ready": True,
            "source_package_present": True,
            "character_source": {"license_evidence": {"unresolved_components": []}},
            "source_manifest": {
                "assets/characters/civilians/civ1/source/body.glb": {
                    "license_scope_verified": True
                }
            },
        }
        status.write_text(json.dumps(ready_status), encoding="utf-8")
        assert source_ready(root) is True
        assert blocking_entries(registry, root) == []

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
        unverified_manifest["source_manifest"][
            "assets/characters/civilians/civ1/source/body.glb"
        ]["license_scope_verified"] = False
        status.write_text(json.dumps(unverified_manifest), encoding="utf-8")
        assert source_ready(root) is False, (
            "CIV-1 must not become roster-ready while any source manifest item has "
            "license_scope_verified=false"
        )

        wrong_candidate = json.loads(json.dumps(ready_status))
        wrong_candidate["candidate_id"] = "OTHER"
        status.write_text(json.dumps(wrong_candidate), encoding="utf-8")
        assert source_ready(root) is False, "readiness status must be bound to CIV-1 identity"

    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")


if __name__ == "__main__":
    main()
