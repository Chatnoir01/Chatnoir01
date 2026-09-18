from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


def _function_block(text: str, name: str) -> str:
    marker = f"func {name}"
    start = text.index(marker)
    next_func = text.find("\nfunc ", start + len(marker))
    return text[start:] if next_func == -1 else text[start:next_func]


class AnneessensMidiSidewalkEmptyRoadsFailClosedTest(unittest.TestCase):
    def test_empty_generated_roads_does_not_commit_scene_binding(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        bind_block = _function_block(text, "_bind_scene(")
        build_block = _function_block(text, "_build_from_existing_osm_roads(")

        self.assertIn(
            "func _build_from_existing_osm_roads() -> bool:",
            build_block,
            "Road discovery must report whether any source-aligned proxy was actually built.",
        )
        self.assertIn(
            "if not _build_from_existing_osm_roads():",
            bind_block,
            "Binding must fail closed when GeneratedRoads exists but yields no eligible source roads.",
        )
        failed_build = bind_block.split("if not _build_from_existing_osm_roads():", 1)[1].split("if manual:", 1)[0]
        self.assertIn(
            "_release_owned_root()",
            failed_build,
            "A failed build must not leave an empty authoritative sidewalk root mounted.",
        )
        self.assertIn(
            "_scene = null",
            failed_build,
            "A failed automatic bind must release scene authority so a later valid scene state can retry.",
        )
        self.assertIn(
            "_start_watching()",
            failed_build,
            "A failed bind must retain event-driven recovery for late GeneratedRoads population.",
        )
        self.assertNotIn(
            "_schedule_bind()",
            failed_build,
            "An empty build must not immediately self-reschedule and spin the deferred queue.",
        )
        self.assertIn(
            "return _sidewalk_count > 0",
            build_block,
            "Successful binding must be evidenced by at least one generated proxy, not node presence alone.",
        )

    def test_late_road_population_retries_through_scene_tree_event(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        watcher_block = _function_block(text, "_on_node_added(")
        schedule_block = _function_block(text, "_schedule_bind(")

        self.assertIn(
            "_schedule_bind()",
            watcher_block,
            "Late GeneratedRoads/Road_* nodes must cause an event-driven retry after an empty bind.",
        )
        self.assertIn(
            "_bind_scheduled",
            schedule_block,
            "Event-driven recovery must stay coalesced so bursts of generated road nodes queue one bind.",
        )
        self.assertIn(
            "call_deferred(\"_try_bind\")",
            schedule_block,
            "Recovery must remain deferred until the newly-added road node is fully mounted.",
        )


if __name__ == "__main__":
    unittest.main()
