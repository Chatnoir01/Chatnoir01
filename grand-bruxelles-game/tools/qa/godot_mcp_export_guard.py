#!/usr/bin/env python3
"""Fail closed if Godot MCP development tooling could enter production exports."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "godot_mcp_pilot_contract.json"
PROJECT_PATH = ROOT / "project.godot"
EXPORT_PATH = ROOT / "export_presets.cfg"
ADDON_PATH = ROOT / "addons" / "godot_mcp"
LOCAL_COMMANDS_PATH = ROOT / "mcp_commands"


def fail(message: str, errors: list[str]) -> None:
    errors.append(message)
    print(f"GODOT_MCP_EXPORT_GUARD_FAIL: {message}")


def preset_blocks(text: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    pattern = re.compile(
        r"(?ms)^\[preset\.(\d+)\]\s*\n(.*?)(?=^\[preset\.\1\.options\]\s*$)"
    )
    for match in pattern.finditer(text):
        body = match.group(2)
        name_match = re.search(r'(?m)^name="([^"]+)"\s*$', body)
        if name_match:
            blocks[name_match.group(1)] = body
    return blocks


def parse_excludes(body: str) -> set[str]:
    match = re.search(r'(?m)^exclude_filter="([^"]*)"\s*$', body)
    if not match:
        return set()
    return {token.strip() for token in match.group(1).split(",") if token.strip()}


def main() -> int:
    errors: list[str] = []

    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    project_text = PROJECT_PATH.read_text(encoding="utf-8")
    export_text = EXPORT_PATH.read_text(encoding="utf-8")

    policy = contract["policy"]
    if policy.get("runtime_authorized") is not False:
        fail("contract must keep runtime_authorized=false", errors)
    if policy.get("export_authorized") is not False:
        fail("contract must keep export_authorized=false", errors)
    if policy.get("canonical_addon_install_authorized") is not False:
        fail("contract must forbid canonical addon installation", errors)
    if policy.get("ci_temp_copy_only") is not True:
        fail("contract must require a temporary CI project copy", errors)
    if policy.get("loopback_only") is not True:
        fail("contract must require loopback-only MCP transport", errors)

    if ADDON_PATH.exists():
        fail(f"production tree contains forbidden addon directory: {ADDON_PATH}", errors)
    if LOCAL_COMMANDS_PATH.exists():
        fail(f"production tree contains MCP-local command directory: {LOCAL_COMMANDS_PATH}", errors)

    for token in contract["forbidden_production_project_tokens"]:
        if token in project_text:
            fail(f"production project.godot contains forbidden MCP token: {token}", errors)

    expected_engine_feature = 'config/features=PackedStringArray("4.7", "GL Compatibility")'
    if expected_engine_feature not in project_text:
        fail("project.godot no longer proves Godot 4.7 + GL Compatibility contract", errors)

    required = set(contract["required_export_excludes"])
    blocks = preset_blocks(export_text)
    required_presets = {"Web", "PC Desktop (Linux)"}
    missing_presets = required_presets - set(blocks)
    if missing_presets:
        fail(f"missing required export presets: {sorted(missing_presets)}", errors)

    for name in sorted(required_presets & set(blocks)):
        excludes = parse_excludes(blocks[name])
        missing = required - excludes
        if missing:
            fail(
                f"export preset {name!r} is missing MCP exclusions: {sorted(missing)}",
                errors,
            )

    if errors:
        print(f"GODOT_MCP_EXPORT_GUARD_RED errors={len(errors)}")
        return 1

    print(
        "GODOT_MCP_EXPORT_GUARD_GREEN "
        f"presets={sorted(required_presets)} excludes={sorted(required)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
