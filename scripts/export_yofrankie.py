"""Run with Blender 2.79: original BGE data -> versioned Mojo assets.
Media attribution: YoFrankie! (c) 2008, Blender Foundation, www.blender.org.
Exporter is original code; no changes are written to upstream .blend files.
"""
import bpy, os, sys, json, struct, math, hashlib, subprocess
from mathutils import Matrix, Vector
ROOT=os.path.abspath('third_party/yofrankie')
OUT=os.path.abspath('assets/yofrankie')
os.makedirs(OUT, exist_ok=True)
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
IDENT=Matrix.Identity(4)
TEXTURES={}
MISSING=set()
def props(o): return {p.name:p.value for p in o.game.properties}
def vec(v): return ' '.join('%.6g'%x for x in v)
def safe(s): return ''.join(c if c.isalnum() or c in '_-' else '_' for c in s)
def binary(path, vertices):
    with open(path,'wb') as f:
        f.write(struct.pack('<II',0x314d4659,len(vertices)))
        for v in vertices: f.write(struct.pack('<8f',*v))
def texture(img):
    if not img: return '-'
    source=bpy.path.abspath(img.filepath, library=img.library)
    if source in TEXTURES:return TEXTURES[source]
    if not os.path.isfile(source):
        source=os.path.join(ROOT,'textures',os.path.basename(img.filepath))
    if not os.path.isfile(source):
        if source not in MISSING:print('MISSING_TEXTURE',img.name,source,flush=True)
        MISSING.add(source)
        return '-'
    name=safe(os.path.basename(source))+'.bmp'
    path=os.path.join(OUT,name)
    if not os.path.exists(path):
        subprocess.check_call(['magick',source,'-resize','4096x4096>','BMP:'+path])
    TEXTURES[source]=name
    return name

def geom(o, transform, scene, batches, collision=None, hazards=None):
    if o.type != 'MESH': return
    p=props(o)
    mesh=o.to_mesh(scene,True,'PREVIEW')
    mesh.calc_tessface(); mesh.calc_normals_split()
    world=C*transform
    normal=world.to_3x3().inverted_safe().transposed()
    uv=mesh.tessface_uv_textures.active
    skip=o.hide_render or any(x in o.name.lower() for x in ['shadow','null_mesh','slowvert','bounce']) or o.name=='Frankie'
    for face in mesh.tessfaces:
        pts=[world*mesh.vertices[i].co for i in face.vertices]
        tri=[(0,1,2)] if len(pts)==3 else [(0,1,2),(0,2,3)]
        if hazards is not None and any(k in p for k in ['water','liquid','kill']):
            for ids in tri:hazards.append([pts[i][:] for i in ids])
        if collision is not None and o.game.physics_type not in ['NO_COLLISION','SENSOR'] and not any(k in p for k in ['portal','water','liquid','kill','pickup','projectile']):
            for ids in tri: collision.append([pts[i][:] for i in ids])
        if skip: continue
        img=uv.data[face.index].image if uv else None
        mat=mesh.materials[face.material_index] if face.material_index<len(mesh.materials) else None
        color=(1,1,1) if img else tuple(mat.diffuse_color) if mat else (.6,.6,.6)
        if 'water' in p:
            img=None; color=(0.08,0.3,0.42)
        tex=texture(img)
        key=(tex,color)
        arr=batches.setdefault(key,[])
        coords=uv.data[face.index].uv if uv else [(0,0)]*4
        for ids in tri:
            for i in ids:
                n=normal*(mesh.vertices[face.vertices[i]].normal if face.use_smooth else face.normal); n.normalize()
                arr.append(tuple(pts[i])+tuple(n)+(coords[i][0],1-coords[i][1]))
    bpy.data.meshes.remove(mesh)

def write_batches(prefix,batches):
    lines=[]
    for i,((tex,color),vertices) in enumerate(sorted(batches.items())):
        if not vertices: continue
        name=prefix+'_'+str(i)+'.yfm'; binary(os.path.join(OUT,name),vertices)
        lines.append(name+'\t'+tex+'\t'+vec(color))
    return lines

