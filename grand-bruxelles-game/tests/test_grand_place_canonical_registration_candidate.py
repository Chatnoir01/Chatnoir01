#!/usr/bin/env python3
import hashlib, importlib.util, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CELL = ROOT / 'data/cell_manifests/bxl-e148000-n170000-s500.json'
INDEX = ROOT / 'data/provenance/brussels_registered_cell_manifest_index.json'
CANDIDATE_REVIEW = ROOT / 'data/provenance/grand_place_canonical_manifest_candidate.review.json'
REG_REVIEW = ROOT / 'data/provenance/grand_place_canonical_registration.review.json'
SOURCE_MANIFEST = ROOT / 'data/urbis/remaining_brussels/cells/bxl-e148000-n170000-s500/manifest.json'
SOURCE_MEASUREMENT = ROOT / 'data/provenance/grand_place_urbis_source_cell.measurement.json'
SOURCE_RAW_ROOT = SOURCE_MANIFEST.parent / 'raw'
SOURCE_CANDIDATE_SHA = 'b454022050e850214eeb8d5345fe574e831dcaba6a832123a7dfe44070d0b020'
EXPECTED_CELL_SHA = '53cac9ef1e281b0971dc7bad44be378f8e8392cca753f9f6c2cdafa45dfddb37'
EXPECTED_INDEX_SEMANTIC = 'e3585c11cc54658d0cfc905540ee672907bad93927033cb9170e79991db69c38'
EXPECTED_SOURCE_MANIFEST_SHA = '4c18e124adfbdb230fcd357c444f58c1d532db2812f77d6f97380676f60e00c7'
EXPECTED_SOURCE_DIGEST = 'bbee45393ca07d86515f160e6eb9511c624440ccced97dff564b133eeafe7feb'
EXPECTED_SOURCE_SEMANTIC = '99cb25db4c95860c02dff5cf25c19cc5a4e11a75166f1fe92734edd1b5a0e7d4'
BASE = '78c169227fe70f2265a83c3ad30601b03bf9ee16'
EXPECTED_RAW = {
    'buildings': ('buildings.geojson', 496088, 'ce835a5752c7abbafde4f364cb29abfcba26c0ff60c334705e17f8654ae96681'),
    'street_axes': ('street_axes.geojson', 62928, '0e2b11ede03aa07a059d9e9bad840abe57148efe954f32961fc26293f607c099'),
    'street_surfaces': ('street_surfaces.geojson', 475278, 'ccb2021f5f44ffb269ba543b87ff41af8c6ef59d434240f143cecb40231c2789'),
    'train_network': ('train_network.geojson', 24216, 'be5c979bb11d0f4611639307b79ad7e5f636787b12fba0f4453433f98b6996c4'),
    'tram_network': ('tram_network.geojson', 24215, '734f0019084351601bf0d227bd9aaf4e91a885cd7a93577e5460ee43ce0f595e'),
}
EXPECTED_LAYER_COUNTS = {
    'buildings': 772,
    'street_axes': 97,
    'street_surfaces': 410,
    'train_network': 28,
    'tram_network': 28,
}


