"""USD authoring integration: composition, animation, caching and failure atomicity."""
import importlib.util
import json
import os
import subprocess
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('atlas_cook', ROOT / 'scripts/cook-assets.py')
cook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cook)
BASE = '''#usda 1.0
(defaultPrim = "Asset")
def Xform "Asset" (
    prepend variantSets = "size"
    variants = { string size = "small" }
) {
    def Mesh "Shape" {
        uniform token subdivisionScheme = "none"
        int[] faceVertexCounts = [3]
        int[] faceVertexIndices = [0, 1, 2]
        rel material:binding = </Asset/Paint>
    }
    def Material "Paint" {
        token outputs:surface.connect = </Asset/Paint/Surface.outputs:surface>
        def Shader "Surface" {
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor = (0.2, 0.3, 0.4)
            float inputs:roughness = 0.6
            float inputs:metallic = 0.25
            token outputs:surface
        }
    }
    variantSet "size" = {
        "small" {
            over "Shape" {
                point3f[] points = [(0,0,0), (1,0,0), (0,1,0)]
            }
        }
        "large" {
            over "Shape" {
                point3f[] points = [(0,0,0), (2,0,0), (0,2,0)]
            }
        }
    }
}
'''
STAGE = '''#usda 1.0
(
    defaultPrim = "World"
    metersPerUnit = 1
    upAxis = "Z"
    startTimeCode = 1
    endTimeCode = 5
    timeCodesPerSecond = 24
)
def Xform "World" {
    def Xform "Placed" (
        prepend references = @base.usda@</Asset>
        variants = { string size = "large" }
    ) {
        double3 xformOp:translate.timeSamples = {1: (0,0,0), 5: (2,0,0)}
        uniform token[] xformOpOrder = ["xformOp:translate"]
    }
}
'''

def must_fail(source, output, message):
    before = (output / 'fixture-assets.atlas').read_bytes()
    try:
        cook.cook(source, output, 'fixture')
    except ValueError as error:
        assert message.lower() in str(error).lower(), str(error)
    else:
        raise AssertionError('Malformed/unsupported USD unexpectedly published')
    assert (output / 'fixture-assets.atlas').read_bytes() == before

(ROOT / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='usd-test-', dir=ROOT / 'build') as temporary:
    root = Path(temporary)
    source, base, output = root / 'scene.usda', root / 'base.usda', root / 'cooked'
    base.write_text(BASE)
    source.write_text(STAGE)
    assert cook.cook(source, output, 'fixture') == 'cooked'
    assert cook.cook(source, output, 'fixture') == 'cached'
    provenance = json.loads((output / 'fixture-source.json').read_text())
    assert str(base) in provenance['dependencies'] and str(source) in provenance['dependencies']
    state = json.loads((output / 'fixture-cook.json').read_text())
    assert str(base) in state['dependencies'] and str(source) in state['dependencies']
    mesh = next(output.glob('fixture-node-*-primitive-0.atlasmesh'))
    vertices = [list(map(float, line.split()[1:])) for line in mesh.read_text().splitlines() if line.startswith('v ')]
    assert max(v[0] for v in vertices) == 2, vertices  # authored variant selection
    material = next(row.split('\t') for row in (output / 'fixture-assets.atlas').read_text().splitlines() if row.startswith('material\t'))
    assert all(abs(float(value) - expected) < 1e-5 for value, expected in zip(material[3:8], [.2, .3, .4, .6, .25])), material
    clips = list(output.glob('fixture-animation-*.atlasclip'))
    assert clips and any('2' in p.read_text() for p in clips)
    tracks = [list(map(float, row.split())) for row in clips[0].read_text().splitlines()[1:]]
    assert any(int(row[2]) == 0 and abs(row[5] - 2.0) < 1e-5 for row in tracks)
    assert '/World/Placed' in (output / 'fixture-assets.atlas').read_text()  # stable USD identity
    generation = state['generation']
    base.write_text(BASE.replace('(2,0,0)', '(3,0,0)'))
    assert cook.cook(source, output, 'fixture') == 'cooked'
    assert json.loads((output / 'fixture-cook.json').read_text())['generation'] != generation
    assert (output / generation).is_dir()  # old readers retain their generation
    source.write_text(STAGE.replace('base.usda', 'missing.usda'))
    must_fail(source, output, 'Unresolved')
    source.write_text(STAGE)
    base.write_text(BASE.replace('subdivisionScheme = "none"', 'subdivisionScheme = "catmullClark"'))
    must_fail(source, output, 'subdivision')
    base.write_text(BASE.replace('UsdPreviewSurface', 'UnknownRendererShader'))
    must_fail(source, output, 'unsupported shader')
    base.write_text(BASE.replace('float inputs:roughness = 0.6', 'float inputs:displacement = 1'))
    must_fail(source, output, 'unsupported Preview Surface input')
    base.write_text(BASE + '\ndef Sphere "Unsupported" {}\n')
    # Reference selects Asset, so unsupported unselected prims do not poison the composed stage.
    assert cook.cook(source, output, 'fixture') in ('cached', 'cooked')
    source.write_text(STAGE + '\ndef Sphere "Unsupported" {}\n')
    must_fail(source, output, 'unsupported type')
    source.write_text(STAGE.replace('base.usda', '../outside.usda'))
    outside = root.parent / 'outside.usda'
    # Do not create an outside file: unresolved references must fail without replacing manifests.
    must_fail(source, output, 'Unresolved')
    base.write_text(BASE)
    source.write_text(STAGE)
    # A nested source can opt into a larger root for legitimate shared references.
    nested = root / 'nested'
    nested.mkdir()
    shared = nested / 'shared.usda'
    shared.write_text(STAGE.replace('base.usda', '../base.usda'))
    must_fail(shared, output, 'outside asset root')
    assert cook.cook(shared, root / 'shared-cooked', 'shared', usd_root=root) == 'cooked'
    # Independent Blender-authored skin and bone motion survive USD -> native Atlas assets.
    rig = root / 'rig.usdc'
    blender = os.environ.get('ATLAS_BLENDER', str(ROOT / '.deps/blender-source/build/bin/blender'))
    result = subprocess.run([blender, '--background', '--factory-startup', '--python-exit-code', '1',
        '--python', str(ROOT / 'tests/usd_rig_fixture.py'), '--', str(rig)], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    rig_output = root / 'rig-cooked'
    assert cook.cook(rig, rig_output, 'rig') == 'cooked'
    assert len(list(rig_output.glob('*.atlasskeleton'))) == 1
    morphs=list(rig_output.glob('*.atlasmorphclip'))
    assert morphs, 'USD blend-shape animation disappeared'
    weights=[float(row.split('\t')[4]) for row in morphs[0].read_text().splitlines()[1:]]
    assert min(weights)<.001 and max(weights)>.999, weights
    skin = next(rig_output.glob('*.atlasskin')).read_text().splitlines()
    assert len(skin[2:]) == 3
    assert all(abs(sum(map(float, row.split()[4:])) - 1) < 1e-6 for row in skin[2:])
    tracks = [list(map(float, row.split())) for row in next(rig_output.glob('*.atlasclip')).read_text().splitlines()[1:]]
    assert any(int(row[2]) == 0 and abs(row[5] - 1) < 1e-5 for row in tracks)
    # No animation is invented for a static variant asset; it is eligible for HLOD cooking.
    assert cook.cook(base, root / 'static', 'static', hlod_distance=100) == 'cooked'
    assert not list((root / 'static').glob('*.atlasclip'))
print('USD integration passed: references, variants, materials, animation, skinning, stable IDs, shared roots, HLOD and failure atomicity')
