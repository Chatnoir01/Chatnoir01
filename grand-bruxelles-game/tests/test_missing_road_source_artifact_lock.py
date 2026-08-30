#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'data' / 'qa' / 'brussels_missing_road_source_artifact_lock.json'
EXPECTED_NIS = {'21002','21003','21005','21006','21007','21008','21009','21010','21011','21012','21014','21015','21016','21017','21018','21019'}
CLOSED = {
    'source_registration_authorized', 'road_cell_mapping_authorized', 'render_authorized',
    'collision_authorized', 'runtime_mount_authorized', 'safe_spawn_authorized', 'jouable_authorized'
}
ROOT_FIELDS = {
    'schema', 'source_run_id', 'source_head_sha', 'source_provider', 'source_license',
    'evidence_only', 'hash_semantics', 'municipalities', 'accounting', 'overlap_summary',
    'authorization'
}
MUNICIPALITY_FIELDS = {
    'id', 'niscode', 'osm_relation_id', 'osm_base_timestamp', 'artifact_id', 'artifact_digest',
    'manifest_file_sha256', 'raw_semantic_sha256', 'raw_file_sha256', 'game_semantic_sha256',
    'game_file_sha256', 'receipt_file_sha256', 'road_count', 'point_count'
}
ACCOUNTING_FIELDS = {
    'municipality_count', 'road_membership_count', 'unique_osm_road_count',
    'cross_municipality_duplicate_osm_id_count', 'duplicate_membership_excess',
    'point_count', 'duplicate_map_sha256'
}
HASH_SEMANTICS_FIELDS = {
    'file_sha256', 'receipt_normalized_game_source_sha256', 'receipt_raw_snapshot_sha256'
}
OVERLAP_SUMMARY_FIELDS = {'pairs', 'triples'}
HEX = set('0123456789abcdef')


def require_exact_fields(value: object, expected: set[str], label: str) -> dict[str, object]:
    assert type(value) is dict, f'{label}: expected object'
    assert set(value) == expected, f'{label} field set drift'
    return value


def require_sha256(value: object, label: str, prefix: bool = False) -> str:
    if type(value) is not str:
        raise AssertionError(f'{label}: expected string')
    if prefix:
        if not value.startswith('sha256:'):
            raise AssertionError(f'{label}: invalid sha256')
        raw = value[7:]
    else:
        raw = value
    if len(raw) != 64 or any(ch not in HEX for ch in raw):
        raise AssertionError(f'{label}: invalid sha256')
    return raw


def require_git_sha(value: object, label: str) -> str:
    if type(value) is not str or len(value) != 40 or any(ch not in HEX for ch in value):
        raise AssertionError(f'{label}: invalid git sha')
    return value


def require_positive_int(value: object, label: str, *, allow_zero: bool = False) -> int:
    if type(value) is not int or (value < 0 if allow_zero else value <= 0):
        raise AssertionError(f'{label}: invalid integer')
    return value


