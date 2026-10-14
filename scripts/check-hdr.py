"""Check actual linear-light output rather than treating a successful draw as proof."""
from pathlib import Path
from PIL import Image,ImageChops,ImageStat

def encode(value,exposure=1):
    x=max(0,value*exposure)
    x=max(0,min(1,(x*(2.51*x+.03))/(x*(2.43*x+.59)+.14)))
    y=12.92*x if x<=.0031308 else 1.055*x**(1/2.4)-.055
    return round(y*255)
def decode(value):
    x=value/255
    return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4

def close(actual,expected,tolerance=1):
    assert max(abs(a-b) for a,b in zip(actual,expected))<=tolerance,(actual,expected)

root=Path('build')
for samples in (1,4):
    for banks in (1,2):
        images=[Image.open(root/f'atlas-hdr-{samples}-{banks}-{mode}.bmp').convert('RGB') for mode in range(9)]
        assert images[0].tobytes()==images[8].tobytes(),'Disabling HDR/environment failed to restore legacy rendering'
        assert images[1].tobytes()==images[6].tobytes(),'HDR resize changed output'
        assert images[5].size==(333,251)
        for mode,exposure in [(1,1),(2,.25),(3,4)]:
            close(images[mode].getpixel((160,140)),tuple(encode(x,exposure) for x in (4,2,1)))
            close(images[mode].getpixel((0,0)),tuple(encode(x,exposure) for x in (.2,.4,.6)))
        close(images[4].getpixel((160,140)),tuple(encode(decode(x)*8) for x in (128,64,32)))
        close(images[0].getpixel((20,20)),(26,204,51),1)
        for im in images:close(im.getpixel((20,20)),images[0].getpixel((20,20)),0)
        change=ImageChops.difference(images[1],images[7])
        assert sum(ImageStat.Stat(change).mean)>1,'Environment had no visible material response'
        water=[Image.open(root/f'atlas-hdr-water-{samples}-{banks}-{i}.bmp').convert('RGB') for i in (0,1)]
        difference=ImageChops.difference(*water)
        assert max(hi for lo,hi in difference.getextrema())<=2,'Water mixed display-encoded light before exposure'
        assert len(set(water[0].getdata()))>30,'Water scene did not render'
        eye=[Image.open(root/f'atlas-hdr-eye-{samples}-{banks}-{i}.bmp').convert('RGB') for i in (0,1)]
        assert sum(ImageStat.Stat(ImageChops.difference(*eye)).mean)/3<.05,'Camera-relative reflections/fog changed with the draw origin'
    for mode in range(9):
        assert (root/f'atlas-hdr-{samples}-1-{mode}.bmp').read_bytes()==(root/f'atlas-hdr-{samples}-2-{mode}.bmp').read_bytes(),'HDR frame banks disagree'
    for scale in (0,1):
        assert (root/f'atlas-hdr-water-{samples}-1-{scale}.bmp').read_bytes()==(root/f'atlas-hdr-water-{samples}-2-{scale}.bmp').read_bytes(),'HDR water frame banks disagree'
print('HDR captures passed: fixed radiance/exposure, exact sRGB texture decode, linear water scaling, unchanged UI, environment response, camera-relative origin parity, resize and frame banks')
