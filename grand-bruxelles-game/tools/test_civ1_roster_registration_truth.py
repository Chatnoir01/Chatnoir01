#!/usr/bin/env python3
from __future__ import annotations

import hashlib, json, struct, subprocess, sys, tempfile
from pathlib import Path
from civ1_roster_registration_truth import PLAYER_ASSET, build_payload, validate_entry


def entry(path: str, sha: str, role: str = "civilian", source_url: str = "https://example.invalid/source") -> dict[str, str]:
    return {"asset_path": path, "role": role, "sha256": sha, "source_url": source_url, "license": "CC0-1.0"}


def minimal_glb() -> bytes:
    json_chunk = b"{}  "
    total = 12 + 8 + len(json_chunk)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = "grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset = root / rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(minimal_glb())
        sha = hashlib.sha256(asset.read_bytes()).hexdigest()

        good = validate_entry(entry(rel, sha), root)
        assert good["valid"] is True and good["roster_eligible"] is True

        fake_rel = "grand-bruxelles-game/assets/characters/civilian_fake.glb"
        fake = root / fake_rel
        fake.write_bytes(b"not-a-glb-character")
        fake_sha = hashlib.sha256(fake.read_bytes()).hexdigest()
        fake_result = validate_entry(entry(fake_rel, fake_sha), root)
        assert "glb_container_invalid" in fake_result["blocking_reasons"], "v9 fail-open reproduced: arbitrary bytes were accepted as a Character GLB"
        assert fake_result["roster_eligible"] is False

        wrong = validate_entry(entry(rel, "0" * 64), root)
        assert "sha256_mismatch" in wrong["blocking_reasons"]
        missing_license = entry(rel, sha)
        missing_license["license"] = "TBD"
        assert "license_not_resolved" in validate_entry(missing_license, root)["blocking_reasons"]

        for unresolved_license in ("free", "custom", "royalty-free", "public domain"):
            candidate = entry(rel, sha)
            candidate["license"] = unresolved_license
            result = validate_entry(candidate, root)
            assert "license_not_allowed" in result["blocking_reasons"]
            assert result["roster_eligible"] is False

        for source_url, reason in {
            "https://": "source_url_host_missing",
            "http://example.invalid/source": "source_url_https_required",
            "https://localhost/source": "source_url_localhost_forbidden",
            "https://127.0.0.1/source": "source_url_non_global_ip_forbidden",
            "https://example.invalid/source#claim": "source_url_fragment_forbidden",
        }.items():
            result = validate_entry(entry(rel, sha, source_url=source_url), root)
            assert reason in result["blocking_reasons"]

        player = root / PLAYER_ASSET
        player.parent.mkdir(parents=True, exist_ok=True)
        player.write_bytes(minimal_glb())
        psha = hashlib.sha256(player.read_bytes()).hexdigest()
        reused = validate_entry(entry(PLAYER_ASSET, psha, "police"), root)
        assert "player_reuse_forbidden" in reused["blocking_reasons"]
        assert "player_content_reuse_forbidden" in reused["blocking_reasons"]

        canonical = build_payload({"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": []}, root)
        assert canonical["blocking_reasons"] == []

    print("CIV1_ROSTER_REGISTRATION_TRUTH_V10_GREEN")


if __name__ == "__main__":
    main()
