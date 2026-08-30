from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
_HANDLER_ARG = r'(?:Callable\s*\(\s*self\s*,\s*["\']([_A-Za-z0-9]+)["\']\s*\)|([_A-Za-z0-9]+))'
NODE_ADDED_CONNECT_RE = re.compile(
    rf"node_added\s*\.\s*connect\s*\(\s*{_HANDLER_ARG}\s*\)"
)
NODE_ADDED_DISCONNECT_RE = re.compile(
    rf"node_added\s*\.\s*disconnect\s*\(\s*{_HANDLER_ARG}\s*\)"
)


def fail(message: str) -> None:
    raise AssertionError(message)


def _handler(match: re.Match[str]) -> str:
    return match.group(1) or match.group(2) or ""


def handlers(pattern: re.Pattern[str], source: str) -> tuple[str, ...]:
    return tuple(_handler(match) for match in pattern.finditer(source) if _handler(match))


def _connect_site_is_guarded(source: str, match: re.Match[str], handler: str) -> bool:
    line_start = source.rfind("\n", 0, match.start()) + 1
    previous_line_start = source.rfind("\n", 0, max(0, line_start - 1)) + 1
    context = source[previous_line_start:match.start()]
    direct_guard = re.compile(
        rf"not\s+[^\n]*node_added\s*\.\s*is_connected\s*\(\s*{re.escape(handler)}\s*\)"
    )
    callable_guard = re.compile(
        rf"not\s+[^\n]*node_added\s*\.\s*is_connected\s*\(\s*Callable\s*\(\s*self\s*,\s*[\"\']{re.escape(handler)}[\"\']\s*\)\s*\)"
    )
    return bool(direct_guard.search(context) or callable_guard.search(context))


def validate_watcher_cardinality(source: str, rel_path: str) -> None:
    connect_matches = list(NODE_ADDED_CONNECT_RE.finditer(source))
    connected = tuple(_handler(match) for match in connect_matches)
    disconnected = handlers(NODE_ADDED_DISCONNECT_RE, source)
    if not connected:
        fail(f"runtime must connect node_added: {rel_path}")
    if len(set(connected)) != 1:
        fail(
            f"runtime connects node_added with multiple handlers: {rel_path} "
            f"handlers={list(connected)}"
        )
    if len(connect_matches) > 1:
        unguarded = [
            index
            for index, match in enumerate(connect_matches, start=1)
            if not _connect_site_is_guarded(source, match, connected[0])
        ]
        if unguarded:
            fail(
                f"multiple node_added connect sites require is_connected guards: {rel_path} "
                f"sites={len(connect_matches)} unguarded={unguarded}"
            )
    if not disconnected:
        fail(f"runtime must disconnect node_added on at least one cleanup path: {rel_path}")
    unexpected_disconnects = tuple(handler for handler in disconnected if handler != connected[0])
    if unexpected_disconnects:
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

    callable_probe = "\n".join(
        (
            'node_added.connect(Callable(self, "_on_tree_node_added"))',
            'node_added.disconnect(Callable(self, "_on_tree_node_added"))',
        )
    )
    if handlers(NODE_ADDED_CONNECT_RE, callable_probe) != ("_on_tree_node_added",):
        fail("node_added watcher discovery does not detect Callable connect syntax")
    if handlers(NODE_ADDED_DISCONNECT_RE, callable_probe) != ("_on_tree_node_added",):
        fail("node_added watcher discovery does not detect Callable disconnect syntax")

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
        fail("unguarded duplicate node_added subscription sites are not rejected")

    guarded_rearm_probe = "\n".join(
        (
            "if not tree.node_added.is_connected(_on_node_added):",
            "    tree.node_added.connect(_on_node_added)",
            "if not tree.node_added.is_connected(_on_node_added):",
            "    tree.node_added.connect(_on_node_added)",
            "tree.node_added.disconnect(_on_node_added)",
        )
    )
    validate_watcher_cardinality(guarded_rearm_probe, "synthetic_guarded_rearm.gd")

    alternate_cleanup_probe = "\n".join(
        (
            "node_added.connect(_on_node_added)",
            "node_added.disconnect(_on_node_added)",
            "node_added.disconnect(_on_node_added)",
        )
    )
    validate_watcher_cardinality(alternate_cleanup_probe, "synthetic_alternate_cleanup.gd")

    mismatched_cleanup_probe = "\n".join(
        (
            "node_added.connect(_on_node_added)",
            "node_added.disconnect(_on_node_added)",
            "node_added.disconnect(_rogue_node_added)",
        )
    )
    try:
        validate_watcher_cardinality(mismatched_cleanup_probe, "synthetic_mismatched_cleanup.gd")
    except AssertionError:
        pass
    else:
        fail("node_added cleanup path using a different handler is not rejected")

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
        "subscription_handlers=locked guarded_rearm=locked multiline=locked "
        "callable=locked cleanup_handlers=locked"
    )


if __name__ == "__main__":
    main()
