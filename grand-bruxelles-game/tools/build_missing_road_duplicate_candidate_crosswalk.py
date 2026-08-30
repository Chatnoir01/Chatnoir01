#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from zipfile import ZipFile

CLOSED = {
    'source_registration_authorized': False,
    'road_cell_mapping_authorized': False,
    'render_authorized': False,
    'collision_authorized': False,
    'runtime_mount_authorized': False,
    'safe_spawn_authorized': False,
    'jouable_authorized': False,
}
EXPECTED_SOURCE_SCHEMA = 'grand-bruxelles-municipality-road-source-acquisition-v1'
OUTPUT_SCHEMA = 'grand-bruxelles-road-duplicate-candidate-crosswalk-v1'

def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()

def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')

def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)

def bbox(points: list[list[float]]) -> list[float]:
    xs = [p[0] for p in points]; ys = [p[1] for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]

def load_lock(path: Path) -> dict:
    lock = json.loads(path.read_text(encoding='utf-8'))
    require(lock.get('schema') == 'grand-bruxelles-missing-road-source-artifact-lock-v1', 'unexpected lock schema')
    require(lock.get('evidence_only') is True, 'lock must stay evidence-only')
    require(lock.get('authorization') == CLOSED, 'lock authorization envelope is not closed')
    return lock

