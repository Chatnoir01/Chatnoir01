#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import tempfile
from pathlib import Path

from civ1_roster_source_readiness import source_ready


def git_blob_sha1(data: bytes) -> str:
    digest = hashlib.sha1()
    digest.update(f"blob {len(data)}\0".encode("ascii"))
    digest.update(data)
    return digest.hexdigest()


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source_path = "assets/characters/civilians/civ1/source/body.glb"
        source_file = root / "grand-bruxelles-game" / source_path
        source_file.parent.mkdir(parents=True)
        payload = b"civ1-runtime-readiness"
        source_file.write_bytes(payload)

        status_path = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
        status = {
            "candidate_id": "CIV-1",
            "production_authorized": True,
            "activation_ready": True,
            "source_package_present": True,
            "runtime_package_present": False,
            "blocker": None,
            "character_source": {
                "repository": "https://github.com/ibrews/VitruvianGodot",
                "commit": "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0",
                "license_claim": "MIXED_BY_COMPONENT",
                "license_evidence": {"unresolved_components": []},
            },
            "source_paths": [source_path],
            "source_manifest": {
                source_path: {
                    "upstream_path": "godot_project/body.glb",
                    "license_scope_verified": True,
                    "license": "CC0-1.0",
                    "git_blob_sha1": git_blob_sha1(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                    "size_bytes": len(payload),
                }
            },
        }

        status_path.write_text(json.dumps(status), encoding="utf-8")
        assert source_ready(root) is False, (
            "CIV-1 must remain fail-closed when source/provenance is ready but "
            "the runtime package is explicitly absent"
        )

        readiness_flags = (
            "production_authorized",
            "activation_ready",
            "source_package_present",
            "runtime_package_present",
        )
        impostors = (1, "true", [True], {"present": True})
        for flag in readiness_flags:
            for impostor in impostors:
                candidate = dict(status)
                candidate.update({name: True for name in readiness_flags})
                candidate[flag] = impostor
                status_path.write_text(json.dumps(candidate), encoding="utf-8")
                assert source_ready(root) is False, (
                    f"{flag} must be the JSON boolean true, not a truthy "
                    f"lookalike: {impostor!r}"
                )

        for flag in readiness_flags:
            candidate = dict(status)
            candidate.update({name: True for name in readiness_flags})
            candidate.pop(flag)
            status_path.write_text(json.dumps(candidate), encoding="utf-8")
            assert source_ready(root) is False, f"missing {flag} must fail closed"

            for negative in (False, None):
                candidate = dict(status)
                candidate.update({name: True for name in readiness_flags})
                candidate[flag] = negative
                status_path.write_text(json.dumps(candidate), encoding="utf-8")
                assert source_ready(root) is False, (
                    f"{flag}={negative!r} must not authorize CIV-1"
                )

        # A ready record must state unambiguously that no blocker exists.
        for ambiguous_blocker in ("", False, 0, [], {}):
            candidate = dict(status)
            candidate.update({name: True for name in readiness_flags})
            candidate["blocker"] = ambiguous_blocker
            status_path.write_text(json.dumps(candidate), encoding="utf-8")
            assert source_ready(root) is False, (
                f"ready CIV-1 blocker must be explicit JSON null, not {ambiguous_blocker!r}"
            )
        candidate = dict(status)
        candidate.update({name: True for name in readiness_flags})
        candidate.pop("blocker")
        status_path.write_text(json.dumps(candidate), encoding="utf-8")
        assert source_ready(root) is False, "missing blocker must fail closed"

        # Readiness must remain bound to the reviewed CIV-1 upstream identity.
        # Valid local hashes and a permissive license must not authorize a substituted source.
        identity_impostors = {
            "repository": "https://github.com/example/lookalike-character",
            "commit": "0" * 40,
            "license_claim": "CC0-1.0",
        }
        for field, impostor in identity_impostors.items():
            candidate = dict(status)
            candidate.update({name: True for name in readiness_flags})
            candidate["character_source"] = dict(status["character_source"])
            candidate["character_source"][field] = impostor
            status_path.write_text(json.dumps(candidate), encoding="utf-8")
            assert source_ready(root) is False, (
                f"substituted CIV-1 character_source.{field} must fail closed"
            )

        status.update({name: True for name in readiness_flags})
        status_path.write_text(json.dumps(status), encoding="utf-8")
        assert source_ready(root) is True, (
            "runtime-package presence plus reviewed upstream identity and explicit null blocker must complete readiness"
        )

    print("CIV1_ROSTER_RUNTIME_PACKAGE_READINESS_GREEN")


if __name__ == "__main__":
    main()
