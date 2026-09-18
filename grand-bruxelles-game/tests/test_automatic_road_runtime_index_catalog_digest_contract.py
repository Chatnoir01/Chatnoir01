from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_catalog_digest_is_typed_and_canonical_before_documents() -> None:
    body = _loader()
    documents = body.index("var documents: Variant")
    authorization = body.index('var authorization: Variant = index.get("authorization", {})')

    digest_binding = 'var catalog_sha256: Variant = index.get("catalog_sha256", "")'
    digest_guard = (
        'if typeof(catalog_sha256) != TYPE_STRING or _canonical_sha256(catalog_sha256).is_empty():\n'
        '        return false'
    )

    assert digest_binding in body, "runtime-index must bind catalog_sha256 explicitly"
    assert body.count(digest_binding) == 1, "catalog_sha256 must have one canonical binding"
    assert digest_guard in body, "catalog_sha256 must be an exact canonical lowercase SHA-256 string"
    assert body.count(digest_guard) == 1, "catalog digest validation must have one canonical boundary"
    assert body.index(digest_binding) < body.index(digest_guard) < authorization < documents, (
        "catalog digest provenance must fail closed before authorization and document registration"
    )

    assert 'str(index.get("catalog_sha256", ""))' not in body, (
        "catalog digest provenance must not use string coercion"
    )
