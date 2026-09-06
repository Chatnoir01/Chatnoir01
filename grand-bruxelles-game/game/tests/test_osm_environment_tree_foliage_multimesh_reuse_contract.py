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
    refresh = function_block(source, "_refresh_tree_lod")
    foliage = function_block(source, "_build_tree_foliage_batches")
    batch = function_block(source, "_batch")

    assert "_clear_tree_foliage_batches()" not in refresh, (
        "Tree LOD refresh must not destroy foliage MultiMeshInstance3D nodes before rebuilding presentation"
    )
    assert "_build_tree_foliage_batches(_rendered_trees, anchor, true)" in refresh, (
        "Tree LOD refresh must explicitly request reuse of the existing foliage batches"
    )
    assert "reuse_existing: bool = false" in foliage, (
        "foliage batching must expose a fail-safe reuse flag while preserving full-rebuild behavior"
    )
    assert "if rows.is_empty() and not reuse_existing:" in foliage, (
        "zero-row LOD refresh must reach the reuse writer so both foliage MultiMesh instance counts are cleared"
    )
    assert "if rows.is_empty():\n        _tree_lod_boundary_margin_m = 0.0\n    else:" in foliage, (
        "zero-row reuse may reset the precomputed margin but must not return before the canonical batch writer"
    )
    zero_margin = foliage.index("if rows.is_empty():")
    first_batch = foliage.index('_batch("TreeFoliageDark"', zero_margin)
    assert "return" not in foliage[zero_margin:first_batch], (
        "zero-row reused foliage must flow through to instance_count=0 instead of leaving stale geometry visible"
    )
    assert 'reuse_existing)' in foliage, (
        "both foliage material batches must forward the reuse decision to the canonical batch writer"
    )
    assert "reuse_existing: bool = false" in batch, (
        "canonical batch writer must support opt-in MultiMesh reuse"
    )
    assert "instance.multimesh = multimesh" in batch, "batch ownership must remain explicit"
    assert "multimesh.instance_count = transforms.size()" in batch, (
        "reused MultiMesh instance_count must exactly track current transforms, including zero"
    )

    print("OSM_TREE_FOLIAGE_MULTIMESH_REUSE_CONTRACT_OK")


if __name__ == "__main__":
    main()
