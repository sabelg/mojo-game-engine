"""Blender 5 authoring pipeline for a procedural realism pass of all runtime art.

Uses the legacy converter's animation/level bridge, never opens old BGE files.
Original media: YoFrankie! (c) 2008 Blender Foundation, CC-BY 3.0.
Generated art is derivative of that media, not a newly sculpted character set.
Run via scripts/remake-frankie.sh. Source originals are never overwritten.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import sys

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/yofrankie'
OUT = ROOT / 'assets/yofrankie-realistic'
AUTHOR = ROOT / 'art/frankie-realistic'


def seed(name):
    return int.from_bytes(hashlib.sha256(name.encode()).digest()[:4], 'little')


def noise(w, h, frequency, rng):
    """Periodic smooth value noise: repeat-safe on the original tiling UVs."""
    grid = rng.random((frequency, frequency), dtype=np.float32)
    x = np.arange(w, dtype=np.float32) * frequency / w
    y = np.arange(h, dtype=np.float32) * frequency / h
    xi, yi = x.astype(int), y.astype(int)
    xf, yf = x - xi, y - yi
    xf, yf = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    a = grid[yi[:, None], xi] * (1 - xf) + grid[yi[:, None], (xi + 1) % frequency] * xf
    b = grid[(yi[:, None] + 1) % frequency, xi] * (1 - xf) + grid[(yi[:, None] + 1) % frequency, (xi + 1) % frequency] * xf
    return a * (1 - yf[:, None]) + b * yf[:, None]


def bmp(path, rgba):
    """Uncompressed BMP v4, explicit alpha mask; supported by SDL and Blender."""
    h, w = rgba.shape[:2]
    pixels = (np.clip(rgba, 0, 1) * 255 + .5).astype(np.uint8)
    payload = pixels[:, :, [2, 1, 0, 3]].tobytes()  # input bottom-up, as in Blender
    header = struct.pack('<IiiHHIIiiII', 108, w, h, 1, 32, 3, len(payload), 2835, 2835, 0, 0)
    header += struct.pack('<IIIII', 0xff0000, 0xff00, 0xff, 0xff000000, 0x73524742)
    header += bytes(48)
    path.write_bytes(struct.pack('<2sIHHI', b'BM', 122 + len(payload), 0, 0, 122) + header + payload)


def family(name):
    name = name.lower()
    if name.startswith(('sign_', 'sky', 'font_', 'fx_spark', 'fx_splash', 'slideshow', 'x_', 'rabbithole', 'watermap')):
        return 'preserved_graphic'
    if 'lava' in name: return 'lava'
    if any(x in name for x in ('skin', 'char_', 'rat_col', 'tail')): return 'fur'
    if any(x in name for x in ('bark', 'stump', 'log')): return 'bark'
    if any(x in name for x in ('rock', 'stone')): return 'stone'
    if 'generic_grass' in name: return 'grass'
    if 'dirt' in name: return 'soil'
    if any(x in name for x in ('leaves', 'plants', 'furn')): return 'foliage'
    if any(x in name for x in ('bridge', 'fence', 'home', 'phare')): return 'weathered_atlas'
    return 'prop_atlas'


def read_pixels(path, size):
    image = bpy.data.images.load(str(path), check_existing=False)
    image.colorspace_settings.name = 'Non-Color'
    w, h = image.size[:]
    # Authored atlas colors stay at native resolution; procedural detail fills
    # larger maps only when explicitly requested. This is not recovered detail.
    factor = min(1.0, size / max(w, h))
    w, h = max(16, int(w * factor)), max(16, int(h * factor))
    if tuple(image.size) != (w, h): image.scale(w, h)
    pixels = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(h, w, 4)


def generate_materials(size):
    rows, report = [], []
    for line in (SOURCE / 'materials.tsv').read_text().splitlines():
        name, old_normal, rough, metal, emission = line.split('\t')
        kind = family(name)
        src = read_pixels(SOURCE / name, size)
        h, w = src.shape[:2]
        rng = np.random.default_rng(seed(name))
        broad = noise(w, h, 8, rng)
        medium = noise(w, h, 32, rng)
        fine = noise(w, h, 128, rng)
        grain = rng.random((h, w), dtype=np.float32)
        height = .5 * broad + .3 * medium + .15 * fine + .05 * grain
        result = src.copy()
        roughness = np.full((h, w), float(rough))
        occlusion = np.ones((h, w))
        metallic = np.full((h, w), float(metal))
        treatment = 'preserved authored graphic'
        if kind in ('stone', 'soil', 'grass', 'bark'):
            palettes = {
                'stone': ((.28, .32, .37), (.60, .65, .67)),
                'soil': ((.24, .13, .065), (.49, .32, .16)),
                'grass': ((.13, .24, .035), (.34, .48, .08)),
                'bark': ((.23, .115, .045), (.54, .32, .14)),
            }
            lo, hi = map(np.array, palettes[kind])
            if 'redrock' in name.lower(): lo, hi = np.array((.20, .10, .065)), np.array((.47, .29, .19))
            if 'darkrock' in name.lower() or 'black' in name.lower(): lo *= .55; hi *= .60
            if kind == 'bark':
                u = np.arange(w)[None, :] / w
                grooves = (.5 + .5 * np.sin(2 * np.pi * (u * 37 + broad * 2))) ** 9
                height = height * .65 - grooves * .25
            if kind == 'grass':
                u = np.arange(w)[None, :] / w
                fibers = .5 + .5 * np.sin(2 * np.pi * (u * 170 + broad * 3))
                height += fibers * .07
            blend = np.clip(height, 0, 1)[..., None]
            natural = lo * (1 - blend) + hi * blend
            # Pure tile materials are reauthored; prop atlases retain their UV masks.
            tiled = name.lower().startswith(('generic_', 'stone_cliff', 'trees_bark'))
            if tiled: result[..., :3] = natural * (.85 + fine[..., None] * .3)
            else: result[..., :3] = src[..., :3] * (.67 + height[..., None] * .48)
            roughness = np.clip(.62 + height * .20, .50, .94)
            occlusion = np.clip(.86 + height * .14, 0, 1)
            treatment = 'new procedural tile' if tiled else 'authored atlas with procedural surface detail'
        elif kind != 'preserved_graphic':
            gray = src[..., :3].mean(axis=2, keepdims=True)
            saturation = 1.15 if kind == 'foliage' else 1.02
            result[..., :3] = (gray + (src[..., :3] - gray) * saturation) * (.98 + height[..., None] * .13)
            roughness = np.clip(float(rough) + (height - .5) * .24, .12, .98)
            if kind == 'fur':
                u = np.arange(w)[None, :] / w
                fibers = (.5 + .5 * np.sin(2 * np.pi * (u * 210 + broad * 1.5))) ** 3
                height = .15 * medium + .08 * fibers + .02 * grain
                result[..., :3] *= .92 + fibers[..., None] * .14
                roughness[:] = .86
                if 'tail' in name.lower():
                    # The legacy shell texture contains bright stochastic dots.
                    # Retain its alpha silhouette but author continuous warm fur
                    # color, avoiding a white stipple patch at gameplay distance.
                    result[..., :3] = np.array((.42,.235,.105)) * (.83 + medium[...,None]*.25 + fibers[...,None]*.08)
                    roughness[:] = .94
            if kind == 'lava':
                crust = np.clip((broad - .43) * 6, 0, 1)
                result[..., :3] = np.array((1., .22, .012)) * (1 - crust[..., None]) + np.array((.12, .065, .045)) * crust[..., None]
                roughness = .25 + crust * .65
            treatment = 'authored atlas with procedural surface detail'
        # Tangent-space OpenGL normals derived from the periodic height field.
        dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .75
        dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .75
        normals = np.stack((-dx, -dy, np.ones_like(dx)), axis=2)
        if old_normal != '-' and kind not in ('stone', 'soil', 'grass', 'bark'):
            original = read_pixels(SOURCE / old_normal, size)[..., :3] * 2 - 1
            if original.shape == normals.shape:
                normals[..., :2] += original[..., :2] * .45
        if kind == 'preserved_graphic': normals[:] = (0, 0, 1)
        normals /= np.linalg.norm(normals, axis=2, keepdims=True)
        normal_name, orm_name = name[:-4] + '_detail.bmp', name[:-4] + '_orm.bmp'
        bmp(OUT / name, result)
        bmp(OUT / normal_name, np.dstack((normals * .5 + .5, np.ones((h, w)))))
        bmp(OUT / orm_name, np.dstack((occlusion, roughness, metallic, np.ones((h, w)))))
        rows.append('\t'.join((name, normal_name, rough, metal, emission, orm_name)))
        report.append(dict(albedo=name, family=kind, treatment=treatment, width=w, height=h,
                           source_sha256=hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()))
        print('MATERIAL', name, kind, flush=True)
    # Compact grass material shared by new geometric ground cover in every scene.
    w = h = 128
    v = np.arange(h)[:, None] / (h - 1)
    blade = np.ones((h, w, 4), dtype=np.float32)
    blade[..., :3] = np.array((.16, .30, .04)) + v[..., None] * np.array((.25, .29, .055))
    bmp(OUT / 'detail_meadow.bmp', blade)
    blade[..., :3] = (.5, .5, 1)
    bmp(OUT / 'detail_meadow_normal.bmp', blade)
    blade[..., :3] = (1, .91, 0)
    bmp(OUT / 'detail_meadow_orm.bmp', blade)
    rows.append('detail_meadow.bmp\tdetail_meadow_normal.bmp\t0.91\t0\t0\tdetail_meadow_orm.bmp')
    # Shared opaque atlas for newly modeled foliage and flowers. Geometry defines
    # silhouettes, so no coarse alpha cards or painted lighting are necessary.
    palette = ((.08,.38,.16),(.40,.67,.08),(.04,.43,.38),(1,.64,.07),
               (.96,.25,.17),(.55,.25,.82),(1,.91,.60),(.32,.15,.065))
    atlas = np.ones((128,512,4),dtype=np.float32)
    for i, color in enumerate(palette):
        atlas[:,i*64:(i+1)*64,:3] = np.array(color) * (.82 + .18 * np.arange(128)[:,None,None]/127)
    bmp(OUT/'detail_garden.bmp',atlas)
    atlas[:,:,:3] = (.5,.5,1); bmp(OUT/'detail_garden_normal.bmp',atlas)
    atlas[:,:,:3] = (1,.72,0); bmp(OUT/'detail_garden_orm.bmp',atlas)
    rows.append('detail_garden.bmp\tdetail_garden_normal.bmp\t0.72\t0\t0\tdetail_garden_orm.bmp')
    (OUT / 'materials.tsv').write_text('\n'.join(rows) + '\n')
    return report


def materials():
    result = {}
    for line in (OUT / 'materials.tsv').read_text().splitlines():
        albedo, normal, roughness, metallic, emission, orm = line.split('\t')
        mat = bpy.data.materials.new(albedo)
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        bsdf = nodes.get('Principled BSDF')
        bsdf.inputs['Emission Strength'].default_value = float(emission)
        for i, (name, linear) in enumerate(((albedo, False), (normal, True), (orm, True))):
            node = nodes.new('ShaderNodeTexImage')
            node.image = bpy.data.images.load(str(OUT / name), check_existing=True)
            node.image.colorspace_settings.name = 'Non-Color' if linear else 'sRGB'
            node.location = (-650, 300 - i * 280)
            if i == 0:
                links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
                links.new(node.outputs['Alpha'], bsdf.inputs['Alpha'])
                links.new(node.outputs['Color'], bsdf.inputs['Emission Color'])
            elif i == 1:
                normal_node = nodes.new('ShaderNodeNormalMap')
                normal_node.location = (-270, 0)
                links.new(node.outputs['Color'], normal_node.inputs['Color'])
                links.new(normal_node.outputs['Normal'], bsdf.inputs['Normal'])
            else:
                split = nodes.new('ShaderNodeSeparateColor')
                split.location = (-270, -240)
                links.new(node.outputs['Color'], split.inputs['Color'])
                links.new(split.outputs['Green'], bsdf.inputs['Roughness'])
                links.new(split.outputs['Blue'], bsdf.inputs['Metallic'])
        mat['runtime_albedo'] = albedo
        mat['provenance'] = 'Procedural derivative of YoFrankie! 2008 Blender Foundation / CC-BY 3.0'
        mat.asset_mark()
        result[albedo] = mat
    return result


def engine_to_blender(values):
    return values[:, [0, 2, 1]] * np.array((1, -1, 1), dtype=np.float32)


def import_mesh(name, collection, material, color):
    source = SOURCE / name
    data = (source if source.exists() else OUT / name).read_bytes()
    magic, count = struct.unpack_from('<II', data)
    if magic != 0x314d4659 or len(data) != 8 + count * 32: raise ValueError(name)
    a = np.frombuffer(data, dtype='<f4', offset=8).reshape(-1, 8).copy()
    # Degenerate legacy triangles can crash Blender's custom-normal builder
    # after welding vertices. They have no visible area; remove before import.
    triangles = a.reshape(-1, 3, 8)
    areas = np.linalg.norm(np.cross(triangles[:, 1, :3] - triangles[:, 0, :3], triangles[:, 2, :3] - triangles[:, 0, :3]), axis=1)
    a = triangles[areas >= 1e-10].reshape(-1, 8)
    if not len(a): raise ValueError('Entirely degenerate mesh: ' + name)
    # Legacy ground often uses a tiny patch of an atlas. Reauthor tile UVs in
    # world metres, otherwise even a detailed material becomes a blurry swatch.
    texture = material.get('runtime_albedo', '') if material else ''
    if name.startswith(('level_', 'minilevel_')) and texture.startswith(('generic_', 'stone_cliff')) and family(texture) in ('stone', 'grass', 'soil'):
        triangles = a.reshape(-1, 3, 8)
        dominant = np.argmax(np.abs(triangles[:, :, 3:6].mean(axis=1)), axis=1)
        for axis, pair in ((0, (2, 1)), (1, (0, 2)), (2, (0, 1))):
            selected = dominant == axis
            coords = triangles[selected][:, :, list(pair)]
            triangles[selected, :, 6:8] = coords / (1.8 if family(texture) == 'stone' else 1.2)
    positions, indices = np.unique(engine_to_blender(a[:, :3]), axis=0, return_inverse=True)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(positions.tolist(), [], indices.reshape(-1, 3).tolist())
    mesh.update()
    uv = mesh.uv_layers.new(name='UVMap')
    coords = a[:, 6:8].copy(); coords[:, 1] = 1 - coords[:, 1]
    uv.data.foreach_set('uv', coords.ravel())
    mesh.polygons.foreach_set('use_smooth', [True] * len(mesh.polygons))
    mesh.normals_split_custom_set(engine_to_blender(a[:, 3:6]).tolist())
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    if material:
        mesh.materials.append(material)
    else:
        mat = bpy.data.materials.get('Solid ' + color)
        if mat is None:
            mat = bpy.data.materials.new('Solid ' + color)
            mat.diffuse_color = (*map(float, color.split()), 1)
            mat.use_nodes = True
            mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = mat.diffuse_color
        mesh.materials.append(mat)
    obj['source_mesh'] = name
    obj['runtime_color'] = color
    return obj, a


def export_mesh(obj, name, transform=None, mesh=None):
    if mesh is None: mesh = obj.data
    mesh.calc_loop_triangles()
    loops = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int32)
    mesh.loop_triangles.foreach_get('loops', loops)
    vertices = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get('vertex_index', vertices)
    positions = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get('co', positions)
    normals = np.empty(len(mesh.corner_normals) * 3, dtype=np.float32)
    mesh.corner_normals.foreach_get('vector', normals)
    coords = np.empty(len(mesh.loops) * 2, dtype=np.float32)
    mesh.uv_layers.active.data.foreach_get('uv', coords)
    a = np.empty((len(loops), 8), dtype='<f4')
    a[:, :3] = positions.reshape(-1, 3)[vertices[loops]][:, [0, 2, 1]] * (1, 1, -1)
    a[:, 3:6] = normals.reshape(-1, 3)[loops][:, [0, 2, 1]] * (1, 1, -1)
    a[:, 6:8] = coords.reshape(-1, 2)[loops]; a[:, 7] = 1 - a[:, 7]
    if transform is not None:
        # Apply edits in Blender space before converting back to engine Y-up.
        p = engine_to_blender(a[:, :3])
        n = engine_to_blender(a[:, 3:6])
        matrix = np.array(transform, dtype=np.float32)
        p = p @ matrix[:3, :3].T + matrix[:3, 3]
        n = n @ np.linalg.inv(matrix[:3, :3])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-8)
        a[:, :3] = p[:, [0, 2, 1]] * (1, 1, -1)
        a[:, 3:6] = n[:, [0, 2, 1]] * (1, 1, -1)
        if np.linalg.det(matrix[:3, :3]) < 0:
            a = a.reshape(-1, 3, 8)[:, [0, 2, 1], :].reshape(-1, 8)
    (OUT / name).write_bytes(struct.pack('<II', 0x314d4659, len(a)) + a.tobytes())
    return len(a) // 3


def ground_cover(key, surfaces, collection, material, budget):
    """Small non-colliding grass blades only on authored grassy upward surfaces."""
    if not surfaces: return None, 0
    triangles = np.concatenate(surfaces).reshape(-1, 3, 8)[:, :, :3]
    cross = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    area = np.linalg.norm(cross, axis=1) * .5
    usable = (cross[:, 1] > area * 1.3) & (area > .005)
    triangles, area = triangles[usable], area[usable]
    if not len(area): return None, 0
    rng = np.random.default_rng(seed(key))
    count = min(budget, int(area.sum() * 7))
    if not count: return None, 0
    choices = rng.choice(len(area), count, p=area / area.sum())
    vertices, faces, uvs = [], [], []
    for tri in triangles[choices]:
        a, b = rng.random(2)
        if a + b > 1: a, b = 1 - a, 1 - b
        p = tri[0] + a * (tri[1] - tri[0]) + b * (tri[2] - tri[0])
        for angle in rng.random(3) * math.tau:
            length = rng.uniform(.07, .22)
            side = np.array((math.cos(angle), 0, math.sin(angle))) * .018
            tip = p + np.array((math.sin(angle) * .04, length, math.cos(angle) * .04))
            start = len(vertices)
            vertices.extend(engine_to_blender(np.array((p - side, p + side, tip))).tolist())
            faces.append((start, start + 1, start + 2))
            uvs.extend(((0, 0), (1, 0), (.5, 1)))
    mesh = bpy.data.meshes.new(key + '_ground_cover')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.uv_layers.new().data.foreach_set('uv', np.array(uvs).ravel())
    mesh.materials.append(material)
    mesh.polygons.foreach_set('use_smooth', [True] * len(mesh.polygons))
    mesh.normals_split_custom_set([(0,0,1)] * len(mesh.loops))
    obj = bpy.data.objects.new(mesh.name, mesh)
    collection.objects.link(obj)
    obj['non_colliding_detail'] = True
    filename = key + '_ground_cover.yfm'
    export_mesh(obj, filename)
    return filename, len(faces)


def fur_detail(source, vertices, collection, material):
    """Short tapered surface fibers sampled consistently on every baked pose."""
    if material is None or family(material['runtime_albedo']) != 'fur': return None, 0
    triangles = vertices.reshape(-1, 3, 8)
    count = min(900, len(triangles) // 3)
    if not count: return None, 0
    # Pose-independent random barycentrics/triangle ids keep fibers attached
    # rather than randomly respawning as the animation advances.
    rng = np.random.default_rng(7341)
    indices = rng.integers(0, len(triangles), count)
    weights = rng.dirichlet((1, 1, 1), count)
    samples = np.sum(triangles[indices] * weights[:, :, None], axis=1)
    normals = samples[:, 3:6]
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-8)
    tangent = np.cross(normals, np.array((0, 1, .13)))
    tangent /= np.maximum(np.linalg.norm(tangent, axis=1, keepdims=True), 1e-8)
    length = rng.uniform(.004, .010, (count, 1))
    width = rng.uniform(.0008, .0016, (count, 1))
    points = np.stack((samples[:, :3] - tangent * width, samples[:, :3] + tangent * width,
                       samples[:, :3] + normals * length + tangent * length * .35), axis=1)
    mesh = bpy.data.meshes.new(source[:-4] + '_fur')
    mesh.from_pydata(engine_to_blender(points.reshape(-1, 3)).tolist(), [], np.arange(count * 3).reshape(-1, 3).tolist())
    mesh.update()
    coords = np.repeat(samples[:, None, 6:8], 3, axis=1); coords[:, :, 1] = 1 - coords[:, :, 1]
    mesh.uv_layers.new().data.foreach_set('uv', coords.ravel())
    mesh.materials.append(material)
    # Shade fibers with the skin's interpolated surface normal. Flat normals
    # perpendicular to the body made each thin triangle a white specular fleck.
    mesh.polygons.foreach_set('use_smooth', [True] * len(mesh.polygons))
    mesh.normals_split_custom_set(engine_to_blender(np.repeat(normals,3,axis=0)).tolist())
    obj = bpy.data.objects.new(mesh.name, mesh); collection.objects.link(obj)
    filename = mesh.name + '.yfm'
    obj['source_mesh'] = filename; obj['runtime_color'] = '1 1 1'
    export_mesh(obj, filename)
    return filename, count


def garden_detail(key, surfaces, collection, material, spawn):
    """Model colorful broad-leaf plants/flowers along existing grassy terrain."""
    if not surfaces: return None, 0
    tris=np.concatenate(surfaces).reshape(-1,3,8)[:,:,:3]
    cross=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0])
    area=np.linalg.norm(cross,axis=1)*.5
    use=(cross[:,1]>area*1.6)&(area>.01)
    tris,area=tris[use],area[use]
    if not len(area): return None,0
    rng=np.random.default_rng(seed(key+'garden'))
    centers=tris.mean(axis=1)
    distance=np.linalg.norm(centers-np.array(spawn),axis=1)
    weights=area*(1+5*np.exp(-distance/16))
    count=min(650,int(area.sum()*1.2))
    vertices=[]; faces=[]; uvs=[]; normals=[]
    def triangle(a,b,c,cell,surface_normals=None):
        start=len(vertices)
        vertices.extend((a,b,c)); faces.append((start,start+1,start+2))
        uvs.extend((((cell+.15)/8,.15),((cell+.85)/8,.15),((cell+.5)/8,.85)))
        normals.extend(surface_normals if surface_normals is not None else ((0,1,0),)*3)
    def leaf(p,angle,length,width,cell):
        forward=np.array((math.cos(angle),0,math.sin(angle)))
        side=np.array((-math.sin(angle),0,math.cos(angle)))
        def point(t,s):
            shape=max(.015,math.sin(math.pi*t))**.7
            return p+forward*length*t+side*width*shape*s+np.array((0,length*(.72*math.sin(t*math.pi*.8)-.15*t)-width*.23*s*s,0))
        def normal(t,s):
            tangent=point(t+.001,s)-point(t-.001,s)
            across=point(t,s+.001)-point(t,s-.001)
            n=np.cross(across,tangent)
            if n[1]<0:n=-n
            return n/max(np.linalg.norm(n),1e-8)
        for row in range(6):
            for column in range(2):
                t0,t1=row/6,(row+1)/6
                s0,s1=column-1,column
                corners=((t0,s0),(t1,s0),(t1,s1),(t0,s1))
                ps=[point(t,s) for t,s in corners]; ns=[normal(t,s) for t,s in corners]
                triangle(ps[0],ps[1],ps[2],cell,(ns[0],ns[1],ns[2]))
                triangle(ps[0],ps[2],ps[3],cell,(ns[0],ns[2],ns[3]))
    volcanic='lava' in key.lower()
    for index in rng.choice(len(tris),count,p=weights/weights.sum()):
        a,b=rng.random(2)
        if a+b>1:a,b=1-a,1-b
        p=tris[index,0]+a*(tris[index,1]-tris[index,0])+b*(tris[index,2]-tris[index,0])
        if np.linalg.norm(p-np.array(spawn))<1.5: continue
        scale=rng.uniform(.18,.42)
        for n in range(5):
            leaf(p,n*math.tau/5+rng.uniform(-.2,.2),scale,.08,1 if volcanic else n%3)
        if rng.random()<.55:
            center=p+np.array((0,scale*.9,0))
            cell=3 if volcanic else int(rng.integers(3,6))
            for n in range(7):
                angle=n*math.tau/7
                radial=np.array((math.cos(angle),0,math.sin(angle)))
                side=np.array((-math.sin(angle),0,math.cos(angle)))
                mid=center+radial*.075+np.array((0,.018,0))
                for segment in range(10):
                    edge=[]
                    for theta in (segment*math.tau/10,(segment+1)*math.tau/10):
                        edge.append(mid+radial*math.cos(theta)*.065+side*math.sin(theta)*.036+np.array((0,-.012*math.sin(theta)**2,0)))
                    triangle(mid,edge[0],edge[1],cell)
                triangle(center+np.array((0,.015,0)),center+radial*.032,
                         center+np.array((math.cos(angle+.9)*.032,0,math.sin(angle+.9)*.032)),6)
    if not faces:return None,0
    mesh=bpy.data.meshes.new(key+'_garden')
    mesh.from_pydata(engine_to_blender(np.array(vertices)).tolist(),[],faces); mesh.update()
    mesh.uv_layers.new().data.foreach_set('uv',np.array(uvs).ravel())
    mesh.materials.append(material)
    mesh.polygons.foreach_set('use_smooth',[True]*len(mesh.polygons))
    mesh.normals_split_custom_set(engine_to_blender(np.array(normals)).tolist())
    obj=bpy.data.objects.new(mesh.name,mesh); collection.objects.link(obj)
    name=mesh.name+'.yfm'
    obj['source_mesh']=name; obj['runtime_color']='1 1 1'; obj['non_colliding_detail']=True
    export_mesh(obj,name)
    return name,len(faces)


def setup_scene(key, spawn):
    scene = bpy.context.scene
    scene.name = key
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new('Daylight')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.32, .43, .60, 1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .5
    light = bpy.data.lights.new('Sun', 'SUN'); light.energy = 3; light.angle = .08
    obj = bpy.data.objects.new('Sun', light); scene.collection.objects.link(obj)
    obj.rotation_euler = (.45, -.5, -.4)
    camera = bpy.data.cameras.new('Gameplay preview'); camera.lens = 35
    obj = bpy.data.objects.new('Gameplay preview', camera); scene.collection.objects.link(obj)
    focus = Vector((spawn[0], -spawn[2], spawn[1] + .65))
    obj.location = focus + Vector((0, -5, 2.2))
    obj.rotation_euler = (focus - obj.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = obj
    scene['runtime_scene'] = key
    scene['status'] = 'Procedural realism pass; original topology and baked animation retained'


def save(path):
    bpy.context.preferences.filepaths.save_version = 0
    # External relative textures are shared, keeping the authoring library small.
    for image in bpy.data.images:
        if image.source == 'FILE':
            image.filepath = '//' + str(Path(__import__('os').path.relpath(bpy.path.abspath(image.filepath), path.parent)))
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)


def export_edited(path):
    """Export saved Blender geometry edits; collision remains a separate contract."""
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    report = json.loads((OUT / 'remake-report.json').read_text())
    records = {entry['file']: entry for entry in report['meshes']}
    known_materials = {line.split('\t')[0] for line in (OUT / 'materials.tsv').read_text().splitlines()}
    collections = [c for c in bpy.context.scene.collection.children if c.name == 'Environment' or (OUT / (c.name + '.parts')).exists()]
    if not collections: raise ValueError('No runtime collections in ' + str(path))
    pending = []
    used_names = set()
    # Validate unsupported edits before changing any runtime files.
    for collection in collections:
        key = bpy.context.scene['runtime_scene'] if collection.name == 'Environment' else collection.name
        objects = []
        for obj in collection.all_objects:
            if obj.type != 'MESH': continue
            name = obj.get('source_mesh', obj.name + '.yfm')
            if Path(name).name != name or not name.endswith('.yfm') or name in used_names:
                raise ValueError('Mesh export names must be unique basenames: ' + name)
            used_names.add(name)
            if len(obj.data.materials) != 1:
                raise ValueError('Split objects by material before export: ' + obj.name)
            mat = obj.data.materials[0]
            texture = mat.get('runtime_albedo', '-')
            if texture != '-' and texture not in known_materials:
                raise ValueError('Bake/register the new material in materials.tsv first: ' + texture)
            color = obj.get('runtime_color', '1 1 1')
            if len(color.split()) != 3: raise ValueError('Invalid runtime_color: ' + obj.name)
            if abs(obj.matrix_world.determinant()) < 1e-10: raise ValueError('Singular transform: ' + obj.name)
            objects.append((obj, name, texture, color))
        if not objects: raise ValueError('Empty runtime collection: ' + collection.name)
        pending.append((key, objects))
    graph = bpy.context.evaluated_depsgraph_get()
    for key, objects in pending:
        rows = []
        for obj, name, texture, color in objects:
            evaluated = obj.evaluated_get(graph)
            temporary = evaluated.to_mesh()
            try:
                count = export_mesh(evaluated, name, obj.matrix_world, temporary)
            finally:
                evaluated.to_mesh_clear()
            records[name] = dict(file=name, triangles=count, treatment='edited in modern Blender')
            rows.append('\t'.join((name, texture, color)))
        (OUT / (key + '.parts')).write_text('\n'.join(rows) + '\n')
    referenced = {line.split('\t')[0] for manifest in OUT.glob('*.parts') for line in manifest.read_text().splitlines()}
    report['meshes'] = [records[name] for name in sorted(referenced)]
    (OUT / 'remake-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('EXPORTED_EDITED', path, len(pending), 'collections', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--texture-size', type=int, default=1024)
    parser.add_argument('--grass-budget', type=int, default=12000)
    parser.add_argument('--materials-only', action='store_true')
    parser.add_argument('--export-blend', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    if bpy.app.version < (5, 0, 0): raise RuntimeError('Blender 5 or newer required')
    if args.export_blend:
        export_edited(args.export_blend)
        return
    if not 128 <= args.texture_size <= 4096 or not 0 <= args.grass_budget <= 20000:
        raise ValueError('Texture size must be 128..4096; grass budget 0..20000')
    OUT.mkdir(parents=True, exist_ok=True); AUTHOR.mkdir(parents=True, exist_ok=True)
    report = dict(blender=bpy.app.version_string, seed='sha256(asset name)',
                  status='procedural remaster, original topology/animation retained',
                  materials=generate_materials(args.texture_size), meshes=[], scenes=[])
    if args.materials_only:
        existing=OUT/'remake-report.json'
        if existing.exists():
            previous=json.loads(existing.read_text())
            previous['materials']=report['materials']
            existing.write_text(json.dumps(previous,indent=2)+'\n')
        return
    for path in SOURCE.iterdir():
        if path.suffix in ('.entities', '.collision', '.hazards', '.markers', '.triggers') or path.name in ('levels.tsv', 'ATTRIBUTION.txt', 'COPYING', 'CC-BY3.0'):
            shutil.copy2(path, OUT / path.name)
    (OUT / 'ATTRIBUTION.txt').write_text(
        'YoFrankie! (c) 2008, Blender Foundation, www.blender.org\n'
        'Original media and derivative remaster media: Creative Commons Attribution 3.0.\n'
        'Procedural remaster: generated natural materials, surface fibers, ground cover, '
        'and modern Blender reconstruction of original models/poses.\n'
        'Original source: third_party/yofrankie; original provenance: PROVENANCE.json there.\n'
        'Editable derivative files: art/frankie-realistic. Generation: scripts/remake_frankie_blender.py.\n'
        'See remake-report.json for asset treatments and source texture hashes.\n')
    levels = [line.split('\t') for line in (SOURCE / 'levels.tsv').read_text().splitlines()]
    scene_ids = {row[0] for row in levels}
    prefabs = sorted(p for p in SOURCE.glob('*.parts') if p.stem not in scene_ids)
    # Save individual action libraries to keep authoring files practical to open.
    groups = {}
    for path in prefabs:
        key = '_'.join(path.stem.split('_')[:-1]) if path.stem.split('_')[-1].isdigit() and path.stem.startswith(('frankie_', 'rat_', 'ram_', 'sheep_cute_')) else 'props'
        groups.setdefault(key, []).append(path)
    for group, paths in groups.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        mats = materials()
        for index, path in enumerate(paths):
            collection = bpy.data.collections.new(path.stem)
            bpy.context.scene.collection.children.link(collection)
            collection.hide_render = index > 0
            collection.hide_viewport = index > 0
            lines = path.read_text().splitlines()
            extra = []
            for line in lines:
                mesh, texture, color = line.split('\t')
                obj, original = import_mesh(mesh, collection, mats.get(texture), color)
                triangles = export_mesh(obj, mesh)
                report['meshes'].append(dict(file=mesh, triangles=triangles, treatment='Blender reconstructed original topology'))
                detail, count = fur_detail(mesh, original, collection, mats.get(texture))
                if detail:
                    extra.append(detail + '\t' + texture + '\t1 1 1')
                    report['meshes'].append(dict(file=detail, triangles=count, treatment='new geometric surface fibers'))
            (OUT / path.name).write_text('\n'.join(lines + extra) + '\n')
        setup_scene(group, (0, 0, 0))
        save(AUTHOR / (group + '.blend'))
        print('AUTHOR_LIBRARY', group, len(paths), flush=True)
    for key, source, scene, spawn in levels:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        mats = materials()
        collection = bpy.data.collections.new('Environment')
        bpy.context.scene.collection.children.link(collection)
        lines = (SOURCE / (key + '.parts')).read_text().splitlines()
        grass_surfaces = []
        for line in lines:
            mesh, texture, color = line.split('\t')
            obj, original = import_mesh(mesh, collection, mats.get(texture), color)
            triangles = export_mesh(obj, mesh)
            report['meshes'].append(dict(file=mesh, triangles=triangles, treatment='Blender reconstructed original topology'))
            if family(texture) == 'grass': grass_surfaces.append(original)
        detail, triangle_count = ground_cover(key, grass_surfaces, collection, mats['detail_meadow.bmp'], args.grass_budget)
        if detail:
            lines.append(detail + '\tdetail_meadow.bmp\t1 1 1')
            report['meshes'].append(dict(file=detail, triangles=triangle_count, treatment='new procedural grass geometry'))
        garden, garden_count= garden_detail(key,grass_surfaces,collection,mats['detail_garden.bmp'],list(map(float,spawn.split())))
        if garden:
            lines.append(garden+'\tdetail_garden.bmp\t1 1 1')
            report['meshes'].append(dict(file=garden,triangles=garden_count,treatment='new modeled broad-leaf plants and flowers'))
        (OUT / (key + '.parts')).write_text('\n'.join(lines) + '\n')
        # Include runtime actor/prop placement in editable scenes as linked mesh copies.
        instances = bpy.data.collections.new('Actors and pickups')
        bpy.context.scene.collection.children.link(instances)
        cache = {}
        entities = (SOURCE / (key + '.entities')).read_text().splitlines()
        entities.append('player\tfrankie_idle_0\t' + spawn + '\t0\t1 1 1')
        for line in entities:
            if not line: continue
            kind, prefab, location, angle, scale = line.split('\t')
            if prefab not in cache:
                cache[prefab] = []
                staging = bpy.data.collections.new('Temporary')
                for part in (OUT / (prefab + '.parts')).read_text().splitlines():
                    mesh, texture, color = part.split('\t')
                    obj, _ = import_mesh(mesh, staging, mats.get(texture), color)
                    cache[prefab].append(obj.data)
                    bpy.data.objects.remove(obj, do_unlink=True)
                bpy.data.collections.remove(staging)
            pos = list(map(float, location.split())); size = list(map(float, scale.split()))
            for mesh in cache[prefab]:
                obj = bpy.data.objects.new(kind, mesh); instances.objects.link(obj)
                obj.location = (pos[0], -pos[2], pos[1] + (.28 if kind == 'player' else .3 if kind in ('ram', 'rat', 'sheep') else 0))
                obj.rotation_euler.z = float(angle)
                obj.scale = (size[0], size[2], size[1])
                obj['runtime_prefab'] = prefab
        setup_scene(key, list(map(float, spawn.split())))
        save(AUTHOR / (key + '.blend'))
        report['scenes'].append(dict(id=key, blend='art/frankie-realistic/' + key + '.blend', added_grass_triangles=triangle_count))
        print('AUTHOR_SCENE', key, 'new grass triangles', triangle_count, flush=True)
    (OUT / 'remake-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('REMAKE_COMPLETE', len(report['scenes']), 'scenes', len(report['meshes']), 'meshes', flush=True)


if __name__ == '__main__':
    main()
