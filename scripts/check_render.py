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

assert Path("build/gpu-textured.bmp").read_bytes() != Path("build/gpu-normal-map.bmp").read_bytes(), "Normal map did not affect surface shading"
assert Path("build/gpu-normal-map.bmp").read_bytes() != Path("build/gpu-orm-map.bmp").read_bytes(), "Packed material map did not affect surface shading"
assert Path("build/gpu-orm-base.bmp").read_bytes() != Path("build/gpu-orm-only.bmp").read_bytes(), "ORM channels did not affect shading without a normal map"
assert Path('build/gpu-morph-mid.bmp').read_bytes() == Path('build/gpu-morph-reference.bmp').read_bytes(), 'GPU morph disagrees with static midpoint geometry'
assert Path('build/gpu-origin.bmp').read_bytes() != Path('build/gpu-art-lighting.bmp').read_bytes(), 'Scene lighting had no effect'
ui=pixels('build/gpu-font.bmp')
assert ui[(241-30-1)*321+30]==(0,0,255), 'Circle center did not render'
assert ui[(241-10-1)*321+10]!=(0,0,255), 'Circle incorrectly fills its bounding box'
assert len(set(ui[(241-y-1)*321+x] for y in range(16,48) for x in range(65,195)))>10, 'Font glyphs did not render with smooth alpha'
