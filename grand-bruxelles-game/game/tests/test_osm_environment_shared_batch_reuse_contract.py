from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def function_block(source: str, name: str) -> str:
    marker = f"func {name}("
    start = source.find(marker)
    assert start >= 0, f"missing function: {name}"
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def main() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    rebuild = function_block(source, "_rebuild")
    tree = function_block(source, "_build_tree_batches")
    lamps = function_block(source, "_build_lamp_batches")
    bollards = function_block(source, "_build_bollard_batches")
    batch = function_block(source, "_batch")

    assert "_clear_owned_batches()" not in rebuild, (
        "proximity rebuild must not destroy every shared environment MultiMesh before replacing transforms"
    )
    assert "reuse_existing" in tree, "tree rebuild must explicitly reuse canonical batches"
    assert "reuse_existing" in lamps, "street-lamp rebuild must explicitly reuse canonical batches"
    assert "reuse_existing" in bollards, "bollard rebuild must explicitly reuse canonical batches"

    for block, label in ((tree, "tree"), (lamps, "street lamp"), (bollards, "bollard")):
        assert "if rows.is_empty():\n        return" not in block, (
            f"{label} zero-row rebuild must reach the canonical writer so stale reused instances become zero"
        )

    assert "reuse_existing: bool = false" in batch, "canonical batch writer must retain opt-in reuse"
    assert "multimesh.instance_count = transforms.size()" in batch, (
        "reused MultiMesh instance_count must exactly follow the current transform count, including zero"
    )
    assert "instance.visible = _batches_visible" in batch, (
        "reused and new shared batches must preserve runtime visibility state"
    )

    print("OSM_SHARED_BATCH_REUSE_CONTRACT_OK")


if __name__ == "__main__":
    main()