def load(path):
    return json.loads(path.read_text())


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert sha256(CELL) == EXPECTED_CELL_SHA
    assert sha256(SOURCE_MANIFEST) == EXPECTED_SOURCE_MANIFEST_SHA
    cell = load(CELL)
    candidate = load(CANDIDATE_REVIEW)
    review = load(REG_REVIEW)
    index = load(INDEX)
    source = load(SOURCE_MANIFEST)
    measurement = load(SOURCE_MEASUREMENT)

    # Historical candidate and the new canonical registration remain distinct phases.
    assert candidate['status'] == 'CANDIDATE_LOCKED_UNREGISTERED'
    assert candidate['candidate_manifest']['sha256'] == SOURCE_CANDIDATE_SHA
    assert candidate['semantic_sha256'] == 'bb0a23818b738b22b20aea1d9c37ecf794827e05d5d4ab8fed4f758d0c6f197e'

    # Canonical registration is bound to exact persisted, artifact-backed UrbIS source bytes.
    source_lock = review['source_lock']
    assert source_lock['source_manifest_path'] == 'data/urbis/remaining_brussels/cells/bxl-e148000-n170000-s500/manifest.json'
    assert source_lock['source_manifest_sha256'] == EXPECTED_SOURCE_MANIFEST_SHA
    assert source_lock['source_manifest_source_digest'] == EXPECTED_SOURCE_DIGEST
    assert source_lock['source_semantic_sha256'] == EXPECTED_SOURCE_SEMANTIC
    assert source_lock['measurement_path'] == 'data/provenance/grand_place_urbis_source_cell.measurement.json'
    assert source_lock['measurement_schema'] == 'grand-bruxelles-urbis-source-cell-lock-v2'
    assert source_lock['measurement_status'] == 'LOCKED_EXACT_SOURCE_ONLY_PERSISTED'
    assert source_lock['authority'] == 'Paradigm / Brussels-Capital Region'
    assert source_lock['license'] == 'CC0-1.0'
    assert source_lock['crs'] == 'EPSG:31370'
    assert source_lock['layer_feature_counts'] == EXPECTED_LAYER_COUNTS

    assert source['cell_id'] == 'bxl-e148000-n170000-s500'
    assert source['crs'] == 'EPSG:31370'
    assert source['bbox'] == [148000.0,170000.0,148500.0,170500.0]
    assert source['promotion'] == 'source_only_no_runtime_mutation'
    assert source['source_digest'] == EXPECTED_SOURCE_DIGEST
    assert {k: v['features'] for k, v in source['layers'].items()} == EXPECTED_LAYER_COUNTS
    assert source['layers']['buildings']['ownership_filtered'] == 61
    assert source['layers']['buildings']['invalid_ownership_features'] == 0

    assert measurement['schema'] == 'grand-bruxelles-urbis-source-cell-lock-v2'
    assert measurement['status'] == 'LOCKED_EXACT_SOURCE_ONLY_PERSISTED'
    assert measurement['target']['cell_id'] == source['cell_id']
    assert measurement['target']['crs'] == source['crs']
    assert measurement['target']['bbox'] == source['bbox']
    assert measurement['source']['authority'] == source_lock['authority']
    assert measurement['source']['license'] == source_lock['license']
    assert measurement['locked']['manifest_source_digest'] == EXPECTED_SOURCE_DIGEST
    assert measurement['locked']['source_semantic_sha256'] == EXPECTED_SOURCE_SEMANTIC
    assert {k: v['features'] for k, v in measurement['locked']['layers'].items()} == EXPECTED_LAYER_COUNTS
    persisted = measurement['persisted_artifact_bytes']['persistence']
    assert persisted['file_count'] == 7
    assert persisted['manifest_sha256'] == EXPECTED_SOURCE_MANIFEST_SHA
    assert persisted['source_semantic_sha256'] == EXPECTED_SOURCE_SEMANTIC
    for key, (filename, size, digest) in EXPECTED_RAW.items():
        path = SOURCE_RAW_ROOT / filename
        assert path.stat().st_size == size, key
        assert sha256(path) == digest, key
        assert persisted['raw_files'][key] == {'bytes': size, 'sha256': digest}, key

    assert cell['cell_id'] == 'bxl-e148000-n170000-s500'
    assert cell['crs'] == 'EPSG:31370'
    assert cell['bbox'] == [148000.0,170000.0,148500.0,170500.0]
    assert cell['geometry']['source_digest'] == EXPECTED_SOURCE_DIGEST
    assert cell['geometry']['layer_feature_counts'] == EXPECTED_LAYER_COUNTS
    assert cell['provenance']['authoritative_source_manifest_sha256'] == EXPECTED_SOURCE_MANIFEST_SHA
    assert cell['provenance']['source_semantic_sha256'] == EXPECTED_SOURCE_SEMANTIC
    assert cell['provenance']['license'] == 'CC0-1.0'
    assert cell['maturity']['state'] == 'data_ready'
    assert all(v is False for v in cell['maturity']['gates'].values())
    assert cell['terrain']['status'] == 'not_registered'
    assert cell['heights']['status'] == 'not_registered'
    assert cell['photo_match']['required'] is False
    assert cell['photo_match']['status'] == 'not_validated'
    assert cell['performance']['budget_pass'] is False

    assert review['status'] == 'REGISTRATION_CANDIDATE_EVIDENCE_ONLY'
    assert review['production_base_sha'] == BASE
    assert review['source_candidate_manifest_sha256'] == SOURCE_CANDIDATE_SHA
    assert review['canonical_manifest_sha256'] == EXPECTED_CELL_SHA
    assert review['registered_index_semantic_sha256'] == EXPECTED_INDEX_SEMANTIC
    assert review['registered_cell_count'] == 2
    assert review['target_registered'] is True
    assert all(v is False for v in review['runtime_authorization'].values())
    assert index['production_base_sha'] == BASE
    assert index['registered_cell_count'] == 2
    assert index['semantic_sha256'] == EXPECTED_INDEX_SEMANTIC
    rows = {r['cell_id']: r for r in index['entries']}
    assert set(rows) == {'bxl-e148000-n170000-s500','bxl-e149000-n169000-s500'}
    assert rows['bxl-e148000-n170000-s500']['manifest_sha256'] == EXPECTED_CELL_SHA
    for key in ['runtime_directory_scan_authorized','road_crosswalk_authorized','runtime_mount_authorized','rendered_geometry_authorized','collision_authorized','safe_spawn_authorized','jouable_promotion_authorized']:
        assert index[key] is False, key
    script = ROOT / 'tools/qa/build_registered_cell_manifest_index.py'
    spec = importlib.util.spec_from_file_location('builder', script)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    rebuilt = mod.build(ROOT / 'data/cell_manifests', ROOT, BASE)
    assert rebuilt == index
    print('GRAND_PLACE_CANONICAL_REGISTRATION_SOURCE_BYTES_LOCKED count=2 semantic=' + EXPECTED_INDEX_SEMANTIC)


if __name__ == '__main__':
    main()
