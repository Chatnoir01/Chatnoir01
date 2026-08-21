from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
JETTE = ROOT / "game" / "zones" / "laeken_jette" / "jette_phase2_zone.gd"
BRIDGE = ROOT / "game" / "scripts" / "brussels_city_machine_environment_runtime.gd"
RENDERER = ROOT / "game" / "scripts" / "brussels_osm_environment_runtime.gd"


class CityMachineEnvironmentSingleOwnerContract(unittest.TestCase):
    def test_jette_no_longer_mounts_environment_outside_city_machine_bridge(self) -> None:
        text = JETTE.read_text(encoding="utf-8")
        for stale_owner in ("OSM_ENVIRONMENT_RUNTIME", "OSM_ENVIRONMENT_DATA", "_build_osm_environment"):
            self.assertNotIn(stale_owner, text)

    def test_renderer_exposes_fail_closed_load_state(self) -> None:
        text = RENDERER.read_text(encoding="utf-8")
        self.assertIn("func loaded_ok() -> bool:", text)
        self.assertIn("func _validate_document_contract(document: Dictionary) -> bool:", text)
        for invariant in (
            'EXPECTED_SOURCE_CRS := "EPSG:4326"',
            'EXPECTED_PROJECTION_CRS := "EPSG:31370"',
            'EXPECTED_LICENSE := "ODbL-1.0"',
            'EXPECTED_AXES := "X=east, Y=up, Z=south"',
            'EXPECTED_UNITS := "metres"',
        ):
            self.assertIn(invariant, text)

    def test_bridge_marks_zone_active_only_after_renderer_accepts_artifact(self) -> None:
        text = BRIDGE.read_text(encoding="utf-8")
        load_check = 'if not renderer.has_method("loaded_ok") or not bool(renderer.call("loaded_ok")):'
        self.assertIn(load_check, text)
        self.assertLess(text.index(load_check), text.index("_active[zone] = renderer"))
        self.assertIn("renderer.queue_free()", text[text.index(load_check):text.index("_active[zone] = renderer")])


if __name__ == "__main__":
    unittest.main()
