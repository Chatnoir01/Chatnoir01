#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "validate_asset_provenance.py"
spec = importlib.util.spec_from_file_location("validate_asset_provenance", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)
validate = module.validate

HEADER = "asset_id\tsource_url\tauthor\tlicense\tattribution_required\tderivative_terms\tlocal_path\tnotes\n"


class AssetProvenanceTests(unittest.TestCase):
    def make_root(self) -> Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        (root / "assets").mkdir()
        return root

    def test_unregistered_asset_is_rejected(self) -> None:
        root = self.make_root()
        (root / "assets" / "LICENSE_REGISTRY.tsv").write_text(HEADER, encoding="utf-8")
        (root / "assets" / "texture.png").write_bytes(b"png")
        self.assertIn("unregistered asset: assets/texture.png", validate(root))

    def test_complete_registered_asset_passes(self) -> None:
        root = self.make_root()
        (root / "assets" / "texture.png").write_bytes(b"png")
        row = "texture\tlocal-provenance\tExample\tCC0-1.0\tfalse\tpermissive\tassets/texture.png\ttest\n"
        (root / "assets" / "LICENSE_REGISTRY.tsv").write_text(HEADER + row, encoding="utf-8")
        self.assertEqual([], validate(root))

    def test_missing_file_is_rejected(self) -> None:
        root = self.make_root()
        row = "texture\tlocal-provenance\tExample\tCC0-1.0\tfalse\tpermissive\tassets/missing.png\ttest\n"
        (root / "assets" / "LICENSE_REGISTRY.tsv").write_text(HEADER + row, encoding="utf-8")
        self.assertTrue(any("local_path does not exist" in error for error in validate(root)))

    def test_gitkeep_is_not_treated_as_distributable_asset(self) -> None:
        root = self.make_root()
        (root / "assets" / "LICENSE_REGISTRY.tsv").write_text(HEADER, encoding="utf-8")
        placeholder = root / "assets" / "characters" / "source" / ".gitkeep"
        placeholder.parent.mkdir(parents=True)
        placeholder.write_text("", encoding="utf-8")
        self.assertEqual([], validate(root))


if __name__ == "__main__":
    unittest.main()
