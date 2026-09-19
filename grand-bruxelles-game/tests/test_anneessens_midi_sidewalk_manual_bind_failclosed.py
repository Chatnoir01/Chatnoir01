from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiSidewalkManualBindFailClosedTest(unittest.TestCase):
    def test_failed_manual_bind_does_not_fall_back_to_automatic_watching(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        bind_block = _function_block(text, "_bind_scene(")
        failed_build = bind_block.split(
            "if not _build_from_existing_osm_roads():", 1
        )[1].split("if manual:", 1)[0]

        self.assertIn("_release_owned_root()", failed_build)
        self.assertIn("_scene = null", failed_build)
        self.assertNotIn(
            "_manual_binding = false",
            failed_build,
            "An explicit bind_scene() failure must not silently switch the runtime "
            "back to automatic production-scene discovery.",
        )
        self.assertNotIn(
            "_start_watching()",
            failed_build,
            "An explicit/manual bind failure must remain isolated instead of attaching "
            "SceneTree node-added/node-removed watchers.",
        )

        automatic_recovery = bind_block.split("if manual:", 1)[1]
        self.assertIn("_stop_watching()", automatic_recovery)
        self.assertIn("_start_watching()", automatic_recovery)


if __name__ == "__main__":
    unittest.main()