def kind(name):
    for prefix,k in [('FlyingSquirrel','player'),('MomoMonkey','momo'),('acorn','acorn'),('apricot','apricot'),('bone','bone'),('boost','boost'),('springbox','spring'),('sheep_cute','sheep'),('sheep_ram','ram'),('ram','ram'),('rat','rat')]:
        if name.startswith(prefix): return k
    return ''

def export_level(filepath):
    bpy.ops.wm.open_mainfile(filepath=filepath)
    basename=os.path.basename(filepath)[:-6]
    rows=[]
    for scene in bpy.data.scenes:
        if scene.name.lower() in ['hud','help','credits']: continue
        bpy.context.screen.scene=scene
        scene.frame_set(1); scene.update()
        key=basename+'__'+safe(scene.name)
        batches={}; collision=[]; hazards=[]; entities=[]; records=[]; spawn=None; markers=[]; triggers=[]
        def visit(o, mat, depth=0):
            nonlocal spawn
            if depth>5:return
            p=props(o); name=o.name; pos=C*mat.translation
            if depth==0:
                markers.append(name+'\t'+vec(pos))
                if 'portal' in p or 'water' in p or 'kill' in p or 'liquid' in p:
                    bounds=[C*(mat*Vector(v)) for v in o.bound_box]
                    lo=[min(v[i] for v in bounds) for i in range(3)];hi=[max(v[i] for v in bounds) for i in range(3)]
                    triggers.append(('portal' if 'portal' in p else 'hazard')+'\t'+vec(lo)+'\t'+vec(hi)+'\t'+str(p.get('portal_blend','')).replace('//','').replace('.blend','')+'\t'+str(p.get('portal_scene',''))+'\t'+str(p.get('portal','')))
                if p: records.append({'name':name,'properties':p,'position':list(pos)})
            group=o.dupli_group
            k=kind(group.name if group else name)
            if k=='player':
                if spawn is None:spawn=pos[:]
                return
            if k=='momo':return
            if group and k:
                prefab=safe(group.name)
                pref=os.path.join(OUT,prefab+'.parts')
                if not os.path.exists(pref):
                    parts={}
                    for child in group.objects: geom(child,Matrix.Translation(-group.dupli_offset)*child.matrix_world,scene,parts)
                    open(pref,'w').write('\n'.join(write_batches(prefab,parts))+'\n')
                angle=-mat.to_euler().z
                entities.append(k+'\t'+prefab+'\t'+vec(pos)+'\t'+str(angle)+'\t'+vec(mat.to_scale()))
                return
            if group:
                for child in group.objects:visit(child,mat*Matrix.Translation(-group.dupli_offset)*child.matrix_world,depth+1)
            else:geom(o,mat,scene,batches,collision,hazards)
        for o in scene.objects:
            if any(a and b for a,b in zip(o.layers,scene.layers)):visit(o,o.matrix_world)
        if not batches:continue
        if spawn is None:spawn=(0,3,0)
        open(os.path.join(OUT,key+'.parts'),'w').write('\n'.join(write_batches(key,batches))+'\n')
        with open(os.path.join(OUT,key+'.collision'),'w') as f:
            for tri in collision:f.write(' '.join(vec(p) for p in tri)+'\n')
        with open(os.path.join(OUT,key+'.hazards'),'w') as f:
            for tri in hazards:f.write(' '.join(vec(p) for p in tri)+'\n')
        open(os.path.join(OUT,key+'.entities'),'w').write('\n'.join(entities)+'\n')
        open(os.path.join(OUT,key+'.markers'),'w').write('\n'.join(markers)+'\n')
        open(os.path.join(OUT,key+'.triggers'),'w').write('\n'.join(triggers)+'\n')
        open(os.path.join(OUT,key+'.json'),'w').write(json.dumps(records,indent=2))
        rows.append(key+'\t'+basename+'\t'+scene.name+'\t'+vec(spawn))
        print('EXPORTED',key,len(collision),len(entities),len(batches),flush=True)
    return rows