def validate_lock(lock: dict[str, object]) -> None:
    require_exact_fields(lock, ROOT_FIELDS, 'lock')
    assert lock['schema'] == 'grand-bruxelles-missing-road-source-artifact-lock-v1'
    assert type(lock['source_run_id']) is int and lock['source_run_id'] == 33286183671
    require_git_sha(lock['source_head_sha'], 'source_head_sha')
    assert lock['source_provider'] == 'OpenStreetMap contributors via Overpass API'
    assert lock['source_license'] == 'ODbL-1.0'
    assert lock['evidence_only'] is True

    hash_semantics = require_exact_fields(lock['hash_semantics'], HASH_SEMANTICS_FIELDS, 'hash_semantics')
    assert hash_semantics['file_sha256'] == 'exact stored artifact member bytes including trailing newline'
    assert hash_semantics['receipt_normalized_game_source_sha256'] == 'canonical JSON payload bytes without trailing newline'
    assert hash_semantics['receipt_raw_snapshot_sha256'] == 'canonical JSON payload bytes without trailing newline'

    authorization = require_exact_fields(lock['authorization'], CLOSED, 'authorization')
    assert all(authorization[key] is False for key in CLOSED)

    rows = lock['municipalities']
    assert type(rows) is list and len(rows) == 16
    assert all(type(row) is dict for row in rows)
    assert {row['niscode'] for row in rows} == EXPECTED_NIS
    assert len({row['artifact_id'] for row in rows}) == 16
    assert len({row['osm_relation_id'] for row in rows}) == 16

    for row in rows:
        require_exact_fields(row, MUNICIPALITY_FIELDS, 'municipality')
        assert type(row['id']) is str and row['id'] and row['id'] == row['id'].strip()
        assert type(row['niscode']) is str and row['niscode'] in EXPECTED_NIS
        assert type(row['osm_base_timestamp']) is str and row['osm_base_timestamp'].endswith('Z')
        require_positive_int(row['artifact_id'], f"{row['niscode']} artifact_id")
        require_positive_int(row['osm_relation_id'], f"{row['niscode']} osm_relation_id")
        require_positive_int(row['road_count'], f"{row['niscode']} road_count")
        require_positive_int(row['point_count'], f"{row['niscode']} point_count")
        assert row['point_count'] >= row['road_count'] * 2
        require_sha256(row['artifact_digest'], f"{row['niscode']} artifact_digest", prefix=True)
        for key in ('manifest_file_sha256','raw_semantic_sha256','raw_file_sha256','game_semantic_sha256','game_file_sha256','receipt_file_sha256'):
            require_sha256(row[key], f"{row['niscode']} {key}")
        assert row['raw_semantic_sha256'] != row['raw_file_sha256']
        assert row['game_semantic_sha256'] != row['game_file_sha256']

    accounting = require_exact_fields(lock['accounting'], ACCOUNTING_FIELDS, 'accounting')
    for key in ACCOUNTING_FIELDS - {'duplicate_map_sha256'}:
        require_positive_int(accounting[key], f'accounting {key}', allow_zero=key in {'cross_municipality_duplicate_osm_id_count', 'duplicate_membership_excess'})
    assert accounting['municipality_count'] == len(rows) == 16
    assert accounting['road_membership_count'] == sum(row['road_count'] for row in rows) == 19707
    assert accounting['point_count'] == sum(row['point_count'] for row in rows) == 118185
    assert accounting['cross_municipality_duplicate_osm_id_count'] == 586
    assert accounting['duplicate_membership_excess'] == 594
    assert accounting['unique_osm_road_count'] == 19113
    require_sha256(accounting['duplicate_map_sha256'], 'duplicate_map_sha256')

    overlap_summary = require_exact_fields(lock['overlap_summary'], OVERLAP_SUMMARY_FIELDS, 'overlap_summary')
    assert type(overlap_summary['pairs']) is dict
    assert type(overlap_summary['triples']) is dict
    assert all(type(key) is str and type(value) is int and value > 0 for key, value in overlap_summary['pairs'].items())
    assert all(type(key) is str and type(value) is int and value > 0 for key, value in overlap_summary['triples'].items())
    pair_count = sum(overlap_summary['pairs'].values())
    triple_count = sum(overlap_summary['triples'].values())
    assert pair_count + triple_count == 586
    assert pair_count + (triple_count * 2) == 594


def test_artifact_digest_requires_explicit_sha256_prefix() -> None:
    with pytest.raises(AssertionError, match='artifact_digest: invalid sha256'):
        require_sha256('0' * 64, 'artifact_digest', prefix=True)


def test_locked_batch_contract() -> None:
    validate_lock(json.loads(LOCK.read_text(encoding='utf-8')))


def test_root_semantic_field_drift_fails_closed() -> None:
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    mutated = copy.deepcopy(lock)
    mutated['safe_spawn_ready'] = True
    with pytest.raises(AssertionError, match='lock field set drift'):
        validate_lock(mutated)


def test_municipality_semantic_field_drift_fails_closed() -> None:
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    mutated = copy.deepcopy(lock)
    mutated['municipalities'][0]['playable'] = True
    with pytest.raises(AssertionError, match='municipality field set drift'):
        validate_lock(mutated)


def test_bool_cannot_masquerade_as_numeric_identity() -> None:
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    mutated = copy.deepcopy(lock)
    mutated['municipalities'][0]['artifact_id'] = True
    with pytest.raises(AssertionError, match='artifact_id: invalid integer'):
        validate_lock(mutated)


def test_ambiguous_municipality_membership_stays_closed() -> None:
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    assert lock['accounting']['cross_municipality_duplicate_osm_id_count'] > 0
    assert lock['authorization']['source_registration_authorized'] is False
    assert lock['authorization']['road_cell_mapping_authorized'] is False
    assert lock['authorization']['render_authorized'] is False
    assert lock['authorization']['collision_authorized'] is False
    assert lock['authorization']['runtime_mount_authorized'] is False
    assert lock['authorization']['safe_spawn_authorized'] is False
    assert lock['authorization']['jouable_authorized'] is False
