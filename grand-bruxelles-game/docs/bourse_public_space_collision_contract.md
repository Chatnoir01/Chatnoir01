# Bourse public-space collision contract

This change keeps the official UrbIS sidewalk polygons as the sole planimetric geometry source for the Bourse public-space overlay.

- Render mesh remains at `base_surface_y_m + render_bias_m` to prevent z-fighting.
- Gameplay collision must use the same triangulated official polygon footprint at `base_surface_y_m`.
- The collision does not claim an authoritative source elevation.
- No curb height, wall height, slope, or vertical separation is inferred from the UrbIS planar source.
- Collision provenance is explicitly marked as `same_official_urbis_sidewalk_mesh` with `gameplay_base_surface_datum` as height authority.

The dedicated Godot test compares collision triangle topology/count and verifies every collision face lies on the base-surface datum rather than the presentation layer.
