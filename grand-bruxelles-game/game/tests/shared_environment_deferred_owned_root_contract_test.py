from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game/scripts/anneessens_midi_sidewalk_runtime.gd"
LIFECYCLE = ROOT / "game/tests/shared_environment_lifecycle_contract_test.py"


def function_body(source: str, function_name: str) -> str:
    lines = source.splitlines()
    marker = f"func {function_name}("
    start = None
    for index, line in enumerate(lines):
        if line.startswith(marker):
            start = index + 1
            break
    if start is None:
        return ""
    body: list[str] = []
    for line in lines[start:]:
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break
        body.append(line)
    return "\n".join(body)


def main() -> None:
    runtime = RUNTIME.read_text(encoding="utf-8")
    lifecycle = LIFECYCLE.read_text(encoding="utf-8")
    release = function_body(runtime, "_release_owned_root")
    deferred = function_body(runtime, "_detach_and_free_owned_root")

    assert 'call_deferred("_detach_and_free_owned_root", owned_root)' in release
    assert "remove_child(" not in release
    assert "queue_free()" not in release
    assert "is_instance_valid(owned_root)" in deferred
    assert "owned_root.get_parent()" in deferred
    assert "parent.remove_child(owned_root)" in deferred
    assert "owned_root.queue_free()" in deferred

    # The central lifecycle gate must understand the tree-callback-safe deferred
    # ownership pattern instead of requiring synchronous detach/free tokens in
    # _release_owned_root(). This assertion is intentionally RED until the
    # central contract is upgraded.
    assert "_detach_and_free_owned_root" in lifecycle, (
        "shared Environment lifecycle gate does not recognize deferred owned-root disposal"
    )
    assert "call_deferred" in lifecycle, (
        "shared Environment lifecycle gate does not require deferred owned-root disposal"
    )

    print("SHARED_ENVIRONMENT_DEFERRED_OWNED_ROOT_CONTRACT_OK")


if __name__ == "__main__":
    main()
