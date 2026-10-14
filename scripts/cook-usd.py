"""OpenUSD preflight and Blender conversion into Atlas's transactional cooker.

USD remains the authoring source; the runtime consumes native Atlas assets.
External tool paths may be supplied by ATLAS_BLENDER and ATLAS_USD_INSPECT.
"""
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile
import io
import stat
from pathlib import PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
MAX_DEPENDENCIES = 4096

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def executable(variable, default):
    path = Path(os.environ.get(variable, str(default))).resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise ValueError(f'Missing USD tool: {path}; set {variable} (see docs/ATLAS_UPGRADES.md)')
    return path

def run(command, timeout=180, env=None):
    try:
        result = subprocess.run(list(map(str, command)), capture_output=True, text=True,
                                timeout=timeout, check=False, env=env)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError('USD tool failed: ' + str(error)) from error
    if result.returncode:
        raise ValueError(f'USD tool exited {result.returncode}: ' + (result.stderr + result.stdout)[-4000:])
    return result.stdout

def cook_package(source, output, asset_id, hlod_distance, hlod_transition, hlod_error, api, usd_root=None):
    source=source.resolve()
    if usd_root and not source.is_relative_to(Path(usd_root).resolve()):
        raise ValueError('USDZ source must be inside --usd-root')
    data=api.bounded_read(source)
    try:
        archive=zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as error:
        raise ValueError('Invalid USDZ archive') from error
    with archive:
        entries=archive.infolist()
        if not entries or len(entries)>MAX_DEPENDENCIES:raise ValueError('USDZ entry count exceeds profile')
        names=set();total=0
        for entry in entries:
            path=PurePosixPath(entry.filename)
            if (not entry.filename or entry.filename!=str(path) or path.is_absolute() or '..' in path.parts
                or '\\' in entry.filename or '\0' in entry.filename or ':' in entry.filename
                or entry.filename in names or entry.is_dir() or stat.S_ISLNK(entry.external_attr>>16)):
                raise ValueError('Unsafe or duplicate USDZ entry')
            names.add(entry.filename);total+=entry.file_size
            if entry.compress_type!=zipfile.ZIP_STORED or entry.flag_bits&1 or entry.file_size>api.MAX_FILE or total>api.MAX_BUNDLE:
                raise ValueError('USDZ must contain bounded uncompressed, unencrypted files')
        first=PurePosixPath(entries[0].filename)
        if first.suffix.lower() not in ('.usd','.usda','.usdc'):raise ValueError('First USDZ entry must be its root USD layer')
        directory=ROOT/'build/usd-packages'/hashlib.sha256(data).hexdigest()
        directory.mkdir(parents=True,exist_ok=True)
        for entry in entries:
            destination=directory/entry.filename
            if not destination.resolve().is_relative_to(directory.resolve()):raise ValueError('USDZ cache path escapes extraction root')
            try:payload=archive.read(entry)
            except (zipfile.BadZipFile,RuntimeError,NotImplementedError) as error:
                raise ValueError('Invalid USDZ archive payload') from error
            destination.parent.mkdir(parents=True,exist_ok=True)
            if not destination.exists() or api.bounded_read(destination)!=payload:api.atomic(destination,payload)
    return cook(directory/str(first),output,asset_id,hlod_distance,hlod_transition,hlod_error,api,directory,package=(source,data,names))

