"""Compile Vulkan GLSL to SPIR-V and embed aligned words in the native backend."""
from pathlib import Path
import os
import shutil
import struct
import subprocess

compiler = os.environ.get('GLSLC') or shutil.which('glslc')
if not compiler:
    raise SystemExit('Vulkan shader compiler missing: install glslc or set GLSLC')
output = Path('build')
output.mkdir(exist_ok=True)
arrays = ['"""Generated SPIR-V. Rebuild from shaders/, do not edit."""', 'from std.collections import Array', 'from std.builtin.globals import global_constant', 'from native.mojo.runtime_support import c_address']
for path in sorted(Path('shaders').iterdir()):
    if path.suffix not in {'.vert', '.frag'}:
        continue
    binary = output / (path.name + '.spv')
    subprocess.run([compiler, '--target-env=vulkan1.1', str(path), '-o', str(binary)], check=True)
    validator = shutil.which('spirv-val')
    if validator:
        subprocess.run([validator, '--target-env', 'vulkan1.1', str(binary)], check=True)
    data = binary.read_bytes()
    words = struct.unpack('<' + 'I' * (len(data) // 4), data)
    name = path.name.replace('.', '_')
    arrays.extend([f'comptime data_{name}: Array[UInt32, {len(words)}] = [' + ','.join(hex(w) for w in words) + ']', f'def shader_{name}() -> UInt64:', f'    return c_address(Pointer(to=global_constant[data_{name}]()))', f'def shader_{name}_size() -> UInt64:', f'    return {len(data)}'])
Path('native/mojo/shaders.mojo').write_text('\n'.join(arrays) + '\n')
