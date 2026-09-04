from pathlib import Path
import importlib.util
import pytest

SCRIPT = Path(__file__).parents[1] / 'tools' / 'select_quaternius_project.py'
spec = importlib.util.spec_from_file_location('selector', SCRIPT)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


def _scene(project: Path) -> Path:
    p = project / 'Models_with_rigging' / 'Master_Rigged.tscn'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text('[gd_scene]\n')
    return p


def test_selects_project_that_owns_pinned_scene_not_first_project(tmp_path: Path):
    wrong = tmp_path / 'aaa-empty-project'
    wrong.mkdir(); (wrong / 'project.godot').write_text('[application]\n')
    right = tmp_path / 'zzz-quaternius-project'
    right.mkdir(); (right / 'project.godot').write_text('[application]\n')
    _scene(right)
    assert selector.select_project_root(tmp_path) == right.resolve()


def test_duplicate_pinned_scene_fails_closed(tmp_path: Path):
    for name in ('one','two'):
        project = tmp_path / name
        project.mkdir(); (project / 'project.godot').write_text('[application]\n'); _scene(project)
    with pytest.raises(ValueError, match='exactly one pinned'):
        selector.select_project_root(tmp_path)


def test_scene_without_ancestor_project_fails_closed(tmp_path: Path):
    _scene(tmp_path / 'orphan')
    with pytest.raises(ValueError, match='no ancestor project'):
        selector.select_project_root(tmp_path)


def test_missing_archive_root_fails_closed(tmp_path: Path):
    with pytest.raises(ValueError, match='archive root missing'):
        selector.select_project_root(tmp_path / 'missing')
