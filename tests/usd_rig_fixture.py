"""Author an independent one-bone USD fixture through Blender's USD exporter."""
import sys
from pathlib import Path
import bpy

target = Path(sys.argv[sys.argv.index('--') + 1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.object.armature_add()
rig = bpy.context.object
rig.name = 'Rig'
bpy.ops.object.mode_set(mode='POSE')
bone = rig.pose.bones[0]
bone.location = (0, 0, 0)
bone.keyframe_insert('location', frame=1)
bone.location = (1, 0, 0)
bone.keyframe_insert('location', frame=5)
bpy.ops.object.mode_set(mode='OBJECT')
mesh = bpy.data.meshes.new('Triangle')
mesh.from_pydata([(0,0,0), (1,0,0), (0,0,1)], [], [(0,1,2)])
obj = bpy.data.objects.new('Triangle', mesh)
bpy.context.collection.objects.link(obj)
group = obj.vertex_groups.new(name=rig.data.bones[0].name)
group.add([0,1,2], 1.0, 'REPLACE')
modifier = obj.modifiers.new('Skin', 'ARMATURE')
modifier.object = rig
obj.parent = rig
obj.shape_key_add(name='Basis')
shape=obj.shape_key_add(name='Smile')
for vertex in shape.data:vertex.co.y += .5
shape.value=0
shape.keyframe_insert('value',frame=1)
shape.value=1
shape.keyframe_insert('value',frame=5)
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 5
bpy.ops.wm.usd_export(filepath=str(target), export_animation=True, export_armatures=True)
