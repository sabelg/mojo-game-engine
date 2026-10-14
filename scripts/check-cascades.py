"""Check actual atlas occupancy, shadow effect and independent skin/origin parity."""
from pathlib import Path
import sys
from PIL import Image,ImageChops,ImageStat

root=Path('build')
prefix='-hdr' if '--hdr' in sys.argv else ''
def pixels(image):return image.get_flattened_data() if hasattr(image,'get_flattened_data') else image.getdata()
def difference(first,second):return sum(ImageStat.Stat(ImageChops.difference(first,second)).mean)/3
for frames in (1,2):
 images=[Image.open(root/f'atlas-cascades{prefix}-{case}-{frames}.bmp').convert('RGB') for case in range(5)]
 assert len(set(pixels(images[1])))>50,'Cascade fixture rendered no useful geometry'
 assert (root/f'atlas-cascades{prefix}-1-{frames}.bmp').read_bytes()==(root/f'atlas-cascades{prefix}-2-{frames}.bmp').read_bytes(),'Floating-origin cascade capture differs'
 error=difference(images[1],images[4]);assert error<.15,('Cascade CPU/GPU skin mismatch',error)
 shadow=ImageChops.difference(images[1],images[3]);changed=sum(value!=(0,0,0) for value in pixels(shadow))
 assert changed>50,('Cascade casters did not affect the final image',changed)
 atlas=Image.open(root/f'atlas-cascade-atlas{prefix}-{frames}.bmp').convert('RGB');width,height=atlas.size;counts=[]
 for tile in range(4):
  count=sum(atlas.getpixel((x,y))[0]<250 for y in range(tile//2*height//2,(tile//2+1)*height//2) for x in range(tile%2*width//2,(tile%2+1)*width//2))
  assert count>0,('Cascade atlas tile contains no depth',tile);counts.append(count)
 resized=Image.open(root/f'atlas-cascade-resized{prefix}-{frames}.bmp')
 assert resized.size==(503,277) and sum(pixel[1]>pixel[0]+10 and pixel[1]>pixel[2]+10 for pixel in pixels(resized))>10,'Legacy reset/resize did not render the green fixture; atlas debug may still be enabled'
 print('Cascade capture checks:',frames,'frame banks; tile pixels',counts,'shadow pixels',changed,'skin mean error',error)
for case in range(5):assert (root/f'atlas-cascades{prefix}-{case}-1.bmp').read_bytes()==(root/f'atlas-cascades{prefix}-{case}-2.bmp').read_bytes(),('Cascade frame-bank parity mismatch',case)
print('Directional shadow captures passed: populated atlas, actual shadow effect, GPU/CPU skin, origin and frame-bank parity')