def build(lock_path: Path, artifact_dir: Path) -> dict:
    lock = load_lock(lock_path)
    locked_rows = {row['niscode']: row for row in lock['municipalities']}
    require(len(locked_rows) == lock['accounting']['municipality_count'] == 16, 'municipality lock count mismatch')
    memberships: dict[int, list[dict]] = defaultdict(list)
    source_artifacts: list[dict] = []
    road_membership_count = point_count = 0
    for niscode in sorted(locked_rows):
        row = locked_rows[niscode]
        matches = sorted(artifact_dir.glob(f'road-source-{niscode}-*.zip'))
        require(len(matches) == 1, f'{niscode}: expected exactly one locked artifact zip')
        archive = matches[0]; archive_bytes = archive.read_bytes()
        require(f"sha256:{sha256_bytes(archive_bytes)}" == row['artifact_digest'], f'{niscode}: artifact digest mismatch')
        with ZipFile(archive) as zf:
            game_members = [name for name in zf.namelist() if name.endswith('_road_source.game.json')]
            require(len(game_members) == 1, f'{niscode}: expected exactly one game source member')
            game_member = game_members[0]; game_bytes = zf.read(game_member)
            require(sha256_bytes(game_bytes) == row['game_file_sha256'], f'{niscode}: game file sha mismatch')
            game = json.loads(game_bytes)
        municipality = game.get('municipality', {}); acquisition = game.get('acquisition', {})
        require(municipality.get('niscode') == niscode, f'{niscode}: municipality NIS mismatch')
        require(municipality.get('id') == row['id'], f'{niscode}: municipality id mismatch')
        require(municipality.get('osm_relation_id') == row['osm_relation_id'], f'{niscode}: relation mismatch')
        require(acquisition.get('schema') == EXPECTED_SOURCE_SCHEMA, f'{niscode}: acquisition schema mismatch')
        require(game.get('source') == lock['source_provider'], f'{niscode}: source provider mismatch')
        require(game.get('license') == lock['source_license'], f'{niscode}: source license mismatch')
        require(game.get('authorization') == CLOSED, f'{niscode}: source authorization envelope is not closed')
        roads = game.get('roads'); require(type(roads) is list and len(roads) == row['road_count'], f'{niscode}: road count mismatch')
        seen: set[int] = set(); local_points = 0
        for road in roads:
            osm_id = road.get('osm_id'); require(type(osm_id) is int and osm_id > 0, f'{niscode}: invalid osm_id')
            require(osm_id not in seen, f'{niscode}: duplicate osm_id inside municipality source'); seen.add(osm_id)
            points = road.get('points'); require(type(points) is list and len(points) >= 2, f'{niscode}/{osm_id}: invalid points')
            for point in points:
                require(type(point) is list and len(point) == 2, f'{niscode}/{osm_id}: invalid point shape')
                require(all(type(v) in (int, float) and not isinstance(v, bool) and math.isfinite(v) for v in point), f'{niscode}/{osm_id}: invalid coordinate')
            local_points += len(points)
            memberships[osm_id].append({
                'municipality_id': row['id'], 'niscode': niscode, 'osm_relation_id': row['osm_relation_id'],
                'artifact_id': row['artifact_id'], 'artifact_digest': row['artifact_digest'], 'game_member': game_member,
                'game_file_sha256': row['game_file_sha256'], 'road_record_sha256': sha256_bytes(canonical_bytes(road)),
                'geometry_sha256': sha256_bytes(canonical_bytes(points)), 'point_count': len(points), 'bbox_m': bbox(points),
            })
        require(local_points == row['point_count'], f'{niscode}: point count mismatch')
        road_membership_count += len(roads); point_count += local_points
        source_artifacts.append({
            'municipality_id': row['id'], 'niscode': niscode, 'osm_relation_id': row['osm_relation_id'],
            'artifact_id': row['artifact_id'], 'artifact_digest': row['artifact_digest'], 'game_member': game_member,
            'game_file_sha256': row['game_file_sha256'], 'road_count': len(roads), 'point_count': local_points,
        })
    duplicates = {osm_id: rows for osm_id, rows in memberships.items() if len(rows) > 1}
    require(road_membership_count == lock['accounting']['road_membership_count'], 'aggregate road membership mismatch')
    require(point_count == lock['accounting']['point_count'], 'aggregate point count mismatch')
    require(len(memberships) == lock['accounting']['unique_osm_road_count'], 'aggregate unique road mismatch')
    require(len(duplicates) == lock['accounting']['cross_municipality_duplicate_osm_id_count'], 'duplicate road count mismatch')
    require(sum(len(rows) - 1 for rows in duplicates.values()) == lock['accounting']['duplicate_membership_excess'], 'duplicate membership excess mismatch')
    entries = []; membership_map: dict[str, list[str]] = {}; geometry_equivalent = 0; multiplicity = Counter()
    for osm_id in sorted(duplicates):
        rows = sorted(duplicates[osm_id], key=lambda r: (r['niscode'], r['municipality_id']))
        candidate_niscodes = [r['niscode'] for r in rows]
        require(len(set(candidate_niscodes)) == len(candidate_niscodes), f'{osm_id}: duplicate candidate municipality')
        geometry_is_equivalent = len({r['geometry_sha256'] for r in rows}) == 1 and len({r['road_record_sha256'] for r in rows}) == 1
        if geometry_is_equivalent: geometry_equivalent += 1
        multiplicity[len(rows)] += 1; membership_map[str(osm_id)] = candidate_niscodes
        entries.append([osm_id, candidate_niscodes, rows[0]['geometry_sha256'] if geometry_is_equivalent else None,
                        rows[0]['road_record_sha256'] if geometry_is_equivalent else None,
                        rows[0]['point_count'] if geometry_is_equivalent else None,
                        rows[0]['bbox_m'] if geometry_is_equivalent else None])
    return {
        'schema': OUTPUT_SCHEMA, 'production_base_sha': '__PRODUCTION_BASE_SHA__',
        'source_lock': {'path':'data/qa/brussels_missing_road_source_artifact_lock.json','source_run_id':lock['source_run_id'],
                        'source_head_sha':lock['source_head_sha'],'source_provider':lock['source_provider'],'source_license':lock['source_license'],
                        'locked_duplicate_map_sha256':lock['accounting']['duplicate_map_sha256']},
        'source_artifacts': source_artifacts,
        'accounting': {'municipality_count':len(source_artifacts),'road_membership_count':road_membership_count,'unique_osm_road_count':len(memberships),
                       'duplicate_osm_id_count':len(entries),'duplicate_membership_excess':sum(len(e[1])-1 for e in entries),'point_count':point_count,
                       'geometry_equivalent_duplicate_count':geometry_equivalent,'geometry_non_equivalent_duplicate_count':len(entries)-geometry_equivalent,
                       'pair_duplicate_count':multiplicity[2],'triple_duplicate_count':multiplicity[3],
                       'candidate_membership_sha256':sha256_bytes(canonical_bytes(membership_map)),'entries_sha256':sha256_bytes(canonical_bytes(entries))},
        'entry_fields':['osm_id','candidate_niscodes','geometry_sha256','road_record_sha256','point_count','bbox_m'],
        'decision': {'municipality_assignment_authorized':False,'spatial_cell_assignment_authorized':False,
                     'requires_explicit_administrative_boundary_crosswalk':True,'first_candidate_wins_forbidden':True},
        'authorization': CLOSED, 'entries': entries,
    }

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument('--lock',type=Path,required=True); parser.add_argument('--artifact-dir',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True); parser.add_argument('--production-base-sha',required=True); args=parser.parse_args()
    output=build(args.lock,args.artifact_dir)
    require(len(args.production_base_sha)==40 and all(ch in '0123456789abcdef' for ch in args.production_base_sha),'invalid production base sha')
    output['production_base_sha']=args.production_base_sha; args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,ensure_ascii=False,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8')
if __name__=='__main__': main()
