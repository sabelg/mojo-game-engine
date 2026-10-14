"""Independent glTF morph/pose channels, interpolation and publication failures."""
import importlib.util,json,struct,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('cook',ROOT/'scripts/cook-assets.py');cook=importlib.util.module_from_spec(spec);spec.loader.exec_module(cook)
work=ROOT/'build/morph-test';work.mkdir(parents=True,exist_ok=True)
buf=bytearray();views=[];accessors=[]
def accessor(rows,width):
 offset=len(buf)
 for row in rows:buf.extend(struct.pack('<'+'f'*width,*row))
 views.append({'buffer':0,'byteOffset':offset,'byteLength':len(buf)-offset})
 accessors.append({'bufferView':len(views)-1,'componentType':5126,'count':len(rows),'type':{1:'SCALAR',3:'VEC3'}[width]})
 return len(accessors)-1
pos=accessor([[0,0,0],[1,0,0],[0,1,0]],3)
delta=accessor([[2,0,0]]*3,3)
times=accessor([[0],[2]],1)
linear=accessor([[0],[1]],1)
cubic=accessor([[0],[0],[2],[0],[1],[0]],1)
trs=accessor([[0,0,0],[0,2,0]],3)
doc={'asset':{'version':'2.0'},'buffers':[{'uri':'input.bin','byteLength':len(buf)}],'bufferViews':views,'accessors':accessors,
 'nodes':[{'mesh':0,'extras':{'atlas_id':'face'}}], 'meshes':[{'primitives':[{'attributes':{'POSITION':pos},'targets':[{'POSITION':delta}]}]}],
 'animations':[{'samplers':[{'input':times,'output':linear,'interpolation':'LINEAR'},{'input':times,'output':trs}],
 'channels':[{'sampler':0,'target':{'node':0,'path':'weights'}},{'sampler':1,'target':{'node':0,'path':'translation'}}]}]}
(work/'input.bin').write_bytes(buf);source=work/'input.gltf'
for mode in ['LINEAR','STEP','CUBICSPLINE']:
 fixture=copy.deepcopy(doc);fixture['animations'][0]['samplers'][0].update(interpolation=mode,output=cubic if mode=='CUBICSPLINE' else linear)
 source.write_text(json.dumps(fixture));cook.cook(source,work/mode,'face')
 rows=(work/mode/'face-animation-0.atlasclip').read_text().splitlines();assert rows[1].split()[0]=='0','TRS indices must remain dense after morph channel'
 rows=(work/mode/'face-animation-0.atlasmorphclip').read_text().splitlines();assert len(rows)==3 and 'face' in rows[1]
# Invalid output and duplicated channels must not replace a published generation.
source.write_text(json.dumps(doc));cook.cook(source,work/'safe','face');before=(work/'safe/face-cook.json').read_bytes()
for invalid in ['output','duplicate']:
 fixture=copy.deepcopy(doc)
 if invalid=='output':fixture['animations'][0]['samplers'][0]['output']=trs
 else:fixture['animations'][0]['channels'].append(copy.deepcopy(fixture['animations'][0]['channels'][0]))
 source.write_text(json.dumps(fixture))
 try:cook.cook(source,work/'safe','face')
 except ValueError:pass
 else:raise AssertionError('Accepted invalid '+invalid)
 assert before==(work/'safe/face-cook.json').read_bytes()
for name,body in {'order':'mesh\t0\t1\t1\t0\nmesh\t0\t1\t0\t1\n','nan':'mesh\t0\t1\t0\tnan\n','width':'mesh\t0\t2\t0\t1\n','cubic':'mesh\t2\t1\t0\t0\t0\t0\n'}.items():
 (work/(name+'.atlasmorphclip')).write_text('ATLAS_MORPH_CLIP_1\n'+body)
print('Morph cooking passed: three interpolation modes, mixed TRS, failure atomicity')
