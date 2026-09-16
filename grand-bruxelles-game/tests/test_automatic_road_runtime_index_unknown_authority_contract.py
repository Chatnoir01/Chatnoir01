from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"


def _loader_body() -> str:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.index("func _load_runtime_index() -> bool:")
    end = text.index("\nfunc runtime_index_road_count()", start)
    return text[start:end]


def test_runtime_index_rejects_unknown_authorization_keys_before_documents() -> None:
    """Unknown authority rails must fail closed instead of being silently ignored."""
    body = _loader_body()
    marker = "authorization.keys()"
    assert marker in body, (
        "runtime loader never validates the authorization key set; an unknown future authority rail "
        "could be silently ignored while the source-only index is accepted"
    )
    assert body.index(marker) < body.index("var documents: Variant"), (
        "authorization key-set validation must complete before any runtime-index document registration"
    )
