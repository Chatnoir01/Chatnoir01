import importlib.util
import pathlib
import unittest
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "capture_urbis_orthophoto.py"
SPEC = importlib.util.spec_from_file_location("capture_urbis_orthophoto", TOOL)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class OrthophotoCaptureTests(unittest.TestCase):
    def test_parse_bbox_accepts_lambert72_cell(self):
        self.assertEqual(
            MODULE.parse_bbox("147000,169000,147500,169500"),
            (147000.0, 169000.0, 147500.0, 169500.0),
        )

    def test_parse_bbox_rejects_reversed_extent(self):
        with self.assertRaises(ValueError):
            MODULE.parse_bbox("147500,169000,147000,169500")

    def test_build_url_mirrors_official_inspire_preview(self):
        url = MODULE.build_wms_url((147000, 169000, 147500, 169500), width=800, height=600)
        parsed = urllib.parse.urlparse(url)
        query = urllib.parse.parse_qs(parsed.query)
        self.assertEqual(parsed.scheme, "https")
        self.assertEqual(parsed.netloc, "geoservices-urbis.irisnet.be")
        self.assertEqual(parsed.path, "/geoserver/inspire/wms")
        self.assertEqual(query["service"], ["WMS"])
        self.assertEqual(query["version"], ["1.1.0"])
        self.assertEqual(query["request"], ["GetMap"])
        self.assertEqual(query["layers"], ["inspire:Ortho"])
        self.assertEqual(query["srs"], ["EPSG:31370"])
        self.assertEqual(query["bbox"], ["147000,169000,147500,169500"])
        self.assertEqual(query["width"], ["800"])
        self.assertEqual(query["height"], ["600"])
        self.assertEqual(query["format"], ["image/png"])

    def test_build_url_rejects_invalid_dimensions(self):
        with self.assertRaises(ValueError):
            MODULE.build_wms_url((147000, 169000, 147500, 169500), width=0)


if __name__ == "__main__":
    unittest.main()