def cook(source, output, asset_id, hlod_distance, hlod_transition, hlod_error, api, usd_root=None, package=None):
    source = source.resolve()
    root = Path(usd_root).resolve() if usd_root else source.parent
    if not source.is_relative_to(root):
        raise ValueError('USD source must be inside --usd-root')
    api.bounded_read(source)
    inspector = executable('ATLAS_USD_INSPECT', ROOT / '.deps/usd-tools/bin/atlas-usd-inspect')
    blender = executable('ATLAS_BLENDER', ROOT / '.deps/blender-source/build/bin/blender')
    worker = Path(__file__).with_name('usd-blender-export.py')
    report = json.loads(run([inspector, source]))
    if report['unresolved']:
        raise ValueError('Unresolved USD dependencies: ' + ', '.join(report['unresolved'][:8]))
    if report['unsupported']:
        raise ValueError('Unsupported USD features: ' + '; '.join(report['unsupported'][:8]))
    if report.get('geometry_bakes') and (report['animated'] or report['skeletons']):
        raise ValueError('Subdivision baking currently requires a static, unskinned stage')
    if not report['meshes']:
        raise ValueError('USD stage has no meshes')
    if (not all(math.isfinite(report[k]) for k in ('start', 'end', 'time_codes_per_second', 'meters_per_unit'))
        or report['end'] < report['start'] or report['end'] - report['start'] > 10000
        or report['time_codes_per_second'] <= 0 or report['meters_per_unit'] <= 0):
        raise ValueError('Invalid USD units or animation duration (maximum 10000 frames)')
    if len(report['dependencies']) > MAX_DEPENDENCIES:
        raise ValueError('USD dependency count exceeds 4096')
    dependencies = {}
    total = 0
    for name in report['dependencies']:
        path = Path(name).resolve()
        if not path.is_relative_to(root):
            raise ValueError(f'USD dependency outside asset root: {name}; set --usd-root to the common asset directory')
        if package and path.relative_to(root).as_posix() not in package[2]:
            raise ValueError("USDZ reference is not a declared archive entry")
        data = api.bounded_read(path)
        total += len(data)
        if total > api.MAX_BUNDLE:
            raise ValueError('USD source bundle exceeds 256 MiB')
        dependencies[str(path)] = data
    if package:dependencies[str(package[0])]=package[1]
    hashes = {p: hashlib.sha256(data).hexdigest() for p, data in sorted(dependencies.items())}
    # Cache keys include actual tool binaries and adapter code, not just timestamps.
    tool_hashes = {str(p): digest(p) for p in (blender, inspector, worker, Path(__file__))}
    key = hashlib.sha256(json.dumps({'inputs': hashes, 'tools': tool_hashes}, sort_keys=True).encode()).hexdigest()
    cache = Path(os.environ.get('ATLAS_USD_CACHE_DIR', ROOT / 'build/usd-cache')) / key
    glb, worker_report = cache / 'stage.glb', cache / 'conversion.json'
    valid = False
    try:
        index = json.loads((cache / 'cache.json').read_text())
        valid = set(index) == {'stage.glb', 'conversion.json'} and all(
            hashlib.sha256(api.bounded_read(cache / name)).hexdigest() == value
            for name, value in index.items())
    except (OSError, ValueError, TypeError):
        pass
    if not valid:
        cache.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='usd-', dir=cache.parent) as temporary:
            temporary = Path(temporary)
            run([inspector, source, temporary / 'composed.usdc'])
            text = run([blender, '--background', '--factory-startup', '-setaudio', 'None', '--disable-autoexec',
                        '--python-exit-code', '1', '--python', worker, '--', temporary / 'composed.usdc',
                        temporary / 'stage.glb', temporary / 'conversion.json',
                        '1' if report['animated'] else '0', json.dumps(report.get('geometry_bakes', [])),
                        json.dumps({key:report[key] for key in ('conversion_grid_factor','conversion_time_codes_per_second','conversion_start','conversion_end')})], timeout=600,
                       # Audaspace enumerates OpenAL devices even with sound None.
                       # The documented null backend prevents headless workers
                       # from initializing a PulseAudio connection during that probe.
                       env={**os.environ,'ALSOFT_DRIVERS':'null','SDL_AUDIO_DRIVER':'dummy','SDL_AUDIODRIVER':'dummy'})
            converted = json.loads((temporary / 'conversion.json').read_text())
            if converted['mesh_objects'] != report['meshes']:
                raise ValueError('USD conversion changed mesh-object count; bake unsupported visibility/instancing first')
            if converted['armatures'] != report['skeletons']:
                raise ValueError('USD conversion changed skeleton count')
            index = {}
            for name in ('stage.glb', 'conversion.json'):
                data = api.bounded_read(temporary / name)
                api.atomic(cache / name, data)
                index[name] = hashlib.sha256(data).hexdigest()
            api.atomic(cache / 'conversion.log', text)
            api.atomic(cache / 'cache.json', json.dumps(index, sort_keys=True))
    for name, data in dependencies.items():
        if api.bounded_read(Path(name)) != data:
            raise ValueError('USD source changed during conversion; retry the import')
    converted = json.loads(worker_report.read_text())
    gltf = api.Gltf(glb)
    for material in gltf.doc.get('materials', []):
        if material.get('extensions'):
            raise ValueError('USD material needs unsupported runtime extensions: ' +
                             ', '.join(material['extensions']) + '; bake to the supported metallic/roughness material model')
    visibility=visibility_assets(report,gltf.doc,asset_id)
    del gltf
    runtime_lights = {light['id'] for light in report.get('lights', []) + report.get('local_lights', [])}
    authoring_only = [p for p in report['prims'] if p['type'].endswith('Light') and p['path'] not in runtime_lights]
    provenance = {'format': 'atlas-usd-source-1', 'source': str(package[0] if package else source), 'asset_root': str(package[0].parent if package else root),
        'dependencies': hashes, 'tools': tool_hashes, 'stage': report, 'conversion': converted,
        'authoring_only_prims': authoring_only,
        'runtime_policy': 'Meshes, supported PBR materials, skeletons and sampled TRS animation. Named camera samples are in cameras.atlascameras for AuthoredCamera3D; Distant/constant dome light samples are in lights.atlaslights for AuthoredLighting3D; other lights remain authoring data. Companion camera/light tracks support their declared animation profiles; morph clips use MorphTrack before deformation. Camera exposure uses the OpenUSD physical exposure scale; DOF and custom clipping planes remain unsupported.'}
    if authoring_only:
        print(f'USD: {len(authoring_only)} lights retained in authoring source only; see {asset_id}-source.json', file=sys.stderr)
    return api._cook(glb, output, asset_id, hlod_distance, hlod_transition, hlod_error,
                     extra_dependencies=dependencies, provenance=provenance, auxiliary={**visibility, **camera_assets(report), **light_assets(report), **camera_track_assets(report), **light_track_assets(report), **local_light_assets(report)})


