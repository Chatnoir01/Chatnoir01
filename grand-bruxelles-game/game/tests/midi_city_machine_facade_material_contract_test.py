#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATERIAL = ROOT / "game/scripts/midi_city_machine_facade_material.gd"
ZONE = ROOT / "game/zones/midi/midi_city_machine_zone.gd"

material = MATERIAL.read_text(encoding="utf-8")
zone = ZONE.read_text(encoding="utf-8")

assert 'MATERIAL_FAMILY := "midi_city_machine_labo_facade_v1"' in material
for marker in [
    'material.set_meta("procedural_only", true)',
    'material.set_meta("geometry_changed", false)',
    'material.set_meta("semantic_windows_claimed", false)',
    'material.set_meta("semantic_doors_claimed", false)',
    'material.set_meta("building_material_identity_claimed", false)',
    'material.set_meta("jouable_authorized", false)',
    'material.set_meta("promotion_performed", false)',
]:
    assert marker in material, marker

assert 'material_override = _building_facade_material if facade_labo_enabled else null' in zone
assert '"scope": "midi_machine_labo"' in zone
assert '"geometry_changed": false' in zone
assert '"jouable_authorized": false' in zone
assert '"promotion_performed": false' in zone

print("MIDI_CITY_MACHINE_FACADE_STATIC_CONTRACT_OK ab=true geometry_changed=false semantics=false promotion=false jouable=false")
