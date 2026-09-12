#!/usr/bin/env python3
from __future__ import annotations

import hashlib, tempfile
from pathlib import Path
from civ1_roster_registration_truth import PLAYER_ASSET, build_payload, validate_entry


def entry(path: str, sha: str, role: str = "civilian") -> dict[str, str]:
    return {"asset_path": path, "role": role, "sha256": sha, "source_url": "https://example.invalid/source", "license": "CC0-1.0"}


def historical_v1_path_guard_accepts(path: str) -> bool:
    normalized = Path(path).as_posix().lstrip("./")
    return normalized.startswith("grand-bruxelles-game/assets/characters/")


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        rel="grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset=root/rel; asset.parent.mkdir(parents=True); asset.write_bytes(b"fixture-character")
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()

        good=validate_entry(entry(rel, sha), root)
        assert good["valid"] is True and good["roster_eligible"] is True

        misleading=root/"grand-bruxelles-game/assets/characters/police_candidate.glb"
        misleading.write_bytes(b"not-registered")
        empty=build_payload({"entries": []}, root)
        assert empty["eligible_count"] == 0
        assert empty["filename_role_inference_forbidden"] is True
        assert empty["canonical_character_path_confinement_required"] is True

        wrong=validate_entry(entry(rel, "0"*64), root)
        assert "sha256_mismatch" in wrong["blocking_reasons"]
        missing=entry(rel, sha); missing["license"]="TBD"
        assert "license_not_resolved" in validate_entry(missing, root)["blocking_reasons"]

        player=root/PLAYER_ASSET; player.parent.mkdir(parents=True, exist_ok=True); player.write_bytes(b"player")
        psha=hashlib.sha256(player.read_bytes()).hexdigest()
        reused=validate_entry(entry(PLAYER_ASSET, psha, "police"), root)
        assert "player_reuse_forbidden" in reused["blocking_reasons"]
        assert reused["roster_eligible"] is False

        dup=build_payload({"entries":[entry(rel, sha), entry(rel, sha, "police")]}, root)
        assert "duplicate_asset_path" in dup["blocking_reasons"]
        assert dup["eligible_count"] == 0

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

    print("CIV1_ROSTER_REGISTRATION_TRUTH_V2_GREEN")

if __name__ == "__main__": main()
