#!/usr/bin/env python3
import json, math, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[1]
contract = json.loads((root/'data/qa/grand_place_town_hall_left_gallery_face_map.json').read_text())
geom = json.loads((root/'data/urbis/grand_place_lod2/1655673.game.json').read_text())
assert contract['status'] == 'evidence_only'
assert contract['interpretation']['runtime_authorized'] is False
assert contract['interpretation']['openings_authorized'] is False
assert contract['interpretation']['arch_dimensions_authorized'] is False
assert contract['interpretation']['right_gallery_dimensions_reusable'] is False
face_id = contract['target']['candidate_face_id']
faces = {f['id']: f for f in geom['faces']}
assert face_id in faces, face_id
face = faces[face_id]
assert face['type'] == 'WALLSURFACE'
pts = contract['target']['ground_chain_points']
a, b = pts
span = math.dist((a[0], a[2]), (b[0], b[2]))
assert abs(span - contract['target']['official_chain_span_m']) < 1e-9
flat = {tuple(v) for tri in face['triangles'] for v in tri if abs(v[1]) < 1e-9}
assert tuple(a) in flat and tuple(b) in flat
assert len(contract['heritage_source']['facts_used']) >= 4
print(f'PASS left-gallery face map: {face_id} span={span:.6f}m; runtime/openings remain unauthorized')
