"""Compare independently deformed CPU/GPU fixture images with a raster tolerance."""
from PIL import Image,ImageChops,ImageStat
cpu=Image.open('build/atlas-skin-cpu.bmp').convert('RGB')
gpu=Image.open('build/atlas-skin-gpu.bmp').convert('RGB')
assert cpu.size==gpu.size
mean=sum(ImageStat.Stat(ImageChops.difference(cpu,gpu)).mean)/3
assert mean<.15,('GPU skinning parity mean error exceeds 0.15/255',mean)
assert len(set(cpu.getdata()))>30,'Skin fixture rendered no useful geometry'
print(f'Skin raster parity passed: lit/shadow/depth mean error {mean:.6f}/255')
