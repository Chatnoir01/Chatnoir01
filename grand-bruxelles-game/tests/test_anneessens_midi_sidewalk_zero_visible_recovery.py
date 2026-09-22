from pathlib import Path
import unittest


RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class ZeroVisibleRoadRecoveryContract(unittest.TestCase):
    """A visibility-only mutation must remain observable when it removes the last proxy.

    The runtime watches every GeneratedRoads/Road_* node, including invisible roads.  If a
    rebuild with zero eligible visible roads is treated as a failed bind, _release_owned_root()
    clears those watches and stops the mutation timer.  A later visible=true mutation then has
    no SceneTree add/remove event to wake the runtime, so the environment can remain stale
    indefinitely.  Zero rendered proxies is therefore a valid fail-closed *bound* state as long
    as GeneratedRoads exists; missing GeneratedRoads remains a bind failure.
    """

    @classmethod
    def setUpClass(cls):
        cls.source = RUNTIME.read_text(encoding="utf-8")

    def _function_body(self, name: str) -> str:
        marker = f"func {name}"
        self.assertIn(marker, self.source)
        tail = self.source.split(marker, 1)[1]
        next_func = tail.find("\nfunc ")
        return tail if next_func < 0 else tail[:next_func]

    def test_zero_proxy_build_is_not_a_binding_failure(self):
        body = self._function_body("_build_from_existing_osm_roads")
        self.assertIn('get_node_or_null("BrusselsOSM/GeneratedRoads")', body)
        self.assertIn("if roads == null:", body)
        self.assertNotIn(
            "return _sidewalk_count > 0",
            body,
            "zero visible/eligible roads currently tears down every road watch and makes a later visibility-only recovery unobservable",
        )
        self.assertRegex(
            body,
            r"(?m)^\s*return true\s*$",
            "once GeneratedRoads exists, an empty proxy set must stay bound so invisible roads remain watched",
        )

    def test_invisible_roads_are_watched_before_render_filter(self):
        body = self._function_body("_build_from_existing_osm_roads")
        watch = body.find("_watch_alignment_road_mutations(road)")
        visibility_filter = body.find("if not road.visible:")
        self.assertGreaterEqual(watch, 0)
        self.assertGreater(visibility_filter, watch)

    def test_empty_bound_state_keeps_polling(self):
        bind = self._function_body("_bind_scene")
        self.assertIn("_ensure_mutation_poll_timer()", bind)
        poll = self._function_body("_poll_alignment_road_mutations")
        self.assertIn("_alignment_road_refs.keys()", poll)


if __name__ == "__main__":
    unittest.main()
