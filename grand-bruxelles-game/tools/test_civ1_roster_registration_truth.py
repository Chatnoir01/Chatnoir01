#!/usr/bin/env python3
from __future__ import annotations

import hashlib, json, subprocess, sys, tempfile
from pathlib import Path
from civ1_roster_registration_truth import PLAYER_ASSET, build_payload, validate_entry


def entry(path: str, sha: str, role: str = "civilian", source_url: str = "https://example.invalid/source") -> dict[str, str]:
    return {"asset_path": path, "role": role, "sha256": sha, "source_url": source_url, "license": "CC0-1.0"}


def historical_v1_path_guard_accepts(path: str) -> bool:
    normalized = Path(path).as_posix().lstrip("./")
    return normalized.startswith("grand-bruxelles-game/assets/characters/")


def historical_v3_player_path_guard_accepts(path: str) -> bool:
    return path != PLAYER_ASSET


def historical_v4_source_guard_accepts(source_url: str) -> bool:
    return source_url.startswith(("https://", "http://"))


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        rel="grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset=root/rel; asset.parent.mkdir(parents=True); asset.write_bytes(b"fixture-character")
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()

        good=validate_entry(entry(rel, sha), root)
        assert good["valid"] is True and good["roster_eligible"] is True

        malformed_sources = {
            "https://": "source_url_host_missing",
            "http://example.invalid/source": "source_url_https_required",
            "https://user:secret@example.invalid/source": "source_url_credentials_forbidden",
            "https://localhost/source": "source_url_localhost_forbidden",
            "https://127.0.0.1/source": "source_url_non_global_ip_forbidden",
            "https://example.invalid/source#claim": "source_url_fragment_forbidden",
        }
        for source_url, reason in malformed_sources.items():
            assert historical_v4_source_guard_accepts(source_url) is True
            result=validate_entry(entry(rel, sha, source_url=source_url), root)
            assert reason in result["blocking_reasons"], (source_url, result)
            assert result["roster_eligible"] is False

        wrong=validate_entry(entry(rel, "0"*64), root)
        assert "sha256_mismatch" in wrong["blocking_reasons"]
        missing=entry(rel, sha); missing["license"]="TBD"
        assert "license_not_resolved" in validate_entry(missing, root)["blocking_reasons"]

        player=root/PLAYER_ASSET; player.parent.mkdir(parents=True, exist_ok=True); player.write_bytes(b"player-authored-content")
        psha=hashlib.sha256(player.read_bytes()).hexdigest()
        reused=validate_entry(entry(PLAYER_ASSET, psha, "police"), root)
        assert "player_reuse_forbidden" in reused["blocking_reasons"]
        assert "player_content_reuse_forbidden" in reused["blocking_reasons"]
        assert reused["roster_eligible"] is False

        disguised_rel="grand-bruxelles-game/assets/characters/civilian_disguised_player.glb"
        disguised=root/disguised_rel; disguised.write_bytes(player.read_bytes())
        assert historical_v3_player_path_guard_accepts(disguised_rel) is True
        assert hashlib.sha256(disguised.read_bytes()).hexdigest() == psha
        disguised_result=validate_entry(entry(disguised_rel, psha, "civilian"), root)
        assert "player_content_reuse_forbidden" in disguised_result["blocking_reasons"]
        assert disguised_result["roster_eligible"] is False

        dup=build_payload({"entries":[entry(rel, sha), entry(rel, sha, "police")]}, root)
        assert "duplicate_asset_path" in dup["blocking_reasons"]
        assert dup["eligible_count"] == 0

        clone_rel="grand-bruxelles-game/assets/characters/police_clone.glb"
        clone=root/clone_rel; clone.write_bytes(asset.read_bytes())
        duplicate_content=build_payload({"entries":[entry(rel, sha), entry(clone_rel, sha, "police")]}, root)
        assert "duplicate_content_sha256" in duplicate_content["blocking_reasons"]
        assert duplicate_content["eligible_count"] == 0

        outside=root/"grand-bruxelles-game/qa/escaped_character.glb"
        outside.parent.mkdir(parents=True, exist_ok=True); outside.write_bytes(b"escaped-character")
        outside_sha=hashlib.sha256(outside.read_bytes()).hexdigest()
        traversal="grand-bruxelles-game/assets/characters/../../qa/escaped_character.glb"
        assert historical_v1_path_guard_accepts(traversal) is True
        escaped=validate_entry(entry(traversal, outside_sha), root)
        assert "asset_path_not_canonically_confined" in escaped["blocking_reasons"]
        assert escaped["actual_sha256"] is None and escaped["roster_eligible"] is False

        noncanonical=validate_entry(entry("./"+rel, sha), root)
        assert "asset_path_not_canonically_confined" in noncanonical["blocking_reasons"]

        sibling=root/"grand-bruxelles-game/assets/characters_evil/civilian.glb"
        sibling.parent.mkdir(parents=True); sibling.write_bytes(b"sibling")
        sibling_sha=hashlib.sha256(sibling.read_bytes()).hexdigest()
        sibling_result=validate_entry(entry("grand-bruxelles-game/assets/characters_evil/civilian.glb", sibling_sha), root)
        assert "asset_path_not_canonically_confined" in sibling_result["blocking_reasons"]

        link=root/"grand-bruxelles-game/assets/characters/linked_escape.glb"
        try:
            link.symlink_to(outside)
        except (OSError, NotImplementedError):
            pass
        else:
            linked=validate_entry(entry("grand-bruxelles-game/assets/characters/linked_escape.glb", outside_sha), root)
            assert "asset_path_not_canonically_confined" in linked["blocking_reasons"]
            assert linked["actual_sha256"] is None and linked["roster_eligible"] is False

        payload=build_payload({"entries": []}, root)
        assert payload["player_content_identity_reuse_forbidden"] is True
        assert payload["source_url_structural_provenance_required"] is True
        assert payload["source_url_https_required"] is True
        assert payload["source_url_local_network_forbidden"] is True
        assert payload["eligible_count"] == 0

        # Causal RED for v5: malformed registry syntax must not be normalized into
        # a successful empty roster truth. Preserve the receipt, but the CLI must
        # fail so CI cannot silently green-light corrupted provenance state.
        malformed_registry=root/"malformed-registry.json"
        malformed_registry.write_text('{"entries": [', encoding="utf-8")
        malformed_receipt=root/"malformed-receipt.json"
        tool=Path(__file__).with_name("civ1_roster_registration_truth.py")
        proc=subprocess.run(
            [sys.executable, str(tool), str(malformed_registry), "--repo-root", str(root), "--out", str(malformed_receipt)],
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode != 0, "v5 fail-open reproduced: malformed registry returned success"
        malformed_payload=json.loads(malformed_receipt.read_text(encoding="utf-8"))
        assert "registry_unreadable_or_invalid_json" in malformed_payload["blocking_reasons"]
        assert malformed_payload["eligible_count"] == 0

    print("CIV1_ROSTER_REGISTRATION_TRUTH_V6_GREEN")

if __name__ == "__main__": main()
