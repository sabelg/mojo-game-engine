"""Fixed-exposure static HLOD quality and source fallback."""
from pathlib import Path
from collections import Counter
from PIL import Image,ImageChops,ImageStat
root=Path('build')
for variant in range(3):
 reference=Image.open(root/f'atlas-hlod-{variant}-0.bmp').convert('RGB')
 colors=Counter(reference.getdata())
 assert len(colors)>=4 and sum(colors.values())-max(colors.values())>1500,'HLOD fixture did not render its three surfaces'
 for mode in range(1,4):
  image=Image.open(root/f'atlas-hlod-{variant}-{mode}.bmp').convert('RGB')
  diff=ImageChops.difference(reference,image)
  mean=sum(ImageStat.Stat(diff).mean)/3
  if variant!=1:assert diff.getbbox() is None,('Exact aggregation changed pixels',variant,mode,mean)
  else:assert mean<.1,('Simplified fixture quality changed',mode,mean)
  print('HLOD',variant,'mode',mode,'mean byte error',round(mean,6))
 fallback=ImageChops.difference(Image.open(root/f'atlas-hlod-fallback-{variant}-0.bmp'),Image.open(root/f'atlas-hlod-fallback-{variant}-1.bmp'))
 assert fallback.getbbox() is None,'Changed-scene fallback changed pixels'
for mode in range(4):
 diff=ImageChops.difference(Image.open(root/f'atlas-hlod-0-{mode}.bmp'),Image.open(root/f'atlas-hlod-2-{mode}.bmp'))
 assert diff.getbbox() is None,'Billion-unit rebasing changed HLOD pixels'
print('HLOD captures passed: exact aggregation/rebasing, bounded simplified fixture error and exact fallback')
