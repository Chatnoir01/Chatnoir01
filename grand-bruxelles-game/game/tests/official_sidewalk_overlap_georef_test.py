import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OSM_PATH = ROOT / "data/osm/vertical_slice_01.game.json"
OFFICIAL_MANIFEST_PATH = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_geometry_manifest.json"
GEOREF_PATH = ROOT / "data/provenance/brussels_sidewalk_overlap_georef.json"
BOURSE_EVIDENCE_PATH = ROOT / "data/urbis/bourse_official_sidewalks.game.json"


def fail(message: str) -> None:
    raise AssertionError(message)


def load_json(path: Path) -> dict:
    if not path.exists():
        fail(f"required file missing: {path.relative_to(ROOT)}")
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        fail(f"expected object in {path.relative_to(ROOT)}")
    return value


def canonical_sha256(value: dict) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def apply_affine(coefficients: list[float], easting: float, northing: float) -> float:
    if len(coefficients) != 3:
        fail("affine coefficient vector must have three terms")
    return float(coefficients[0]) * easting + float(coefficients[1]) * northing + float(coefficients[2])


def test_overlap_requires_source_backed_georef() -> None:
    osm = load_json(OSM_PATH)
    official = load_json(OFFICIAL_MANIFEST_PATH)
    bourse = load_json(BOURSE_EVIDENCE_PATH)

    if osm.get("format") != "grand-bruxelles-osm-v1":
        fail("unexpected OSM game payload format")
    origin = osm.get("origin")
    if not isinstance(origin, dict) or set(origin) != {"lat", "lon"}:
        fail("OSM local-space origin contract missing")

    source = official.get("source")
    snapshot = official.get("source_snapshot")
    policy = official.get("policy")
    if not isinstance(source, dict) or source.get("crs") != "EPSG:31370":
        fail("official sidewalk persisted geometry must remain Lambert72 EPSG:31370")
    if source.get("publisher") != "Paradigm" or source.get("layer") != "bm_urbis:urbadm_ssw":
        fail("official sidewalk source identity drifted before overlap measurement")
    if source.get("license") != "CC0-1.0":
        fail("official sidewalk source license drifted before overlap measurement")
    if not isinstance(snapshot, dict) or int(snapshot.get("feature_count", 0)) != 3158:
        fail("official sidewalk feature count drifted before overlap measurement")
    if not isinstance(policy, dict) or policy.get("game_world_transform_applied") is not False:
        fail("persisted official geometry must remain untransformed before overlap georef validation")
    if policy.get("overlap_measurement_required_before_runtime") is not True:
        fail("official geometry no longer requires overlap measurement before runtime")

    if bourse.get("schema") != "grand-bruxelles-bourse-official-sidewalk-runtime-v1":
        fail("Bourse official sidewalk world-frame evidence schema drifted")
    bourse_source = bourse.get("source")
    if not isinstance(bourse_source, dict):
        fail("Bourse official sidewalk source metadata missing")
    if bourse_source.get("crs") != "EPSG:31370" or bourse_source.get("layer") != "bm_urbis:urbadm_ssw":
        fail("Bourse control source identity is not official Lambert72 sidewalk data")
    if bourse_source.get("license") != "CC0-1.0":
        fail("Bourse control source license drifted")

    georef = load_json(GEOREF_PATH)
    if georef.get("schema") != "grand-bruxelles-sidewalk-overlap-georef-v1":
        fail("unexpected sidewalk overlap georef schema")
    if georef.get("game_space") != "vertical_slice_01.game local X/Z meters":
        fail("game-space identity mismatch")
    if georef.get("official_space") != "EPSG:31370 Lambert72 XY meters":
        fail("official-space identity mismatch")
    if georef.get("horizontal_only") is not True:
        fail("overlap georef must be horizontal-only")
    if georef.get("curb_height_authorized") is not False:
        fail("georef must not authorize curb-height inference")
    if georef.get("vertical_profile_authorized") is not False:
        fail("georef must not authorize vertical-profile inference")
    if georef.get("runtime_geometry_authorized") is not False:
        fail("QA georef must not authorize runtime geometry")

    georef_policy = georef.get("policy")
    if not isinstance(georef_policy, dict) or georef_policy.get("overlap_qa_authorized") is not True:
        fail("validated georef must explicitly authorize horizontal overlap QA")
    for forbidden in ("runtime_use_authorized", "jouable_promotion_authorized", "vertical_inference_authorized"):
        if georef_policy.get(forbidden) is not False:
            fail(f"validated georef must not authorize {forbidden}")

    method = georef.get("method")
    if not isinstance(method, dict):
        fail("georef method missing")
    if method.get("kind") != "validated_affine_2d":
        fail("sidewalk overlap georef must use the reviewed affine world-frame evidence")
    controls = method.get("control_points")
    if not isinstance(controls, list) or len(controls) < 3:
        fail("at least three independently validated control points are required")
    source_ids = [str(control.get("source_id", "")) for control in controls if isinstance(control, dict)]
    if len(set(source_ids)) != len(controls):
        fail("georef controls must use distinct official sidewalk features")

    affine = method.get("affine")
    if not isinstance(affine, dict):
        fail("validated affine coefficients missing")
    x_coeff = affine.get("x_from_E_N")
    z_coeff = affine.get("z_from_E_N")
    if not isinstance(x_coeff, list) or not isinstance(z_coeff, list):
        fail("validated affine coefficient vectors missing")

    sidewalks = bourse.get("sidewalks")
    if not isinstance(sidewalks, list):
        fail("Bourse official sidewalk controls missing")
    by_id = {str(item.get("source_id")): item for item in sidewalks if isinstance(item, dict)}

    residuals: list[float] = []
    for control in controls:
        if not isinstance(control, dict):
            fail("malformed georef control")
        source_id = str(control.get("source_id", ""))
        source_feature = by_id.get(source_id)
        if source_feature is None:
            fail(f"georef control is not present in official Bourse evidence: {source_id}")
        vertex_index = int(control.get("source_vertex_index", -1))
        source_rings = source_feature.get("source_rings_epsg31370")
        world_rings = source_feature.get("world_rings_xz")
        if not isinstance(source_rings, list) or not source_rings or not isinstance(world_rings, list) or not world_rings:
            fail(f"Bourse evidence rings missing for {source_id}")
        source_ring = source_rings[0]
        world_ring = world_rings[0]
        if vertex_index < 0 or vertex_index >= len(source_ring) or vertex_index >= len(world_ring):
            fail(f"invalid control vertex index for {source_id}")

        expected_source = [float(value) for value in source_ring[vertex_index]]
        expected_world = [float(value) for value in world_ring[vertex_index]]
        declared_source = [float(value) for value in control.get("epsg31370_xy", [])]
        declared_world = [float(value) for value in control.get("game_xz", [])]
        if declared_source != expected_source or declared_world != expected_world:
            fail(f"control point does not exactly reproduce persisted official/world evidence for {source_id}")

        predicted_x = apply_affine(x_coeff, declared_source[0], declared_source[1])
        predicted_z = apply_affine(z_coeff, declared_source[0], declared_source[1])
        residuals.append(math.hypot(predicted_x - declared_world[0], predicted_z - declared_world[1]))

    measured_max_residual = max(residuals)
    declared_max_residual = float(method.get("max_horizontal_residual_m", 999.0))
    if measured_max_residual > 0.50 or declared_max_residual > 0.50:
        fail("georef residual exceeds 0.50 m overlap-QA tolerance")
    if measured_max_residual > declared_max_residual + 1e-12:
        fail("declared max residual understates measured control residual")

    evidence = method.get("evidence")
    if not isinstance(evidence, dict):
        fail("georef evidence metadata missing")
    if evidence.get("source_file") != "data/urbis/bourse_official_sidewalks.game.json":
        fail("georef evidence must point at the persisted Bourse official/world control file")
    if evidence.get("source_schema") != bourse.get("schema") or evidence.get("source_layer") != bourse_source.get("layer"):
        fail("georef evidence source identity drifted")
    if evidence.get("source_evidence_artifact_digest") != bourse_source.get("evidence_artifact_digest"):
        fail("georef evidence artifact digest drifted")

    digest_payload = {
        "source_file": evidence["source_file"],
        "source_schema": evidence["source_schema"],
        "source_layer": evidence["source_layer"],
        "source_evidence_artifact_digest": evidence["source_evidence_artifact_digest"],
        "controls": controls,
        "affine": affine,
    }
    if method.get("evidence_sha256") != canonical_sha256(digest_payload):
        fail("georef evidence digest does not match the reviewed controls and affine")


if __name__ == "__main__":
    test_overlap_requires_source_backed_georef()
    print("OFFICIAL_SIDEWALK_OVERLAP_GEOREF_OK")
