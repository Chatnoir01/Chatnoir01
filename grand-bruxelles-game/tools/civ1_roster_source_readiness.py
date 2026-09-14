#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

CIV1_PREFIX = "grand-bruxelles-game/assets/characters/civilians/civ1/"
STATUS_PATH = Path("grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json")


def source_ready(repo_root: Path) -> bool:
    try:
        status = json.loads((repo_root / STATUS_PATH).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return all(
        status.get(key) is True
        for key in ("production_authorized", "activation_ready", "source_package_present")
    )


def blocking_entries(registry: object, repo_root: Path) -> list[str]:
    if source_ready(repo_root):
        return []
    if not isinstance(registry, dict) or not isinstance(registry.get("entries"), list):
        return []
    blocked = []
    for entry in registry["entries"]:
        if not isinstance(entry, dict):
            continue
        asset_path = entry.get("asset_path")
        if isinstance(asset_path, str) and asset_path.startswith(CIV1_PREFIX):
            blocked.append(asset_path)
    return blocked


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("registry", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    args = parser.parse_args()
    try:
        registry = json.loads(args.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"CIV1_ROSTER_SOURCE_READINESS_ERROR {exc}")
        return 2
    blocked = blocking_entries(registry, args.repo_root)
    if blocked:
        print("CIV1_ROSTER_SOURCE_NOT_READY " + json.dumps(sorted(set(blocked))))
        return 2
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
