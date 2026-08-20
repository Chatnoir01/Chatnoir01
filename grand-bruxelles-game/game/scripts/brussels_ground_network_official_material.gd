extends RefCounted

const MATERIAL_FAMILY := "brussels_ground_network_official_v1"
const PROVIDER_URBIS := "UrbIS"

static func create_material(layer: String, provider: String = PROVIDER_URBIS) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.cull_mode = BaseMaterial3D.CULL_DISABLED

    match layer:
        "road":
            material.albedo_color = Color(0.13, 0.135, 0.145, 1.0)
            material.roughness = 0.92
            material.metallic = 0.02
        "sidewalk":
            material.albedo_color = Color(0.36, 0.355, 0.34, 1.0)
            material.roughness = 0.96
            material.metallic = 0.0
        "tram_rail":
            material.albedo_color = Color(0.20, 0.205, 0.215, 1.0)
            material.roughness = 0.43
            material.metallic = 0.56
        _:
            # Jette's current official StreetSurface bundle is not typed finely
            # enough to claim every polygon is asphalt or sidewalk. Keep the
            # presentation intentionally neutral until source semantics improve.
            material.albedo_color = Color(0.25, 0.255, 0.26, 1.0)
            material.roughness = 0.94
            material.metallic = 0.0

    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("provider", provider)
    material.set_meta("source_geometry", "official_existing_geometry")
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("license_claimed_by_presentation_runtime", false)
    material.set_meta("geometry_changed", false)
    return material
