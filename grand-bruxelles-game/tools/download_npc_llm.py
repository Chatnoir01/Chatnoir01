#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "npc_llm_model.json"
DOWNLOAD_ATTEMPTS = 4


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, partial: pathlib.Path) -> None:
    last_error: Exception | None = None
    for attempt in range(1, DOWNLOAD_ATTEMPTS + 1):
        partial.unlink(missing_ok=True)
        try:
            with urllib.request.urlopen(url, timeout=90) as response, partial.open("wb") as output:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    output.write(chunk)
            return
        except Exception as exc:
            last_error = exc
            partial.unlink(missing_ok=True)
            if attempt < DOWNLOAD_ATTEMPTS:
                time.sleep(attempt * 2)
    raise RuntimeError(f"download failed after {DOWNLOAD_ATTEMPTS} attempts: {last_error}")


def main() -> int:
    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    destination = ROOT / config["local_path"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    expected = config["sha256"].lower()
    if destination.exists() and sha256(destination) == expected:
        print(f"NPC_LLM_MODEL_OK {destination}")
        return 0
    destination.unlink(missing_ok=True)
    url = (
        "https://huggingface.co/"
        f"{config['repo_id']}/resolve/{config['revision']}/{config['filename']}"
        "?download=true"
    )
    partial = destination.with_suffix(destination.suffix + ".part")
    print(f"Downloading pinned NPC model to {destination}")
    try:
        download(url, partial)
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
