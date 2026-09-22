from pathlib import Path
import unittest


RUNTIME = Path(__file__).resolve().parents[1] / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkDiagnosticContractTests(unittest.TestCase):
    """Keep the runtime observability surface used by deterministic Godot witnesses intact."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.runtime = RUNTIME.read_text(encoding="utf-8")

    def test_sidewalk_count_diagnostic_is_public_and_constant_time(self) -> None:
        self.assertIn("func diagnostic_sidewalk_count() -> int:\n    return _sidewalk_count", self.runtime)

    def test_collision_count_diagnostic_is_public_and_constant_time(self) -> None:
        self.assertIn("func diagnostic_collision_count() -> int:\n    return _collision_count", self.runtime)

    def test_root_diagnostic_exposes_owned_root_without_mutation(self) -> None:
        self.assertIn("func diagnostic_root() -> Node3D:\n    return _root", self.runtime)


if __name__ == "__main__":
    unittest.main()