def camera_assets(report):
    cameras = report.get('cameras', [])
    if len(cameras) > 256:
        raise ValueError('USD camera count exceeds 256')
    rows = ['ATLAS_CAMERAS_2']
    for camera in cameras:
        identity = camera['id']
        if any(c in identity for c in '\t\r\n\0'):
            raise ValueError('Invalid camera identity')
        values = camera['world'] + camera['projection'] + [camera['exposure_scale']]
        if len(values) != 33 or not all(math.isfinite(v) for v in values):
            raise ValueError('Invalid USD camera matrices')
        rows.append('\t'.join([identity] + [format(v, '.17g') for v in values]))
    return {'cameras.atlascameras': '\n'.join(rows)+'\n'} if cameras else {}


def light_assets(report):
    lights = report.get('lights', [])
    if len(lights)>256:
        raise ValueError('USD light sample count exceeds 256')
    rows = ['ATLAS_LIGHTS_1']
    for light in lights:
        if any(c in light['id'] for c in '\t\r\n\0'):
            raise ValueError('Invalid light identity')
        values = light['direction']+light['rgb']
        if len(values)!=6 or not all(math.isfinite(v) for v in values):
            raise ValueError('Invalid light sample')
        rows.append('\t'.join([light['id'],light['type']]+[format(v,'.17g') for v in values]))
    return {'lights.atlaslights':'\n'.join(rows)+'\n'} if lights else {}


