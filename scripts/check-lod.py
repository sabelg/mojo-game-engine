"""Same-driver LOD parity and measured one-sided coverage."""
from pathlib import Path
from PIL import Image,ImageChops
root=Path('build')
reference=Image.open(root/'atlas-lod-0.bmp').convert('RGB')
for mode in range(1,6):
 image=Image.open(root/f'atlas-lod-{mode}.bmp').convert('RGB')
 assert ImageChops.difference(reference,image).getbbox() is None,'Complementary LOD changed color/shadow/water result'
images=[Image.open(root/f'atlas-lod-coverage-{mode}.bmp').convert('RGB') for mode in range(5)]
background=list(images[-1].getdata());full=list(images[0].getdata())
footprint=[i for i,(a,b) in enumerate(zip(full,background)) if a!=b]
assert len(footprint)>100,'Coverage fixture did not render'
previous=set(footprint)
for mode,image in enumerate(images):
 pixels=list(image.getdata());active={i for i in footprint if pixels[i]!=background[i]}
 assert active<=previous,'Coverage increased while fading out'
 ratio=len(active)/len(footprint)
 assert abs(ratio-(1-mode/4))<.04,(mode,ratio)
 previous=active
 print('LOD coverage',mode,'fraction',round(ratio,4))
print('LOD captures passed: exact complementary coverage and monotonic measured fade')
