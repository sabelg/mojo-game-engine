"""Bounded offline TAA reference study with exact geometric motion/depth.

This is an algorithm experiment, not a Vulkan TAA implementation. It models
camera/object motion, jitter, depth disocclusion and local color clamping in linear
radiance. No production motion attachment, history allocation or presentation
cost is claimed. Run as part of the SDK suite to keep the evaluation reproducible.
"""
import argparse,hashlib,json,math
from pathlib import Path
W,H,FRAMES=64,48,32
JITTER=[(0,-1/6),(-.25,1/6),(.25,-7/18),(-.375,-1/18),(.125,5/18),(-.125,-5/18),(.375,1/18),(-.4375,7/18)]

def state(frame):return (.023*frame,math.sin(frame*.18)*1.4,JITTER[frame%len(JITTER)])
def sample(x,y,camera,actor,origin=0):
 # Subtract origin in double precision before the periodic material lookup.
 wx=(origin+camera+(x/W-.5)*8)-origin;wy=(y/H-.5)*6
 if abs(wx-actor)<.42 and abs(wy)<1.05:return (.9,.07,.03),.25,1,wx
 checker=(math.floor((wx+.01373)*9)+math.floor((wy+.03119)*9))&1
 value=.1 if checker else .8
 return (value,value,value),.75,0,wx

def render(frame,origin=0,supersample=1):
 camera,actor,jitter=state(frame);colors=[];depth=[];objects=[];points=[]
 for y in range(H):
  for x in range(W):
   color,z,obj,wx=sample(x+.5+jitter[0],y+.5+jitter[1],camera,actor,origin)
   depth.append(z);objects.append(obj);points.append(wx)
   if supersample==1:colors.append(color);continue
   total=[0.,0.,0.]
   for sy in range(supersample):
    for sx in range(supersample):
     c,*_=sample(x+(sx+.5)/supersample,y+(sy+.5)/supersample,camera,actor,origin)
     for channel in range(3):total[channel]+=c[channel]/supersample**2
   colors.append(tuple(total))
 return colors,depth,objects,points

def bilinear(image,x,y):
 x0=int(math.floor(x));y0=int(math.floor(y));fx=x-x0;fy=y-y0
 result=[0.,0.,0.]
 for xx,yy,weight in [(x0,y0,(1-fx)*(1-fy)),(x0+1,y0,fx*(1-fy)),(x0,y0+1,(1-fx)*fy),(x0+1,y0+1,fx*fy)]:
  value=image[min(H-1,max(0,yy))*W+min(W-1,max(0,xx))]
  for c in range(3):result[c]+=value[c]*weight
 return result

def resolve(current,depth,objects,points,history,old_depth,frame,motion=True,reject=True):
 camera,actor,jitter=state(frame);pcamera,pactor,pjitter=state(frame-1)
 output=[];rejected=0;revealed=0;max_reset_error=0.;max_vector=0.
 for y in range(H):
  for x in range(W):
   index=y*W+x
   px=(points[index]-(actor-pactor if objects[index] else 0)-pcamera+4)/8*W-.5-pjitter[0] if motion else x
   py=y+jitter[1]-pjitter[1] if motion else y
   max_vector=max(max_vector,math.hypot(px-x,py-y))
   valid=0<=px<W-1 and 0<=py<H-1
   disoccluded=False
   if valid:
    # Require every history texel contributing to the bilinear color sample
    # to represent the expected previous surface depth, avoiding edge bleed.
    x0=int(px);y0=int(py)
    disoccluded=any(abs(old_depth[yy*W+xx]-depth[index])>.01 for yy in [y0,y0+1] for xx in [x0,x0+1])
    if reject and disoccluded:valid=False
   if not valid:
    result=current[index];rejected+=1
    if disoccluded:
     revealed+=1;max_reset_error=max(max_reset_error,max(abs(a-b) for a,b in zip(result,current[index])))
   else:
    previous=bilinear(history,px,py)
    if reject:
     neighbors=[current[yy*W+xx] for yy in range(max(0,y-1),min(H,y+2)) for xx in range(max(0,x-1),min(W,x+2))]
     previous=[max(min(n[c] for n in neighbors),min(max(n[c] for n in neighbors),previous[c])) for c in range(3)]
    result=tuple(.15*current[index][c]+.85*previous[c] for c in range(3))
   output.append(result)
 return output,{'rejected':rejected,'disoccluded':revealed,'max_reset_error':max_reset_error,'max_vector_pixels':max_vector}

def mse(a,b,mask=None):
 indices=range(len(a)) if mask is None else mask
 values=[(a[i][c]-b[i][c])**2 for i in indices for c in range(3)]
 return sum(values)/max(1,len(values))

def evaluate(origin=0):
 history=None;naive=None;old_depth=None;rows=[]
 for frame in range(FRAMES):
  current,depth,objects,points=render(frame,origin);reference,*_=render(frame,origin,4)
  mask=[i for i,o in enumerate(objects) if o==0 and (i%W)>3 and (i%W)<W-4]
  if history is None:history=current;naive=current;info={'rejected':0,'disoccluded':0,'max_reset_error':0,'max_vector_pixels':0}
  else:
   history,info=resolve(current,depth,objects,points,history,old_depth,frame)
   naive,_=resolve(current,depth,objects,points,naive,old_depth,frame,False,False)
  rows.append({'frame':frame,'point_mse':mse(current,reference,mask),'taa_mse':mse(history,reference,mask),'naive_mse':mse(naive,reference,mask),**info})
  old_depth=depth
 warm=rows[8:]
 return {'kind':'offline-linear-temporal-reference','width':W,'height':H,'frames':FRAMES,'supersample_reference':4,
         'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
         'point_mse':sum(r['point_mse'] for r in warm)/len(warm),'taa_mse':sum(r['taa_mse'] for r in warm)/len(warm),
         'naive_mse':sum(r['naive_mse'] for r in warm)/len(warm),'disoccluded_pixels':sum(r['disoccluded'] for r in rows),
         'max_reset_error':max(r['max_reset_error'] for r in rows),'max_vector_pixels':max(r['max_vector_pixels'] for r in rows),'rows':rows,
         'limits':['Software reference vectors/depth; no Vulkan motion attachment or runtime TAA.',
                   'Linear orthographic layered surfaces; perspective, skin/wind/transparency and GPU cost are unqualified.',
                   'Neighborhood clamps and history rejection trade shimmer for blur/reset noise.']}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=Path('build/atlas-temporal-evaluation.json'));args=parser.parse_args()
 result=evaluate();far=evaluate(1_000_000_000)
 assert result['disoccluded_pixels']>100 and result['max_vector_pixels']>1
 assert result['max_reset_error']==0
 assert result['taa_mse']<result['point_mse']*.5,(result['point_mse'],result['taa_mse'])
 assert abs(result['taa_mse']-far['taa_mse'])<1e-8,'Origin-relative reference changed'
 result['billion_origin_mse_difference']=abs(result['taa_mse']-far['taa_mse'])
 args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2)+'\n')
 print('Offline temporal reference passed:',round(result['point_mse'],6),'point MSE;',round(result['taa_mse'],6),'TAA MSE;',result['disoccluded_pixels'],'disoccluded history samples rejected; runtime TAA remains disabled')
if __name__=='__main__':main()
