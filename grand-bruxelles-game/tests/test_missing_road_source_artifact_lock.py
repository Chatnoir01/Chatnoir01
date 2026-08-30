#!/usr/bin/env python3
from __future__ import annotations

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
HEX = set('0123456789abcdef')


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


def test_artifact_digest_requires_explicit_sha256_prefix() -> None:
    with pytest.raises(AssertionError, match='artifact_digest: invalid sha256'):
        require_sha256('0' * 64, 'artifact_digest', prefix=True)


def test_locked_batch_contract() -> None:
    lock = json.loads(LOCK.read_text(encoding='utf-8'))
    assert lock['schema'] == 'grand-bruxelles-missing-road-source-artifact-lock-v1'
    assert lock['source_run_id'] == 33286183671
    require_git_sha(lock['source_head_sha'], 'source_head_sha')
    assert lock['source_provider'] == 'OpenStreetMap contributors via Overpass API'
    assert lock['source_license'] == 'ODbL-1.0'
    assert lock['evidence_only'] is True
    assert set(lock['authorization']) == CLOSED
    assert all(lock['authorization'][key] is False for key in CLOSED)

    rows = lock['municipalities']
    assert type(rows) is list and len(rows) == 16
    assert {row['niscode'] for row in rows} == EXPECTED_NIS
    assert len({row['artifact_id'] for row in rows}) == 16
    assert len({row['osm_relation_id'] for row in rows}) == 16

    for row in rows:
        assert type(row['artifact_id']) is int and row['artifact_id'] > 0
        assert type(row['osm_relation_id']) is int and row['osm_relation_id'] > 0
        assert type(row['road_count']) is int and row['road_count'] > 0
        assert type(row['point_count']) is int and row['point_count'] >= row['road_count'] * 2
        require_sha256(row['artifact_digest'], f"{row['niscode']} artifact_digest", prefix=True)
        for key in ('manifest_file_sha256','raw_semantic_sha256','raw_file_sha256','game_semantic_sha256','game_file_sha256','receipt_file_sha256'):
            require_sha256(row[key], f"{row['niscode']} {key}")
        assert row['raw_semantic_sha256'] != row['raw_file_sha256']
        assert row['game_semantic_sha256'] != row['game_file_sha256']

    accounting = lock['accounting']
    assert accounting['municipality_count'] == len(rows) == 16
    assert accounting['road_membership_count'] == sum(row['road_count'] for row in rows) == 19707
    assert accounting['point_count'] == sum(row['point_count'] for row in rows) == 118185
    assert accounting['cross_municipality_duplicate_osm_id_count'] == 586
    assert accounting['duplicate_membership_excess'] == 594
    assert accounting['unique_osm_road_count'] == 19113
    require_sha256(accounting['duplicate_map_sha256'], 'duplicate_map_sha256')

    pair_count = sum(lock['overlap_summary']['pairs'].values())
    triple_count = sum(lock['overlap_summary']['triples'].values())
    assert pair_count + triple_count == 586
    assert pair_count + (triple_count * 2) == 594


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