def smooth_character(mesh):
    # One subdivision level rounds the authored silhouette and preserves UVs.
    # Evaluate after the original armature, independently for every baked pose.
    modifier=mesh.modifiers.get('Remaster surface')
    if modifier is None:modifier=mesh.modifiers.new('Remaster surface','SUBSURF')
    modifier.levels=1
    modifier.render_levels=1
    modifier.subdivision_type='CATMULL_CLARK'


def animation():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'chars/frankie.blend'))
    scene=bpy.context.scene
    mesh=bpy.data.objects['MeshFrankie'];rig=bpy.data.objects['RigFrankie']
    smooth_character(mesh)
    # Use the authored mesh local to the player's root, preserving its scale.
    player=bpy.data.objects['Frankie'];base=player.matrix_world.inverted()
    rig.animation_data_create()
    for key,action in [('idle','Frankie_Idle1'),('run','Frankie_Run'),('jump','Frankie_Jump'),('double','Frankie_dj'),('glide','Frankie_Glide'),('fall','Frankie_Falling'),('kick','Frankie_Kick'),('whip','Frankie_TailWhip'),('carry','Frankie_Carry'),('throw','Frankie_Throw1'),('hurt','Frankie_HitWalk'),('ledge','Frankie_EdgeIdle')]:
        a=bpy.data.actions.get(action)
        if not a:raise RuntimeError('Missing original animation '+action)
        rig.animation_data.action=a
        for i in range(12):
            frame=a.frame_range[0]+(a.frame_range[1]-a.frame_range[0])*i/12
            scene.frame_set(int(frame),frame-int(frame));scene.update()
            batches={};geom(mesh,base*mesh.matrix_world,scene,batches)
            prefix='frankie_'+key+'_'+str(i)
            open(os.path.join(OUT,prefix+'.parts'),'w').write('\n'.join(write_batches(prefix,batches))+'\n')
        print('ANIMATION',key,flush=True)

def enemies():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'chars/sheep.blend'))
    scene=bpy.context.scene
    # BGE hide-far-away object IPOs are state-machine effects, not skeletal clips.
    # Disable those object tracks before sampling armature actions.
    for obj in bpy.data.objects:
        if obj.type!='ARMATURE':obj.animation_data_clear()
    scene.frame_set(1);scene.update()
    mapping={'sheep_cute':('sheepcute_graze','sheepcute_run','sheepcute_hit'), 'ram':('ram_idle_grazing','ram_run','ram_kicked'), 'rat':('rat_idle','rat_run','rat_beinghit')}
    for name,actions in mapping.items():
        group=bpy.data.groups[name]
        rigs=[o for o in group.objects if o.type=='ARMATURE']
        for mesh in group.objects:
            if mesh.type=='MESH' and any(m.type=='ARMATURE' for m in mesh.modifiers):smooth_character(mesh)
        for state,action in zip(('idle','run','hurt'),actions):
            a=bpy.data.actions[action]
            for rig in rigs:
                rig.animation_data_create();rig.animation_data.action=a
            for i in range(8):
                frame=a.frame_range[0]+(a.frame_range[1]-a.frame_range[0])*i/8
                scene.frame_set(int(frame),frame-int(frame));scene.update()
                batches={}
                for mesh in group.objects:geom(mesh,Matrix.Translation(-group.dupli_offset)*mesh.matrix_world,scene,batches)
                prefix=name+'_'+state+'_'+str(i)
                open(os.path.join(OUT,prefix+'.parts'),'w').write('\n'.join(write_batches(prefix,batches))+'\n')
            print('ENEMY_ANIMATION',name,state,flush=True)

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
if args and args[0]=='animation':animation()
elif args and args[0]=='enemies':enemies()
else:
    files=sorted(f for f in os.listdir(os.path.join(ROOT,'levels')) if f.endswith('.blend') and (f.startswith('level_') or f.startswith('minilevel_')))
    if args:files=args
    rows=[]
    for f in files:rows+=export_level(os.path.join(ROOT,'levels',f))
    open(os.path.join(OUT,'levels.tsv'),'w').write('\n'.join(rows)+'\n')

if not args:open(os.path.join(OUT,"missing-textures.json"),"w").write(json.dumps(sorted(os.path.relpath(p,ROOT) for p in MISSING),indent=2))
