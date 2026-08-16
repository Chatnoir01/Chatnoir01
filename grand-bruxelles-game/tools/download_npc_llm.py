#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "npc_llm_model.json"


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    destination = ROOT / config["local_path"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    expected = config["sha256"].lower()
    if destination.exists() and sha256(destination) == expected:
        print(f"NPC_LLM_MODEL_OK {destination}")
        return 0
    if destination.exists():
        destination.unlink()
    url = (
        "https://huggingface.co/"
        f"{config['repo_id']}/resolve/{config['revision']}/{config['filename']}"
        "?download=true"
    )
    partial = destination.with_suffix(destination.suffix + ".part")
    if partial.exists():
        partial.unlink()
    print(f"Downloading pinned NPC model to {destination}")
    try:
        with urllib.request.urlopen(url, timeout=60) as response, partial.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
    except Exception as exc:
        partial.unlink(missing_ok=True)
        print(f"NPC_LLM_MODEL_DOWNLOAD_FAIL: {exc}", file=sys.stderr)
        return 1
    actual = sha256(partial)
    if actual != expected:
        partial.unlink(missing_ok=True)
        print(f"NPC_LLM_MODEL_HASH_FAIL expected={expected} actual={actual}", file=sys.stderr)
        return 1
    partial.replace(destination)
    print(f"NPC_LLM_MODEL_OK {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