def camera_track_assets(report):
    tracks = report.get('camera_tracks', [])
    rows = ['ATLAS_CAMERA_TRACKS_2']
    count = 0
    for track in tracks:
        if any(c in track['id'] for c in '\t\r\n\0'):
            raise ValueError('Invalid camera track identity')
        previous = -1
        projection = None
        for sample in track['samples']:
            count += 1
            if count > 16384:
                raise ValueError('Camera animation exceeds sample budget')
            if sample['seconds'] <= previous:
                raise ValueError('Camera times must be strictly increasing')
            previous = sample['seconds']
            if projection is not None and projection != sample['projection_type']:
                raise ValueError('Animated projection-type switching is unsupported')
            projection = sample['projection_type']
            values = [sample['seconds']] + sample['world'][12:15] + sample['rotation'] + sample['projection'] + [sample['exposure_scale']]
            if len(values) != 25 or not all(math.isfinite(v) for v in values):
                raise ValueError('Invalid camera animation sample')
            rows.append('\t'.join([track['id']] + [format(v, '.17g') for v in values]))
    return {'camera-tracks.atlascameratracks': '\n'.join(rows)+'\n'} if tracks else {}


def light_track_assets(report):
    tracks = report.get('light_tracks', [])
    rows = ['ATLAS_LIGHT_TRACKS_1']
    count = 0
    for track in tracks:
        if any(c in track['id'] for c in '\t\r\n\0'):
            raise ValueError('Invalid light track identity')
        previous = None
        for sample in track['samples']:
            count += 1
            if count > 16384:
                raise ValueError('Light animation exceeds sample budget')
            if previous is not None:
                if sample['seconds'] <= previous['seconds']:
                    raise ValueError('Light sample times must increase')
                if sum(a*b for a,b in zip(sample['direction'],previous['direction'])) < -.9999:
                    raise ValueError('Light direction turns 180 degrees in one sample; increase USD frame rate')
            previous = sample
            values = [sample['seconds']] + sample['direction'] + sample['rgb']
            if len(values)!=7 or not all(math.isfinite(v) for v in values):
                raise ValueError('Invalid light animation sample')
            rows.append('\t'.join([track['id'],sample['type']] + [format(v,'.17g') for v in values]))
    return {'light-tracks.atlaslighttracks':'\n'.join(rows)+'\n'} if tracks else {}


def local_light_assets(report):
    lights=report.get('local_lights', [])
    if len(lights)>32:
        raise ValueError('Local light count exceeds 32')
    rows=['ATLAS_LOCAL_LIGHTS_1']
    for light in lights:
        if any(c in light['id'] for c in '\t\r\n\0'):
            raise ValueError('Invalid local light identity')
        values=light['position']+light['intensity']+light['direction']+[light['inner'],light['outer']]
        if len(values)!=11 or not all(math.isfinite(v) for v in values):
            raise ValueError('Invalid local light values')
        rows.append('\t'.join([light['id']]+[format(v,'.17g') for v in values]))
    return {'local-lights.atlaslocallights':'\n'.join(rows)+'\n'} if lights else {}


def visibility_assets(report,doc,asset_id):
    tracks={track['id']:track['samples'] for track in report.get('visibility_tracks',[])}
    rows=['ATLAS_VISIBILITY_1'];seen=set();keys=0;track_count=0
    for ni,node in enumerate(doc.get('nodes',[])):
        extra=node.get('extras',{});identity=extra.get('atlas_visibility')
        if identity is None:continue
        if identity not in tracks or 'mesh' not in node:raise ValueError('Invalid converted visibility identity')
        seen.add(identity)
        for pi,primitive in enumerate(doc['meshes'][node['mesh']]['primitives']):
            asset=asset_id+'/node/'+extra.get('atlas_id',str(ni))+'/primitive/'+primitive.get('extras',{}).get('atlas_id',str(pi))
            track_count+=1
            if track_count>4096 or len(asset.encode())>4096 or any(c in asset for c in '\t\r\n\0'):raise ValueError('Invalid visibility asset key or track budget')
            for sample in tracks[identity]:
                rows.append('\t'.join([asset,format(sample['seconds'],'.17g'),'1' if sample['visible'] else '0']));keys+=1
                if keys>100000:raise ValueError('Visibility companion exceeds 100000 keys')
    if set(tracks)!=seen:raise ValueError('USD visibility mapping was lost during conversion')
    return {'visibility.atlasvisibility':'\n'.join(rows)+'\n'} if tracks else {}
