"""Cook a fractional rig and prepare independent USD Skel deformation references."""
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
fixture=module('fractional_fixture',ROOT/'tests/usd_fractional_sampling.py')
fixture.main()
source=ROOT/'build/usd-fractional-rig-source.usda';output=ROOT/'build/usd-fractional-cooked'
cook=module('fractional_cook',ROOT/'scripts/cook-assets.py');started=time.monotonic()
cook.cook(source,output,'preview')
provenance=json.loads((output/'preview-source.json').read_text());timing=provenance['conversion']['conversion_timing']
assert timing['conversion_grid_factor']==4 and provenance['conversion']['fps']==96
manifest=(output/'preview-playback.atlasplayback').read_text();assert all('\n'+kind+'\t' in manifest for kind in ('skin','clip','weights'))
times={float(line.split()[4]) for clip in output.glob('*.atlasclip') for line in clip.read_text().splitlines()[1:]}
for source_time in [0,1.25,3.5,5]:assert min(abs(t-source_time/24) for t in times)<1e-7
weight_files=list(output.glob('*.atlasmorphclip'));assert len(weight_files)==1
weights=[line.split('\t') for line in weight_files[0].read_text().splitlines()[1:]]
for source_time,expected in [(1.25,.75),(3.5,.25),(5,1)]:
    record=min(weights,key=lambda r:abs(float(r[3])-source_time/24))
    assert abs(float(record[3])-source_time/24)<1e-7 and abs(float(record[4])-expected)<1e-6,record
rows=['ATLAS_USD_FRACTIONAL_POSE_1']
for timecode in [0,.625,1.25,2.25,3.5,4.5,5]:
    data=json.loads(subprocess.check_output([str(ROOT/'build/usd-pose-oracle'),str(source),str(timecode)],text=True))[0]
    rows.append('\t'.join(format(v,'.17g') for v in [timecode/24,*data['joint_matrices'][0],data['weights'][0]]))
(ROOT/'build/usd-fractional-reference.tsv').write_text('\n'.join(rows)+'\n')
report={'passed':True,'source_time_codes_per_second':24,'conversion_grid_factor':4,'converted_fps':96,
        'fractional_key_seconds':[1.25/24,3.5/24],'sampled_reference_poses':7,'cook_seconds':time.monotonic()-started,
        'scope':'Real Blender USD import and GLB export; cooked skin/morph/camera data; references use independent native USD Skel evaluation'}
(ROOT/'build/usd-fractional-playback.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
