#!/usr/bin/env python3
"""Download the pinned NPC language model outside Git.

The repository stores only a manifest. Model weights are downloaded into
`grand-bruxelles-game/models/`, which is gitignored.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "data" / "ai" / "npc_llm_model.json"


class ModelDownloadError(ValueError):
    pass


def load_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ModelDownloadError("manifest root must be an object")
    if payload.get("schema") != "grand-bruxelles-npc-llm-model-v1":
        raise ModelDownloadError("unsupported model manifest schema")
    repo_id = str(payload.get("repo_id", "")).strip()
    revision = str(payload.get("revision", "")).strip()
    local_dir = str(payload.get("local_dir", "")).strip()
    if not repo_id or len(revision) != 40 or not local_dir.startswith("models/"):
        raise ModelDownloadError("manifest is not pinned to a safe external model destination")
    return payload


def download_plan(manifest: dict[str, Any], root: Path = ROOT) -> dict[str, Any]:
    destination = (root / str(manifest["local_dir"])).resolve()
    safe_root = (root / "models").resolve()
    if safe_root != destination and safe_root not in destination.parents:
        raise ModelDownloadError("model destination escapes the models directory")
    return {
        "repo_id": str(manifest["repo_id"]),
        "revision": str(manifest["revision"]),
        "destination": destination,
    }


def perform_download(plan: dict[str, Any]) -> Path:
    try:
        from huggingface_hub import snapshot_download
    except ImportError as exc:
        raise ModelDownloadError(
            "huggingface_hub is required; install it with: python -m pip install huggingface_hub"
        ) from exc

    destination = Path(plan["destination"])
    destination.mkdir(parents=True, exist_ok=True)
    resolved = snapshot_download(
        repo_id=str(plan["repo_id"]),
        revision=str(plan["revision"]),
        local_dir=str(destination),
    )
    model_file = Path(resolved) / "model.safetensors"
    if not model_file.exists():
        raise ModelDownloadError("download completed without model.safetensors")
    return Path(resolved)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    try:
        manifest = load_manifest(args.manifest)
        plan = download_plan(manifest)
        if args.dry_run:
            print(
                "NPC_LLM_DOWNLOAD_PLAN: repo=%s revision=%s destination=%s"
                % (plan["repo_id"], plan["revision"], plan["destination"])
            )
            return 0
        resolved = perform_download(plan)
    except (OSError, json.JSONDecodeError, ModelDownloadError) as exc:
        print(f"NPC_LLM_DOWNLOAD_FAIL: {exc}", file=sys.stderr)
        return 2

    print(
        "NPC_LLM_DOWNLOAD_OK: repo=%s revision=%s destination=%s"
        % (plan["repo_id"], plan["revision"], resolved)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
