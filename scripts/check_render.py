"""Validate headless frame content without third-party image dependencies."""
import struct
from pathlib import Path


def pixels(path):
    data = Path(path).read_bytes()
    assert data[:2] == b'BM', f'{path}: not a BMP'
    offset = struct.unpack_from('<I', data, 10)[0]
    width, height = struct.unpack_from('<ii', data, 18)
    depth = struct.unpack_from('<H', data, 28)[0]
    assert width > 0 and height > 0 and depth == 24
    pitch = (width * 3 + 3) & ~3
    assert len(data) >= offset + pitch * height
    return [tuple(data[offset+y*pitch+x*3:offset+y*pitch+x*3+3])
            for y in range(height) for x in range(width)]

origin = Path('build/gpu-origin.bmp').read_bytes()
assert origin == Path('build/gpu-far.bmp').read_bytes(), 'Floating-origin render mismatch'
cube = pixels('build/gpu-origin.bmp')
background = cube[0]
assert sum(p != background for p in cube) > 1000, 'Cube did not render'
resized = pixels('build/gpu-resized.bmp')
assert len(resized) == 503 * 277, 'Render target resize did not take effect'
# BMP rows are bottom-up. The top-left overlay must remain at the top after migration.
assert resized[276 * 503] == (0, 0, 255), 'Overlay vertical convention is wrong'
assert resized[0] != (0, 0, 255), 'Overlay was vertically inverted'
world = pixels('build/open-world.bmp')
assert len(set(world)) > 100, 'World frame lacks shaded geometry'
print('Image checks passed: rendered geometry and bit-identical billion-unit translation')
wind=[pixels(f'build/gpu-wind-{i}.bmp') for i in range(9)]
assert wind[0]==wind[3]==wind[6]==wind[7], 'Wind zero/disabled/frame-reset changed the static render'
assert wind[1]==wind[4]==wind[8], 'Wind changed across floating origins or long-running clock wrapping'
assert sum(a!=b for a,b in zip(wind[1],wind[2]))>100, 'Wind did not animate'
error=sum(abs(x-y) for a,b in zip(wind[1],wind[5]) for x,y in zip(a,b))/(len(wind[1])*3)
assert error<0.05, f'GPU wind differs from CPU geometry/normals/shadow reference: {error}'
print(f'Wind checks passed: disabled/reset/origin/clock parity; CPU geometry and shadow mean error {error:.6f}/255')

assert Path("build/gpu-textured.bmp").read_bytes() != Path("build/gpu-normal-map.bmp").read_bytes(), "Normal map did not affect surface shading"
assert Path("build/gpu-normal-map.bmp").read_bytes() != Path("build/gpu-orm-map.bmp").read_bytes(), "Packed material map did not affect surface shading"
assert Path("build/gpu-orm-base.bmp").read_bytes() != Path("build/gpu-orm-only.bmp").read_bytes(), "ORM channels did not affect shading without a normal map"
assert Path('build/gpu-morph-mid.bmp').read_bytes() == Path('build/gpu-morph-reference.bmp').read_bytes(), 'GPU morph disagrees with static midpoint geometry'
assert Path('build/gpu-origin.bmp').read_bytes() != Path('build/gpu-art-lighting.bmp').read_bytes(), 'Scene lighting had no effect'
ui=pixels('build/gpu-font.bmp')
assert ui[(241-30-1)*321+30]==(0,0,255), 'Circle center did not render'
assert ui[(241-10-1)*321+10]!=(0,0,255), 'Circle incorrectly fills its bounding box'
assert len(set(ui[(241-y-1)*321+x] for y in range(16,48) for x in range(65,195)))>10, 'Font glyphs did not render with smooth alpha'

base = pixels('build/gpu-cinematic-0.bmp')
cinematic = pixels('build/gpu-cinematic-1.bmp')
assert sum(a != b for a, b in zip(base, cinematic)) > 1000, 'Cinematic effects did not shade the world'
assert base == pixels('build/gpu-cinematic-2.bmp'), 'Cinematic settings leaked into the next frame'
assert base == pixels('build/gpu-cinematic-3.bmp'), 'Zero cinematic strength changed the frame'
for y in range(102,122):
    for x in range(122,198):
        i = (241-y-1)*321+x
        assert base[i] == cinematic[i], 'Cinematic grading changed the HUD'
print('Cinematic checks passed: world shading, unchanged HUD, reset and disabled parity')

projection = [Path(f'build/gpu-projection-{i}.bmp').read_bytes() for i in range(5)]
assert projection[0] != projection[1], 'Triplanar projection did not change UV mapping'
assert projection[1] == projection[2], 'Triplanar projection depends on legacy UVs'
assert projection[1] == projection[3], 'Projected material moved with the floating origin'
assert projection[0] == projection[4], 'Disabling projection failed to restore UV mapping'
projected_normal = Path('build/gpu-projection-material-0.bmp').read_bytes()
projected_orm = Path('build/gpu-projection-material-1.bmp').read_bytes()
assert projection[1] != projected_normal, 'Projected normal map did not affect shading'
assert projected_normal != projected_orm, 'Projected ORM map did not affect shading'
print('Triplanar checks passed: UV independence, floating-origin stability, disabled parity, normal and ORM response')

leaves = [pixels(f'build/gpu-foliage-{i}.bmp') for i in range(6)]
assert sum(a != b for a,b in zip(leaves[0],leaves[1])) > 1000, 'Backlit foliage did not transmit light'
assert leaves[0] == leaves[2], 'Disabling foliage changed the ordinary material'
assert leaves[3] == leaves[4], 'Foliage transmission leaked through an opaque shadow caster'
assert leaves[1] == leaves[5], 'Leaf lighting changes when viewing the reverse side'
print('Foliage checks passed: backlighting, two-sided parity, disabled parity and blocked transmission')

slope = [pixels(f'build/gpu-slope-{i}.bmp') for i in range(5)]
assert slope[0] == slope[1] == slope[4], 'Neutral or disabled slope tint changed the surface'
assert sum(a!=b for a,b in zip(slope[0],slope[2]))>100, 'Slope tint failed to shade steep faces'
assert sum(a==b and a!=slope[0][0] for a,b in zip(slope[0],slope[2]))>100, 'Slope tint affected level ground'
assert slope[2] != slope[3], 'Slope tint behaved like an ordinary uniform color multiplier'
print('Terrain checks passed: level-ground preservation, steep-face response and disabled parity')
