from pathlib import Path
import importlib.util
import pytest

SCRIPT = Path(__file__).parents[1] / 'tools' / 'select_quaternius_project.py'
spec = importlib.util.spec_from_file_location('selector', SCRIPT)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


def _project(root: Path, name: str) -> Path:
    p = root / name
    p.mkdir(parents=True)
    (p / 'project.godot').write_text('[application]\n')
    return p


def _source(project: Path) -> None:
    (project / 'UAL1_Standard.glb').write_bytes(b'x')


def _scene(project: Path, rel: str = 'Models_with_rigging/Master_Rigged.tscn') -> None:
    p = project / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('[gd_scene]\n')


def test_selects_common_nearest_owner_not_first_project(tmp_path: Path):
    wrong = _project(tmp_path, 'aaa-empty-project')
    right = _project(tmp_path, 'zzz-quaternius-project')
    _source(right); _scene(right)
    assert selector.select_project_root(tmp_path) == right.resolve()


def test_scene_path_is_not_hardcoded_when_source_owner_is_unambiguous(tmp_path: Path):
    right = _project(tmp_path, 'quaternius-project')
    _source(right); _scene(right, 'scenes/rigged/Master_Rigged.tscn')
    assert selector.select_project_root(tmp_path) == right.resolve()


def test_nested_project_owns_its_assets_not_parent(tmp_path: Path):
    parent = _project(tmp_path, 'outer')
    child = _project(parent, 'inner')
    _source(child); _scene(child)
    assert selector.select_project_root(tmp_path) == child.resolve()


def test_split_source_and_scene_across_projects_fails_closed(tmp_path: Path):
    a = _project(tmp_path, 'a'); b = _project(tmp_path, 'b')
    _source(a); _scene(b)
    with pytest.raises(ValueError, match='owning both pinned source and scene'):
        selector.select_project_root(tmp_path)


def test_duplicate_scene_inside_selected_project_fails_closed(tmp_path: Path):
    p = _project(tmp_path, 'p'); _source(p); _scene(p); _scene(p, 'other/Master_Rigged.tscn')
    with pytest.raises(ValueError, match='exactly one Master_Rigged'):
        selector.select_project_root(tmp_path)


def test_missing_archive_root_fails_closed(tmp_path: Path):
    with pytest.raises(ValueError, match='archive root missing'):
        selector.select_project_root(tmp_path / 'missing')
