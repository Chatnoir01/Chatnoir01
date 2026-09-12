#!/usr/bin/env python3
from __future__ import annotations

import hashlib, json, subprocess, sys, tempfile
from pathlib import Path
from civ1_roster_registration_truth import PLAYER_ASSET, build_payload, validate_entry


def entry(path: str, sha: str, role: str = "civilian", source_url: str = "https://example.invalid/source") -> dict[str, str]:
    return {"asset_path": path, "role": role, "sha256": sha, "source_url": source_url, "license": "CC0-1.0"}


def run_cli(tool: Path, registry: Path, root: Path, receipt: Path) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
    proc = subprocess.run([sys.executable, str(tool), str(registry), "--repo-root", str(root), "--out", str(receipt)], capture_output=True, text=True, check=False)
    return proc, json.loads(receipt.read_text(encoding="utf-8"))


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rel = "grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset = root / rel
        asset.parent.mkdir(parents=True)
        asset.write_bytes(b"fixture-character")
        sha = hashlib.sha256(asset.read_bytes()).hexdigest()

        good = validate_entry(entry(rel, sha), root)
        assert good["valid"] is True and good["roster_eligible"] is True

        for source_url, reason in {
            "https://": "source_url_host_missing",
            "http://example.invalid/source": "source_url_https_required",
            "https://localhost/source": "source_url_localhost_forbidden",
            "https://127.0.0.1/source": "source_url_non_global_ip_forbidden",
            "https://example.invalid/source#claim": "source_url_fragment_forbidden",
        }.items():
            result = validate_entry(entry(rel, sha, source_url=source_url), root)
            assert reason in result["blocking_reasons"], (source_url, result)
            assert result["roster_eligible"] is False

        wrong = validate_entry(entry(rel, "0" * 64), root)
        assert "sha256_mismatch" in wrong["blocking_reasons"]
        missing_license = entry(rel, sha)
        missing_license["license"] = "TBD"
        assert "license_not_resolved" in validate_entry(missing_license, root)["blocking_reasons"]

        player = root / PLAYER_ASSET
        player.parent.mkdir(parents=True, exist_ok=True)
        player.write_bytes(b"player-authored-content")
        psha = hashlib.sha256(player.read_bytes()).hexdigest()
        reused = validate_entry(entry(PLAYER_ASSET, psha, "police"), root)
        assert "player_reuse_forbidden" in reused["blocking_reasons"]
        assert "player_content_reuse_forbidden" in reused["blocking_reasons"]

        disguised_rel = "grand-bruxelles-game/assets/characters/civilian_disguised_player.glb"
        disguised = root / disguised_rel
        disguised.write_bytes(player.read_bytes())
        disguised_result = validate_entry(entry(disguised_rel, psha), root)
        assert "player_content_reuse_forbidden" in disguised_result["blocking_reasons"]

        clone_rel = "grand-bruxelles-game/assets/characters/police_clone.glb"
        clone = root / clone_rel
        clone.write_bytes(asset.read_bytes())
        duplicate_content = build_payload({"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": [entry(rel, sha), entry(clone_rel, sha, "police")]}, root)
        assert "duplicate_content_sha256" in duplicate_content["blocking_reasons"]
        assert duplicate_content["eligible_count"] == 0

        outside = root / "grand-bruxelles-game/qa/escaped_character.glb"
        outside.parent.mkdir(parents=True, exist_ok=True)
        outside.write_bytes(b"escaped-character")
        outside_sha = hashlib.sha256(outside.read_bytes()).hexdigest()
        escaped = validate_entry(entry("grand-bruxelles-game/assets/characters/../../qa/escaped_character.glb", outside_sha), root)
        assert "asset_path_not_canonically_confined" in escaped["blocking_reasons"]
        assert escaped["actual_sha256"] is None

        canonical = build_payload({"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": []}, root)
        assert canonical["blocking_reasons"] == []
        assert canonical["invalid_entry_count"] == 0
        assert canonical["invalid_entries_fail_closed"] is True

        tool = Path(__file__).with_name("civ1_roster_registration_truth.py")

        invalid_entry_registry = root / "invalid-entry-registry.json"
        invalid_entry_registry.write_text(json.dumps({"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": [entry(rel, "0" * 64)]}), encoding="utf-8")
        invalid_entry_receipt = root / "invalid-entry-receipt.json"
        proc, payload = run_cli(tool, invalid_entry_registry, root, invalid_entry_receipt)
        assert proc.returncode != 0, "v7 fail-open reproduced: invalid entry under valid registry schema returned success"
        assert payload["registry_schema_valid"] is True
        assert payload["invalid_entry_count"] == 1
        assert "invalid_entries_present" in payload["blocking_reasons"]
        assert payload["entries"][0]["roster_eligible"] is False

        wrong_schema_registry = root / "wrong-schema-registry.json"
        wrong_schema_registry.write_text(json.dumps({"schema": "grand-bruxelles-civ1-roster-registry-v0", "entries": []}), encoding="utf-8")
        proc, payload = run_cli(tool, wrong_schema_registry, root, root / "wrong-schema-receipt.json")
        assert proc.returncode != 0
        assert "registry_schema_invalid" in payload["blocking_reasons"]

        malformed_registry = root / "malformed-registry.json"
        malformed_registry.write_text('{"entries": [', encoding="utf-8")
        proc, payload = run_cli(tool, malformed_registry, root, root / "malformed-receipt.json")
        assert proc.returncode != 0
        assert payload["registry_parse_valid"] is False
        assert "registry_unreadable_or_invalid_json" in payload["blocking_reasons"]

    print("CIV1_ROSTER_REGISTRATION_TRUTH_V8_GREEN")


if __name__ == "__main__":
    main()
