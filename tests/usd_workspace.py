"""Restart fidelity, portability, rollback, writers and real save interruption."""
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('session', ROOT/'scripts/usd-session.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)


def focal(stage):
    return next(c for c in stage.request('curves', path='/Camera', time=12)['curves']
                if c['name'] == 'focalLength')


def key(stage, value):
    stage.request('attribute', path='/Camera', name='focalLength', time=12, value=value)


def snapshot(stage):
    return stage.request('snapshot')


def rejected(stage, op, **args):
    before = snapshot(stage)
    try:
        stage.request(op, **args)
    except ValueError:
        pass
    else:
        raise AssertionError('Accepted invalid ' + op)
    assert snapshot(stage) == before, 'Failed operation modified active authoring state'


@contextlib.contextmanager
def fault(point):
    previous = os.environ.get('ATLAS_WORKSPACE_FAULT')
    os.environ['ATLAS_WORKSPACE_FAULT'] = point
    try:
        yield
    finally:
        if previous is None:
            os.environ.pop('ATLAS_WORKSPACE_FAULT', None)
        else:
            os.environ['ATLAS_WORKSPACE_FAULT'] = previous


def check_reopen(directory, expected=90):
    with api.StageSession() as stage:
        state = stage.request('open_workspace', source=str(directory))
        assert state['edit_target'] == 'animation'
        assert [l['name'] for l in state['layers'] if l['editable']] == ['session', 'shot', 'animation']
        assert not state['unsaved_changes']
        assert state['undo_count'] == state['redo_count'] == 0
        assert focal(stage)['value'] == expected
        assert any(p['id'] == '/World/Loaded/Child' for p in state['prims'])
        assert not any(p['id'] == '/World/Unloaded/Child' for p in state['prims'])
        # Both conflicting keys survive, including the weaker masked opinion.
        stage.request('select_layer', name='shot')
        stage.request('clear_layer')
        assert focal(stage)['value'] == 65
        stage.request('undo')
        assert focal(stage)['value'] == expected
        assert state['source'] == str(directory.parent/'art/source.usda')


with tempfile.TemporaryDirectory(prefix='usd-workspace-', dir=ROOT/'build') as tmp:
    root = Path(tmp)
    project = root/'project'
    art = project/'art'
    art.mkdir(parents=True)
    source = art/'source.usda'
    payload = art/'payload.usda'
    payload.write_text('#usda 1.0\ndef Xform "Asset" {\n def Xform "Child" {}\n}\n')
    source.write_text('''#usda 1.0
def Camera "Camera" {
 float focalLength.timeSamples = {0:40,24:80}
}
def Xform "World" {
 def Xform "Loaded" (prepend payload = @payload.usda@</Asset>) {}
 def Xform "Unloaded" (prepend payload = @payload.usda@</Asset>) {}
}
''')
    originals = {p: p.read_bytes() for p in [source, payload]}
    directory = project/'workspace'
    with api.StageSession() as stage:
        stage.request('open', source=str(source))
        assert snapshot(stage)['unsaved_changes']
        stage.request('create_layer', name='animation')
        key(stage, 65)
        stage.request('create_layer', name='shot')
        key(stage, 90)
        stage.request('select_layer', name='animation')
        stage.request('load', path='/World/Loaded')
        result = stage.request('save_workspace', destination=str(directory))
        assert result['kind'] == 'workspace'
        assert not snapshot(stage)['unsaved_changes']
        stage.request('select_layer', name='shot')
        assert snapshot(stage)['unsaved_changes']
        stage.request('undo')
        assert not snapshot(stage)['unsaved_changes'], 'Undo to saved state stayed dirty'
        # Composed delivery keeps its original contract; saving it does not clean a workspace.
        key(stage, 66)
        stage.request('save', destination=str(project/'delivery.usda'))
        assert snapshot(stage)['unsaved_changes']
        stage.request('undo')
    check_reopen(directory)
    manifest_path = directory/'workspace.json'
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    for record in [manifest['source'], manifest['session'], *manifest['layers'], *manifest['dependencies']]:
        data = (directory/record['path']).read_bytes()
        assert record['sha256'] == hashlib.sha256(data).hexdigest()
        assert record['bytes'] == len(data)
        assert not Path(record['path']).is_absolute()

    # Moving an entire project tree retains relative owned and external paths.
    moved = root/'relocated'
    project.rename(moved)
    directory = moved/'workspace'
    source = moved/'art/source.usda'
    payload = moved/'art/payload.usda'
    check_reopen(directory)
    manifest_path = directory/'workspace.json'

    # A stale session must not silently overwrite a generation another writer published.
    with api.StageSession() as first, api.StageSession() as second:
        first.request('open_workspace', source=str(directory))
        second.request('open_workspace', source=str(directory))
        first.request('save_workspace', destination=str(directory))
        rejected(second, 'save_workspace', destination=str(directory))
        assert not snapshot(first)['unsaved_changes']
    check_reopen(directory)

    # Writer lock and source identity failures preserve the previous publication.
    before = manifest_path.read_bytes()
    with api.StageSession() as stage:
        stage.request('open_workspace', source=str(directory))
        with (directory/'workspace.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            rejected(stage, 'save_workspace', destination=str(directory))
        source.write_text(source.read_text()+'\n# external change\n')
        rejected(stage, 'save_workspace', destination=str(directory))
        source.write_bytes(originals[project/'art/source.usda'])
        payload.unlink()
        rejected(stage, 'open_workspace', source=str(directory))
        payload.write_bytes(originals[project/'art/payload.usda'])
    assert manifest_path.read_bytes() == before

    # Malformed/obsolete workspaces never replace an active stage.
    manifest = json.loads(before)
    with api.StageSession() as stage:
        stage.request('open', source=str(source))
        for mutation in [lambda m: m.update(version=0), lambda m: m.update(version=2),
                         lambda m: m.update(edit_target='missing'),
                         lambda m: m['layers'][0].update(path='../art/source.usda'),
                         lambda m: m['layers'][0].update(sha256='0'*64),
                         lambda m: m['load_rules'].append({'path': '../invalid', 'rule': 0}),
                         lambda m: m['layers'].append(m['layers'][0].copy()),
                         lambda m: m.update(dependencies=m['dependencies'][:1])]:
            changed = json.loads(before)
            mutation(changed)
            manifest_path.write_text(json.dumps(changed))
            rejected(stage, 'open_workspace', source=str(directory))
        manifest_path.write_bytes(before)
        layer_path = directory/manifest['layers'][0]['path']
        data = layer_path.read_bytes()
        layer_path.unlink()
        layer_path.symlink_to(source)
        rejected(stage, 'open_workspace', source=str(directory))
        layer_path.unlink()
        layer_path.write_bytes(data)
    check_reopen(directory)

    # Crash each publication boundary in a separate native process. Recovery picks
    # exactly the manifest's complete generation, ignoring unpublished files.
    for mode in ['error', 'kill']:
        for point in ['generation_created', 'layers_synced', 'manifest_synced', 'manifest_published']:
            trial = root/(mode+'-'+point)
            shutil.copytree(moved, trial)
            trial_workspace = trial/'workspace'
            original_manifest = (trial_workspace/'workspace.json').read_bytes()
            with fault(mode+':'+point), api.StageSession() as stage:
                stage.request('open_workspace', source=str(trial_workspace))
                stage.request('select_layer', name='shot')
                key(stage, 95)
                stage.request('select_layer', name='animation')
                try:
                    stage.request('save_workspace', destination=str(trial_workspace))
                except (ValueError, RuntimeError):
                    pass
                else:
                    raise AssertionError('Fault injection did not interrupt save')
            new_manifest = (trial_workspace/'workspace.json').read_bytes()
            if point != 'manifest_published':
                assert new_manifest == original_manifest
            check_reopen(trial_workspace, 95 if point == 'manifest_published' else 90)
            with api.StageSession() as stage:
                stage.request('open_workspace', source=str(trial_workspace))
                stage.request('save_workspace', destination=str(trial_workspace))
            check_reopen(trial_workspace, 95 if point == 'manifest_published' else 90)

    assert source.read_bytes() == originals[project/'art/source.usda']
    assert payload.read_bytes() == originals[project/'art/payload.usda']

print('USD workspace passed: conflicting layer restart, targets/payloads, SHA-256, '
      'relocation, dirty/undo, source immutability, stale writers, malformed/version/path '
      'rejection and eight real interruption/I/O fault cases')
