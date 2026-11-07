import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "tools" / "verify_urbis_height_archives.py"
SPEC = importlib.util.spec_from_file_location("verify_urbis_height_archives", TOOL)
verify = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(verify)


class HeightArchiveValidationTest(unittest.TestCase):
    def test_tile_bbox(self):
        self.assertEqual(verify.tile_bbox("149168"), (149000, 168000, 150000, 169000))
        self.assertEqual(verify.tile_bbox("149169"), (149000, 169000, 150000, 170000))
        with self.assertRaises(ValueError):
            verify.tile_bbox("14916x")

    def test_url_requires_official_https_host(self):
        verify.validate_source_url("https://urbisdownload.datastore.brussels/x.zip")
        for url in (
            "http://urbisdownload.datastore.brussels/x.zip",
            "https://example.com/x.zip",
            "https://urbisdownload.datastore.brussels/x.tif",
        ):
            with self.assertRaises(ValueError):
                verify.validate_source_url(url)

    def test_zip_rejects_path_traversal_and_preserves_sidecars(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            good = root / "good.zip"
            with zipfile.ZipFile(good, "w") as zf:
                zf.writestr("grid/tile.tif", b"tiff")
                zf.writestr("grid/tile.tfw", b"0.5\n0\n0\n-0.5\n149000.25\n168999.75\n")
            self.assertEqual(verify.safe_tiff_members(good), ["grid/tile.tif"])
            extracted = verify.extract_archive_safely(good, root / "out")
            self.assertEqual({p.name for p in extracted}, {"tile.tif", "tile.tfw"})
            self.assertTrue((root / "out" / "grid" / "tile.tfw").is_file())

            bad = root / "bad.zip"
            with zipfile.ZipFile(bad, "w") as zf:
                zf.writestr("../escape.tif", b"x")
            with self.assertRaises(ValueError):
                verify.safe_tiff_members(bad)
            with self.assertRaises(ValueError):
                verify.extract_archive_safely(bad, root / "escape")

    def test_metadata_requires_lambert72_and_exact_tile_extent(self):
        valid = {
            "crs_epsg": 31370,
            "width": 2000,
            "height": 2000,
            "count": 1,
            "bounds": [149000.0, 168000.0, 150000.0, 169000.0],
            "resolution": [0.5, 0.5],
        }
        verify.validate_raster_metadata("149168", valid)
        with self.assertRaises(ValueError):
            verify.validate_raster_metadata("149168", dict(valid, crs_epsg=4326))
        with self.assertRaises(ValueError):
            verify.validate_raster_metadata("149168", dict(valid, bounds=[149100.0, 168000.0, 150100.0, 169000.0]))

    def test_pair_alignment_rejects_dsm_dtm_grid_drift(self):
        base = {"width": 10, "height": 10, "crs_epsg": 31370, "bounds": [149000, 168000, 150000, 169000],
                "resolution": [100, 100], "transform": [100, 0, 149000, 0, -100, 169000]}
        dsm = {"archives": [{"tile": "149168", "raster": base}]}
        dtm = {"archives": [{"tile": "149168", "raster": dict(base)}]}
        verify.validate_pair_alignment(dsm, dtm)
        dtm["archives"][0]["raster"] = dict(base, resolution=[50, 50])
        with self.assertRaises(ValueError):
            verify.validate_pair_alignment(dsm, dtm)


if __name__ == "__main__":
    unittest.main()
