#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "project.godot"
BOOTSTRAP = ROOT / "game/scripts/grand_brussels_runtime_bootstrap.gd"
MANIFEST = ROOT / "data/runtime/runtime_registry.json"
MODULES = ROOT / "data/runtime/modules"
EXPECTED_MANIFEST_SCHEMA = "grand-bruxelles-runtime-registry-v1"
EXPECTED_MODULE_SCHEMA = "grand-bruxelles-runtime-module-v1"
EXPECTED_MODULES_DIR = "res://data/runtime/modules"
EXPECTED_AUTOLOAD = 'GrandBrusselsRuntimeBootstrap="*res://game/scripts/grand_brussels_runtime_bootstrap.gd"'


def fail(message: str) -> None:
    print(f"GRAND_BRUSSELS_RUNTIME_BOOTSTRAP_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    for path in (PROJECT, BOOTSTRAP, MANIFEST, MODULES):
        if not path.exists():
            fail(f"required path missing: {path.relative_to(ROOT)}")

    project = PROJECT.read_text(encoding="utf-8")
    if EXPECTED_AUTOLOAD not in project:
        fail("permanent runtime bootstrap autoload missing")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("schema") != EXPECTED_MANIFEST_SCHEMA:
        fail("manifest schema mismatch")
    if manifest.get("modules_dir") != EXPECTED_MODULES_DIR:
        fail("manifest modules_dir changed")

    autoload_section = project.split("[autoload]", 1)[1].split("[display]", 1)[0]
    autoload_names = set(re.findall(r"^([A-Za-z][A-Za-z0-9_]*)=", autoload_section, flags=re.MULTILINE))
    seen_names: set[str] = set()
    enabled = 0
    for descriptor_path in sorted(MODULES.glob("*.json")):
        descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
        if descriptor.get("schema") != EXPECTED_MODULE_SCHEMA:
            fail(f"module schema mismatch: {descriptor_path.name}")
        if not descriptor.get("enabled", True):
            continue
        name = str(descriptor.get("name", "")).strip()
        resource_path = str(descriptor.get("path", "")).strip()
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name):
            fail(f"invalid module root name: {name!r}")
        if name in seen_names:
            fail(f"duplicate module root name: {name}")
        if name in autoload_names:
            fail(f"registered module duplicates direct autoload: {name}")
        if not resource_path.startswith("res://game/scripts/") or not resource_path.endswith(".gd"):
            fail(f"module path outside approved game scripts: {resource_path}")
        runtime_file = ROOT / resource_path.removeprefix("res://")
        if not runtime_file.is_file():
            fail(f"registered runtime file missing: {resource_path}")
        seen_names.add(name)
        enabled += 1

    bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
    required_tokens = [
        'MODULE_DIR := "res://data/runtime/modules"',
        'SCRIPT_DIR := "res://game/scripts/"',
        'get_tree().root.get_node_or_null',
        'get_tree().root.add_child',
        'module root already exists',
        'GRAND_BRUSSELS_RUNTIME_BOOTSTRAP_READY',
    ]
    for token in required_tokens:
        if token not in bootstrap:
            fail(f"bootstrap invariant missing: {token}")

    print(
        "GRAND_BRUSSELS_RUNTIME_BOOTSTRAP_OK: "
        f"enabled_modules={enabled} direct_autoload_overlap=0 per_module_registry=true"
    )


if __name__ == "__main__":
    main()
