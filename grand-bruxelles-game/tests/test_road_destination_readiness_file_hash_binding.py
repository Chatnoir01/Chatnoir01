#!/usr/bin/env python3
from __future__ import annotations

import copy
import fnmatch
import re
from pathlib import Path

from validate_road_destination_readiness_hash_identity import load_catalog, validate

ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parent
CATALOG_PATH = ROOT / "data/provenance/brussels_road_destination_readiness_catalog.json"
WORKFLOW_PATH = REPO_ROOT / ".github/workflows/grand-bruxelles-road-destination-readiness-authorization.yml"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _historical_format_only_accepts(candidate: dict) -> bool:
    row = candidate["destinations"][0]
    return all(
        isinstance(row[field], str) and SHA256_RE.fullmatch(row[field]) is not None
        for field in ("cell_manifest_sha256", "source_points_sha256", "source_sha256")
    )


def _must_reject(label: str, candidate: dict) -> None:
    try:
        validate(candidate, root=ROOT)
    except ValueError:
        return
    raise AssertionError(f"{label} mutation was accepted")


def _workflow_path_filters() -> tuple[str, ...]:
    filters: list[str] = []
    in_paths = False
    for raw_line in WORKFLOW_PATH.read_text(encoding="utf-8").splitlines():
        stripped = raw_line.strip()
        if stripped == "paths:":
            in_paths = True
            continue
        if in_paths and raw_line and not raw_line.startswith("      "):
            break
        if in_paths and stripped.startswith("- "):
            value = stripped[2:].strip().strip('"').strip("'")
            if value:
                filters.append(value)
    if not filters:
        raise AssertionError("authorization workflow exposes no pull_request path filters")
    return tuple(filters)


def _assert_hashed_inputs_trigger_authorization(catalog: dict) -> None:
    filters = _workflow_path_filters()
    referenced: set[str] = set()
    for row in catalog["destinations"]:
        referenced.add(f"grand-bruxelles-game/{row['source_path']}")
        referenced.add(f"grand-bruxelles-game/{row['cell_manifest_path']}")
    uncovered = sorted(
        path for path in referenced if not any(fnmatch.fnmatchcase(path, pattern) for pattern in filters)
    )
    if uncovered:
        preview = ", ".join(uncovered[:5])
        raise AssertionError(
            "authorization workflow does not trigger when hash-bound input files change: "
            f"{preview}" + (" ..." if len(uncovered) > 5 else "")
        )


def main() -> int:
    catalog = load_catalog(CATALOG_PATH)

    source_hash_drift = copy.deepcopy(catalog)
    source_hash_drift["destinations"][0]["source_sha256"] = "0" * 64
    assert _historical_format_only_accepts(source_hash_drift), "historical format-only source precondition missing"
    _must_reject("source file hash drift", source_hash_drift)

    manifest_hash_drift = copy.deepcopy(catalog)
    manifest_hash_drift["destinations"][0]["cell_manifest_sha256"] = "1" * 64
    assert _historical_format_only_accepts(manifest_hash_drift), "historical format-only manifest precondition missing"
    _must_reject("cell manifest file hash drift", manifest_hash_drift)

    source_points_hash_drift = copy.deepcopy(catalog)
    source_points_hash_drift["destinations"][0]["source_points_sha256"] = "2" * 64
    assert _historical_format_only_accepts(
        source_points_hash_drift
    ), "historical format-only source-points precondition missing"
    _must_reject("source points hash drift", source_points_hash_drift)

    _assert_hashed_inputs_trigger_authorization(catalog)
    validate(catalog, root=ROOT)
    print(
        "ROAD_DESTINATION_READINESS_FILE_HASH_BINDING_OK "
        "historical_format_only_acceptance_proven=true "
        "source_file_hash_bound=true cell_manifest_hash_bound=true source_points_hash_bound=true "
        "hashed_input_trigger_coverage=true valid_hash_drift_rejected=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
