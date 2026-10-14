"""Verify MSAA adds fractional edge coverage and survives target recreation."""
from pathlib import Path
import struct
from collections import Counter

def pixels(path):
    data=path.read_bytes();offset=struct.unpack_from('<I',data,10)[0]
    width,height=struct.unpack_from('<ii',data,18)
    bits=struct.unpack_from('<H',data,28)[0]
    assert bits==24 and height>0
    stride=(width*3+3)&~3
    assert len(data)==offset+stride*height
    values=Counter()
    for y in range(height):values.update(struct.iter_unpack('3B',data[offset+y*stride:offset+y*stride+width*3]))
    return (width,height),values

root=Path('build');counts={}
for samples in (1,4):
    first=root/f'msaa-{samples}-0.bmp';last=root/f'msaa-{samples}-2.bmp'
    assert first.read_bytes()==last.read_bytes(),'Recreated target changed the image'
    assert pixels(root/f'msaa-{samples}-1.bmp')[0]==(333,251)
    counts[samples]=pixels(first)[1]
assert len(counts[1])==3,'Fixture must contain only background, solid triangle and UI'
partial=set(counts[4])-set(counts[1])
assert len(partial)>=3 and sum(counts[4][p] for p in partial)>300,'No fractional edge coverage'
print('MSAA passed: fractional edge coverage, stable UI colors and exact resize restoration')
