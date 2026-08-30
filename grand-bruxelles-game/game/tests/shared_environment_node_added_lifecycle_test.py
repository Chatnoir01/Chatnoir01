from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
NODE_ADDED_CONNECT_RE = re.compile(
    r"node_added\s*\.\s*connect\s*\(\s*([_A-Za-z0-9]+)\s*\)"
)
NODE_ADDED_DISCONNECT_RE = re.compile(
    r"node_added\s*\.\s*disconnect\s*\(\s*([_A-Za-z0-9]+)\s*\)"
)


def fail(message: str) -> None:
    raise AssertionError(message)


def handlers(pattern: re.Pattern[str], source: str) -> tuple[str, ...]:
    return tuple(match.group(1) for match in pattern.finditer(source))


def validate_watcher_cardinality(source: str, rel_path: str) -> None:
    connected = handlers(NODE_ADDED_CONNECT_RE, source)
    disconnected = handlers(NODE_ADDED_DISCONNECT_RE, source)
    if len(connected) != 1:
        fail(
            f"runtime must connect node_added exactly once: {rel_path} "
            f"sites={len(connected)} handlers={list(connected)}"
        )
    if len(disconnected) != 1:
        fail(
            f"runtime must disconnect node_added exactly once: {rel_path} "
            f"sites={len(disconnected)} handlers={list(disconnected)}"
        )
    if disconnected != connected:
        fail(
            f"node_added watcher cleanup mismatch: {rel_path} "
            f"connected={list(connected)} disconnected={list(disconnected)}"
        )


def main() -> None:
    discovery_probe = "\n".join(
        (
            "node_added.connect(_on_node_added)",
            "node_added.connect(",
            "    _on_node_added",
            ")",
            "node_added.disconnect(",
            "    _on_node_added",
            ")",
        )
    )
    if handlers(NODE_ADDED_CONNECT_RE, discovery_probe) != (
        "_on_node_added",
        "_on_node_added",
    ):
        fail("node_added watcher discovery does not enumerate multiline connect sites")
    if handlers(NODE_ADDED_DISCONNECT_RE, discovery_probe) != ("_on_node_added",):
        fail("node_added watcher discovery does not detect multiline disconnect")

    duplicate_subscription_probe = "\n".join(
        (
            "node_added.connect(_on_node_added)",
            "node_added.connect(_on_node_added)",
            "node_added.disconnect(_on_node_added)",
        )
    )
    try:
        validate_watcher_cardinality(duplicate_subscription_probe, "synthetic_duplicate_probe.gd")
    except AssertionError:
        pass
    else:
        fail("duplicate node_added subscription sites are not rejected")

    duplicate_disconnect_probe = "\n".join(
        (
            "node_added.connect(_on_node_added)",
            "node_added.disconnect(_on_node_added)",
            "node_added.disconnect(_on_node_added)",
        )
    )
    try:
        validate_watcher_cardinality(duplicate_disconnect_probe, "synthetic_duplicate_disconnect.gd")
    except AssertionError:
        pass
    else:
        fail("duplicate node_added disconnect sites are not rejected")

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    if contract.get("node_added_watcher_cleanup_required") is not True:
        fail("central lifecycle contract does not require node_added cleanup")

    runtimes = contract.get("runtimes")
    if not isinstance(runtimes, list):
        fail("shared Environment lifecycle runtime registry missing")
    if contract.get("node_added_registry_runtime_count") != len(runtimes):
        fail("node_added registry runtime count missing or drifted")

    seen_paths: set[str] = set()
    for entry in runtimes:
        if not isinstance(entry, dict):
            fail("malformed lifecycle runtime entry")
        rel_path = entry.get("path")
        if not isinstance(rel_path, str) or not rel_path.startswith("game/scripts/"):
            fail(f"invalid lifecycle runtime path: {rel_path}")
        if rel_path in seen_paths:
            fail(f"duplicate lifecycle runtime path: {rel_path}")
        seen_paths.add(rel_path)

        source_path = ROOT / rel_path
        if not source_path.is_file():
            fail(f"registered lifecycle runtime missing: {rel_path}")
        source = source_path.read_text(encoding="utf-8")
        validate_watcher_cardinality(source, rel_path)

    print(
        "SHARED_ENVIRONMENT_NODE_ADDED_LIFECYCLE_OK: "
        f"runtimes={len(runtimes)} watcher_cleanup=locked "
        "single_handler=locked multiline=locked subscription_cardinality=locked"
    )


if __name__ == "__main__":
    main()
