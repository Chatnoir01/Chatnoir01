#!/usr/bin/env python3
from __future__ import annotations

import hashlib, json, struct, subprocess, sys, tempfile
from pathlib import Path
from urllib.parse import urlsplit
from civ1_roster_registration_truth import PLAYER_ASSET, build_payload, validate_entry


def entry(path: str, sha: str, role: str = "civilian", source_url: str = "https://example.invalid/source") -> dict[str, object]:
    return {"asset_path": path, "role": role, "sha256": sha, "source_url": source_url, "license": "CC0-1.0"}


def minimal_glb() -> bytes:
    json_chunk = b"{}  "
    total = 12 + 8 + len(json_chunk)
    return struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk


def historical_v10_ignored_unknown_fields(candidate: dict[str, object]) -> bool:
    required = {"asset_path", "role", "sha256", "source_url", "license"}
    return required.issubset(candidate) and candidate.get("role") in {"civilian", "police"}


def historical_v11_normalized_sha(value: str) -> str:
    return value.lower()


def historical_v11_normalized_license(value: str) -> str:
    return value.strip()


def historical_v14_accepts_single_label_https(value: str) -> bool:
    parsed = urlsplit(value)
    host = (parsed.hostname or "").rstrip(".").lower()
    return parsed.scheme.lower() == "https" and bool(host) and host != "localhost" and not host.endswith(".localhost") and "." not in host


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

        assert historical_v11_normalized_sha(sha.upper()) == sha
        uppercase_sha = validate_entry(entry(rel, sha.upper()), root)
        assert "sha256_not_canonical" in uppercase_sha["blocking_reasons"]
        assert uppercase_sha["roster_eligible"] is False

        assert historical_v11_normalized_license(" CC0-1.0 ") == "CC0-1.0"
        spaced_license = entry(rel, sha)
        spaced_license["license"] = " CC0-1.0 "
        spaced_license_result = validate_entry(spaced_license, root)
        assert "license_not_canonical" in spaced_license_result["blocking_reasons"]
        assert spaced_license_result["roster_eligible"] is False

        overclaim = entry(rel, sha)
        overclaim["runtime_authorized"] = True
        overclaim["visual_approval_claimed"] = True
        assert historical_v10_ignored_unknown_fields(overclaim) is True
        overclaim_result = validate_entry(overclaim, root)
        assert "unexpected_entry_field:runtime_authorized" in overclaim_result["blocking_reasons"]
        assert "unexpected_entry_field:visual_approval_claimed" in overclaim_result["blocking_reasons"]
        assert overclaim_result["roster_eligible"] is False

        registry_overclaim = {"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": [], "runtime_authorized": True}
        payload = build_payload(registry_overclaim, root)
        assert "unexpected_registry_field:runtime_authorized" in payload["blocking_reasons"]
        assert payload["runtime_authorized"] is False

        fake_rel = "grand-bruxelles-game/assets/characters/civilian_fake.glb"
        fake = root / fake_rel
        fake.write_bytes(b"not-a-glb-character")
        fake_sha = hashlib.sha256(fake.read_bytes()).hexdigest()
        fake_result = validate_entry(entry(fake_rel, fake_sha), root)
        assert "glb_container_invalid" in fake_result["blocking_reasons"]
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

        for local_name in ("https://intranet/source", "https://router/model.glb"):
            assert historical_v14_accepts_single_label_https(local_name) is True, "v14 precondition: single-label HTTPS host passed structural source checks"
            result = validate_entry(entry(rel, sha, source_url=local_name), root)
            assert "source_url_single_label_host_forbidden" in result["blocking_reasons"]
            assert result["roster_eligible"] is False

        trailing_dot = validate_entry(entry(rel, sha, source_url="https://assets.example.invalid./civilian.glb"), root)
        assert "source_url_not_canonical" in trailing_dot["blocking_reasons"], trailing_dot
        assert trailing_dot["roster_eligible"] is False, trailing_dot

        player = root / PLAYER_ASSET
        player.parent.mkdir(parents=True, exist_ok=True)
        player.write_bytes(minimal_glb())
        psha = hashlib.sha256(player.read_bytes()).hexdigest()
        reused = validate_entry(entry(PLAYER_ASSET, psha, "police"), root)
        assert "player_reuse_forbidden" in reused["blocking_reasons"]
        assert "player_content_reuse_forbidden" in reused["blocking_reasons"]

        canonical = build_payload({"schema": "grand-bruxelles-civ1-roster-registry-v1", "entries": []}, root)
        assert canonical["blocking_reasons"] == []
        assert canonical["strict_registry_fields_required"] is True
        assert canonical["strict_entry_fields_required"] is True
        assert canonical["canonical_provenance_values_required"] is True
        assert canonical["duplicate_json_keys_forbidden"] is True
        assert canonical["source_url_multilabel_dns_required"] is True

        duplicate_registry = root / "duplicate_registry.json"
        duplicate_registry.write_text('{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[],"entries":[{"asset_path":"x"}]}', encoding="utf-8")
        historical = json.loads(duplicate_registry.read_text(encoding="utf-8"))
        assert historical["entries"] == [{"asset_path": "x"}]
        proc = subprocess.run([sys.executable, str(Path(__file__).with_name("civ1_roster_registration_truth.py")), str(duplicate_registry), "--repo-root", str(root)], text=True, capture_output=True, check=False)
        assert proc.returncode == 2
        duplicate_payload = json.loads(proc.stdout)
        assert duplicate_payload["registry_parse_valid"] is False
        assert "registry_duplicate_json_key:entries" in duplicate_payload["blocking_reasons"]
        assert duplicate_payload["registration_count"] == 0
        assert duplicate_payload["eligible_count"] == 0

        for token in ("NaN", "Infinity", "-Infinity"):
            nonstandard_registry = root / f"nonstandard_{token.replace('-', 'minus_')}.json"
            nonstandard_registry.write_text(f'{{"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[{token}]}}', encoding="utf-8")
            historical_nonstandard = json.loads(nonstandard_registry.read_text(encoding="utf-8"))
            assert len(historical_nonstandard["entries"]) == 1
            proc = subprocess.run([sys.executable, str(Path(__file__).with_name("civ1_roster_registration_truth.py")), str(nonstandard_registry), "--repo-root", str(root)], text=True, capture_output=True, check=False)
            assert proc.returncode == 2
            nonstandard_payload = json.loads(proc.stdout)
            assert nonstandard_payload["registry_parse_valid"] is False
            assert f"registry_nonstandard_json_constant:{token}" in nonstandard_payload["blocking_reasons"]
            assert nonstandard_payload["registration_count"] == 0
            assert nonstandard_payload["eligible_count"] == 0

    print("CIV1_ROSTER_REGISTRATION_TRUTH_V16_GREEN")


if __name__ == "__main__":
    main()
