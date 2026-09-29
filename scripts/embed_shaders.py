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
arrays = ['/* Generated SPIR-V. Rebuild from shaders/, do not edit. */', '#include <stdint.h>']
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
    arrays.append(f'static const uint32_t {name}[] = {{' + ','.join(hex(w) for w in words) + '};')
(output / 'shaders.h').write_text('\n'.join(arrays) + '\n')
