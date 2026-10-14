"""Blender worker invoked by cook-usd.py, never by the game runtime."""
import json
import math
from pathlib import Path
import sys
import bpy

arguments = sys.argv[sys.argv.index('--') + 1:]
source, target, report_path = map(Path, arguments[:3])
animated = arguments[3] == '1'
bpy.ops.wm.read_factory_settings(use_empty=True)
result = bpy.ops.wm.usd_import(filepath=str(source), support_scene_instancing=False, import_subdivision=True)
if 'FINISHED' not in result:
    raise RuntimeError('USD import did not finish')
timing=json.loads(arguments[5]) if len(arguments)>5 else None
if timing:
    rate=float(timing['conversion_time_codes_per_second'])
    if not math.isfinite(rate) or rate<=0:raise RuntimeError("Invalid conversion frame rate")
    fps=max(1,min(32767,math.ceil(rate)));base=fps/rate
    if not math.isfinite(rate) or rate<=0 or not .1<=base<=1000:
        raise RuntimeError('Conversion frame rate exceeds Blender clock profile')
    bpy.context.scene.render.fps=fps;bpy.context.scene.render.fps_base=base
    bpy.context.scene.frame_start=round(timing['conversion_start'])
    bpy.context.scene.frame_end=round(timing['conversion_end'])
objects = list(bpy.context.scene.objects)
meshes = [o for o in objects if o.type == 'MESH']
rigs = [o for o in objects if o.type == 'ARMATURE']
if not meshes:
    raise RuntimeError('USD scene contains no imported mesh objects')
if any(o.type not in ('MESH', 'ARMATURE', 'EMPTY', 'CAMERA', 'LIGHT') for o in objects):
    raise RuntimeError('Imported scene has unsupported object types')
# Cameras and lights remain authoring data; make their omission from runtime explicit.
authoring_only = [{'name': o.name, 'type': o.type} for o in objects if o.type in ('CAMERA', 'LIGHT')]
for obj in objects:
    obj['atlas_id'] = obj.get('atlas_id', obj.data.get('atlas_id', obj.name) if obj.data else obj.name)
    if obj.data and obj.data.get('atlas_visibility') is not None:
        obj['atlas_visibility']=obj.data['atlas_visibility']
    if obj.type == 'ARMATURE':
        for bone in obj.data.bones:
            bone['atlas_id'] = obj['atlas_id'] + '/joint/' + bone.name
bakes = json.loads(arguments[4]) if len(arguments) > 4 else []
for bake in bakes:
    matches = [o for o in meshes if o['atlas_id'] == bake.get('identity', bake['path'])]
    if len(matches) != 1:
        raise RuntimeError('Subdivision bake identity did not resolve: ' + bake['path'])
    obj = matches[0]
    modifiers = [m for m in obj.modifiers if m.type == 'SUBSURF']
    if len(modifiers) != 1 or obj.data.shape_keys:
        raise RuntimeError('Expected one static subdivision modifier')
    modifier = modifiers[0]
    modifier.levels = modifier.render_levels = bake['level']
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if 'FINISHED' not in bpy.ops.object.modifier_apply(modifier=modifier.name):
        raise RuntimeError('Subdivision bake failed')
    if len(obj.data.vertices) > 250000 or sum(len(p.vertices) for p in obj.data.polygons) > 750000:
        raise RuntimeError('Subdivision result exceeds geometry budget')
result = bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB',
    export_animations=animated, export_animation_mode='SCENE', export_force_sampling=True,
    export_frame_range=True, export_frame_step=1, export_anim_slide_to_zero=True, export_skins=True,
    export_cameras=False, export_lights=False, export_extras=True,
    export_yup=True)
if 'FINISHED' not in result:
    raise RuntimeError('GLB export did not finish')
report_path.write_text(json.dumps({'blender': bpy.app.version_string,
    'geometry_bakes': bakes, 'mesh_objects': len(meshes), 'armatures': len(rigs), 'authoring_only': authoring_only,
    'frame_start': bpy.context.scene.frame_start, 'frame_end': bpy.context.scene.frame_end,
    'animation_sampling': 'bounded integer conversion grid preserving fractional source keys; scene clips start at zero',
    'conversion_timing': timing, 'fps':bpy.context.scene.render.fps,'fps_base':bpy.context.scene.render.fps_base}, indent=2) + '\n')
