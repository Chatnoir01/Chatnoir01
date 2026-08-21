import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data" / "qa" / "playable_zone_catalog.json"
SELECTOR = ROOT / "game" / "scripts" / "zone_selector_runtime.gd"
JETTE_ZONE = ROOT / "game" / "zones" / "laeken_jette" / "jette_phase2_zone.gd"
RUNTIME = ROOT / "game" / "scripts" / "brussels_osm_environment_runtime.gd"
ENVIRONMENT = ROOT / "data" / "osm" / "zones" / "jette" / "environment.game.json"


class CityMachineEnvironmentRuntimeIntegration(unittest.TestCase):
    def _jette(self) -> dict:
        document = json.loads(CATALOG.read_text(encoding="utf-8"))
        return next(zone for zone in document["zones"] if zone["id"] == "jette")

    def test_jette_catalog_owns_environment_artifact_contract(self) -> None:
        zone = self._jette()
        expected = "res://data/osm/zones/jette/environment.game.json"
        self.assertEqual(zone.get("environment_artifact"), expected)
        self.assertIn(expected, zone["requires"])

    def test_selector_mounts_environment_from_zone_contract(self) -> None:
        text = SELECTOR.read_text(encoding="utf-8")
        self.assertIn(
            'const OSM_ENVIRONMENT_RUNTIME := preload("res://game/scripts/brussels_osm_environment_runtime.gd")',
            text,
        )
        self.assertIn("func _mount_environment_if_required(main: Node, zone: Dictionary) -> bool:", text)
        self.assertIn("environment_artifact", text)
        self.assertIn("_mount_environment_if_required(main, zone)", text)

    def test_jette_zone_no_longer_hardcodes_environment_mount(self) -> None:
        text = JETTE_ZONE.read_text(encoding="utf-8")
        self.assertNotIn("OSM_ENVIRONMENT_DATA", text)
        self.assertNotIn("OSM_ENVIRONMENT_RUNTIME", text)
        self.assertNotIn("_build_osm_environment()", text)

    def test_runtime_validates_full_city_machine_contract_fail_closed(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        for required in (
            'EXPECTED_SOURCE_CRS := "EPSG:4326"',
            'EXPECTED_PROJECTION_CRS := "EPSG:31370"',
            'EXPECTED_LICENSE := "ODbL-1.0"',
            'EXPECTED_AXES := "X=east, Y=up, Z=south"',
            'EXPECTED_UNITS := "metres"',
            'func _validate_document_contract(document: Dictionary) -> bool:',
            'func loaded_ok() -> bool:',
        ):
            self.assertIn(required, text)

        artifact = json.loads(ENVIRONMENT.read_text(encoding="utf-8"))
        self.assertEqual(artifact["format"], "grand-bruxelles-osm-zone-environment-v1")
        self.assertEqual(artifact["source_crs"], "EPSG:4326")
        self.assertEqual(artifact["projection_crs"], "EPSG:31370")
        self.assertEqual(artifact["license"], "ODbL-1.0")
        self.assertEqual(artifact["game_origin"]["axes"], "X=east, Y=up, Z=south")
        self.assertEqual(artifact["game_origin"]["units"], "metres")
        self.assertEqual(sum(artifact["stats"][kind] for kind in ("tree", "street_lamp", "bollard")), len(artifact["environment_points"]))


if __name__ == "__main__":
    unittest.main()
