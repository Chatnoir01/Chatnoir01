extends RefCounted

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const LAYERS := ["roads", "sidewalks", "tram_rails"]

# This registry is deliberately conservative: a shared vertical-slice runtime
# means source-backed context coverage, not a claim that a rail/sidewalk crosses
# every zone spawn. Missing typed source data is recorded instead of invented.
const COVERAGE := {
    "midi": {
        "roads": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
        "sidewalks": {"provider": "OpenStreetMap-adjacent authored placement", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
        "tram_rails": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
    },
    "anneessens": {
        "roads": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
        "sidewalks": {"provider": "OpenStreetMap-adjacent authored placement", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
        "tram_rails": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
    },
    "bourse": {
        "roads": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
        "sidewalks": {"provider": "OpenStreetMap-adjacent authored placement", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
        "tram_rails": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "vertical_slice_context"},
    },
    "grand_place": {
        "roads": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "surrounding_vertical_slice_context"},
        "sidewalks": {"provider": "OpenStreetMap-adjacent authored placement", "status": "shared_source_backed_runtime", "scope": "surrounding_vertical_slice_context"},
        "tram_rails": {"provider": "OpenStreetMap", "status": "shared_source_backed_runtime", "scope": "surrounding_vertical_slice_context"},
    },
    "ixelles": {
        "roads": {"provider": "UrbIS", "status": "official_presentation", "node": "OfficialIxellesStreetSurfaces/StreetSurfaces_S"},
        "sidewalks": {"provider": "UrbIS", "status": "official_presentation", "node": "OfficialIxellesStreetSurfaces/StreetSurfaces_SW"},
        "tram_rails": {"provider": "none", "status": "data_gap_current_main", "reason": "no dedicated source-backed tram layer in the production Ixelles microslice"},
    },
    "atomium": {
        "roads": {"provider": "none", "status": "data_gap_current_main", "reason": "catalog has no dedicated production ground-network source"},
        "sidewalks": {"provider": "none", "status": "data_gap_current_main", "reason": "catalog has no dedicated production ground-network source"},
        "tram_rails": {"provider": "none", "status": "data_gap_current_main", "reason": "catalog has no dedicated production ground-network source"},
    },
    "jette": {
        "roads": {"provider": "UrbIS", "status": "official_neutral_presentation", "node": "JetteOfficialStreetSurfaces"},
        "sidewalks": {"provider": "UrbIS", "status": "data_gap_typed_semantics", "reason": "current StreetSurface bundle does not expose a safe sidewalk-only runtime node"},
        "tram_rails": {"provider": "UrbIS", "status": "official_alignment_presentation", "node": "JetteOfficialTramNetwork", "geometry_claim": "source alignment only; no fabricated dual-rail gauge"},
    },
}

static func zone_ids() -> Array[String]:
    var ids: Array[String] = []
    for zone_id: Variant in COVERAGE.keys():
        ids.append(str(zone_id))
    ids.sort()
    return ids

static func layer(zone_id: String, layer_id: String) -> Dictionary:
    if not COVERAGE.has(zone_id):
        return {}
    var zone: Dictionary = COVERAGE[zone_id]
    return (zone.get(layer_id, {}) as Dictionary).duplicate(true)
