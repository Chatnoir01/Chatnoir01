from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"


def fail(message: str) -> None:
    raise AssertionError(message)


def main() -> None:
    if not CONTRACT_PATH.is_file():
        fail("shared Environment lifecycle contract missing")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("node_added_watcher_cleanup_required") is not True:
        fail("shared Environment node_added watcher cleanup contract missing")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list) or not runtimes:
        fail("shared Environment lifecycle runtime registry missing")

    verified = 0
    for entry in runtimes:
        if not isinstance(entry, dict):
            fail("malformed shared Environment lifecycle runtime entry")
        rel_path = entry.get("path")
        if not isinstance(rel_path, str) or not rel_path.startswith("game/scripts/"):
            fail(f"invalid shared Environment lifecycle runtime path: {rel_path}")

        script_path = ROOT / rel_path
        if not script_path.is_file():
            fail(f"registered shared Environment runtime missing: {rel_path}")
        source = script_path.read_text(encoding="utf-8")

        if "node_added.connect(" not in source:
            fail(f"registered runtime lost node_added watcher: {rel_path}")
        if "node_added.is_connected(" not in source:
            fail(f"node_added watcher cleanup guard missing: {rel_path}")
        if "node_added.disconnect(" not in source:
            fail(f"node_added watcher disconnect missing: {rel_path}")

        verified += 1

    if verified != int(contract.get("registered_runtime_count", -1)):
        fail(
            "shared Environment watcher cleanup coverage mismatch: "
            f"verified={verified} registered={contract.get('registered_runtime_count')}"
        )

    print(
        "SHARED_ENVIRONMENT_WATCHER_CLEANUP_OK: "
        f"runtimes={verified} connect=guarded disconnect=required"
    )


if __name__ == "__main__":
    main()
