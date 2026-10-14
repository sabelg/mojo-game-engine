"""Independent Decimal80 full-matrix instantaneous rigid-body impact oracle."""
from decimal import Decimal,localcontext
from pathlib import Path
import math,json
O=Path(__file__).resolve().parent
SENTINEL=-987654321.25
D=lambda x:Decimal.from_float(float(x))
def dot(a,b):return sum((x*y for x,y in zip(a,b)),Decimal(0))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def add(a,b):return [x+y for x,y in zip(a,b)]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def mul(a,t):return [x*t for x in a]
def norm(a):return dot(a,a).sqrt()
def transpose(M):return list(map(list,zip(*M)))
def mv(M,a):return [dot(r,a) for r in M]
def mm(A,B):return [[dot(r,c) for c in transpose(B)] for r in A]
def rotation(q):
 x,y,z,w=mul(q,1/norm(q));two=Decimal(2);one=Decimal(1)
 return [[one-two*(y*y+z*z),two*(x*y-z*w),two*(x*z+y*w)],[two*(x*y+z*w),one-two*(x*x+z*z),two*(y*z-x*w)],[two*(x*z-y*w),two*(y*z+x*w),one-two*(x*x+y*y)]]
def inverse(M):
 A=[r.copy()+[Decimal(int(i==j)) for j in range(3)] for i,r in enumerate(M)]
 for col in range(3):
  p=max(range(col,3),key=lambda i:abs(A[i][col]));A[p],A[col]=A[col],A[p];v=A[col][col];assert v!=0;A[col]=[x/v for x in A[col]]
  for i in range(3):
   if i==col:continue
   v=A[i][col];A[i]=[a-v*b for a,b in zip(A[i],A[col])]
 return [r[3:] for r in A]
def det(M):return M[0][0]*(M[1][1]*M[2][2]-M[1][2]*M[2][1])-M[0][1]*(M[1][0]*M[2][2]-M[1][2]*M[2][0])+M[0][2]*(M[1][0]*M[2][1]-M[1][1]*M[2][0])
def geometry(x):
 R=rotation(x[8:12]);S=rotation(x[30:34]);half=x[24:27];center=x[27:30];arms=[];points=[];gaps=[];speeds=[]
 for i in range(8):
  corner=[half[j]*(1 if i&(1<<j) else -1) for j in range(3)];r=mv(R,add(center,mv(S,corner)));p=add(x[5:8],r);arms.append(r);points.append(p);gaps.append(p[1]-x[34]);speeds.append(add(x[12:15],cross(x[15:18],r))[1])
 return R,arms,points,gaps,speeds

def oracle(values,forced_code=None):
 with localcontext() as ctx:
  ctx.prec=80;x=list(map(D,values));out=[D(SENTINEL) if i in (0,95) else x[i] if i<=38 else Decimal(0) for i in range(96)]
  if forced_code in [600,601,602]:out[39]=D(forced_code);return list(map(float,out))
  R,arms,points,gaps,speeds=geometry(x);idx=min(range(8),key=lambda i:(gaps[i],i));second=min(gaps[i] for i in range(8) if i!=idx);out[40]=D(idx);out[41]=gaps[idx];out[42]=second;out[75:83]=gaps;out[83:91]=speeds
  if abs(gaps[idx])>D(1e-9):code=603
  elif second<=D(1e-9):code=604
  else:code=0
  if code:out[39]=D(code);assert forced_code in (None,code);return list(map(float,out))
  inertia=mm(mm(R,[[x[2+i] if i==j else Decimal(0) for j in range(3)] for i in range(3)]),transpose(R));invI=inverse(inertia);r=arms[idx];rx=[[Decimal(0),-r[2],r[1]],[r[2],Decimal(0),-r[0]],[-r[1],r[0],Decimal(0)]];K=mm(mm(rx,invI),transpose(rx))
  for i in range(3):K[i][i]+=1/x[1]
  incoming=speeds[idx];eff=x[36] if x[37]==1 and incoming<-D(.2) else Decimal(0);beta=-eff*incoming;N=(beta-incoming)/K[1][1] if incoming<0 else Decimal(0);J=[Decimal(0),N,Decimal(0)];tau=cross(r,J);v=add(x[12:15],mul(J,1/x[1]));w=add(x[15:18],mv(invI,tau));before=(x[1]*dot(x[12:15],x[12:15])+dot(x[15:18],mv(inertia,x[15:18])))/2;after=(x[1]*dot(v,v)+dot(w,mv(inertia,w)))/2;loss=(1-eff*eff)*incoming*incoming/(2*K[1][1]) if N>0 else Decimal(0);vn=add(v,cross(w,r))[1]
  out[43]=incoming;out[44]=beta;out[45]=N;out[46]=K[1][1];out[47]=abs(vn-beta) if N>0 else max(Decimal(0),-vn);out[48]=before;out[49]=after;out[50]=loss;out[51]=norm(sub(mul(sub(v,x[12:15]),x[1]),J));dL=sub(mv(inertia,w),mv(inertia,x[15:18]));out[52]=norm(sub(dL,tau));out[53]=norm(sub(add(dL,cross(x[5:8],mul(sub(v,x[12:15]),x[1]))),cross(points[idx],J)));out[54]=D(1e-9)*(1+abs(incoming));out[56]=eff;out[57]=norm(x[15:18]);out[58]=norm(w);out[59]=det(K);out[60:69]=[a for row in K for a in row];out[69:72]=r;out[72:75]=points[idx];out[91]=dot(x[8:12],x[8:12]);out[92]=dot(x[30:34],x[30:34]);out[93]=abs(after-before+loss);out[94]=vn
  if max(map(abs,w))>10 or max(map(abs,v))>20:out[39]=D(606);assert forced_code in (None,606)
  else:
   assert forced_code is None,(forced_code,idx,N,w)
   if N>0:out[12:15]=v;out[15:18]=w;out[55]=x[37]
  return list(map(float,out))

def qmul(a,b):
 x,y,z,w=a;X,Y,Z,W=b;return [w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]
def axis(axis,angle):return [v*math.sin(angle/2) for v in axis]+[math.cos(angle/2)]
def angles(rx,ry,rz):return qmul(qmul(axis([0,1,0],ry),axis([1,0,0],rx)),axis([0,0,1],rz))
def fixture(kind,variant,order):
 m=[2,.1,100,2][variant];I=[[4/3]*3,[.01,.02,.025],[10,100,100],[.2,.3,.4]][variant].copy();half=[[.5]*3,[.25,.5,.75],[.75,.5,.25],[.5]*3][variant].copy();q=angles(.23 if variant%2==0 else -.23,.31,.19 if variant<2 else -.19);shape=[0,0,0,1];center=[0,0,0];floor=0;omega=[.4,.3,-.2];incoming=-1;new=1;e=0;force=[0,0,0];torque=[0,0,0];gap=0;code=None
 if kind==1:e=.5
 if kind==2:e=1
 if kind in [3,4,5]:omega=[0,0,0];incoming=[-.2,-.2-1e-10,-.2+1e-10][kind-3];e=1
 if kind==6:incoming=.1
 if kind==7:incoming=0;omega=[0,0,0]
 if kind==8:incoming=-5.551115123125783e-17;omega=[0,0,0]
 if kind==9:omega=[0,1,0]
 if kind==11:q=[-v for v in q]
 if kind==12:shape=angles(.13,.17,0)
 if kind==13:center=[.08,-.04,.03]
 if kind==14:floor=2
 if kind==15:gap=-.5e-9
 if kind==16:gap=.5e-9
 if kind==17:force=[.2,-.4,.5];torque=[.1,.2,-.1]
 if kind==18:new=0;e=1
 if kind==19:new=0;incoming=.1
 if kind==20:q=angles(2.2 if variant%2==0 else -2.2,.7,.4 if variant<2 else -.4)
 if kind==21:incoming=-.5;omega=[-.7,.9,.6]
 if kind==22:incoming=-1e-12;omega=[0,0,0]
 if kind==23:incoming=1e-12;omega=[0,0,0]
 if kind==24:q=[0,0,0,1];code=604
 if kind==25:q=axis([1,0,0],.2);code=604
 if kind==26:code=602
 if kind==27:e=1.1;code=602
 if kind==28:new=2;code=602
 if kind==29:gap=1e-6;code=603
 if kind==30:gap=-2e-9;code=603
 if kind==31:shape=[0,0,0,2];code=601
 if kind==32:m=0;code=600
 if kind==33:omega=[20,0,0];code=600
 if kind==34:half[0]=0;code=601
 if kind==35:code=602
 if kind==36:q=axis([1,0,0],1e-12);code=604
 if kind==37:m=100;I=[1e-4]*3;half=[.05]*3;incoming=-19;omega=[0,0,0];code=606
 if kind==38:code=601
 if kind==39:center=[11,0,0];code=601
 x=[SENTINEL if i in (0,95) else 0.0 for i in range(96)];x[1:5]=[m]+I;x[8:12]=q;x[15:18]=omega;x[18:21]=force;x[21:24]=torque;x[24:27]=half;x[27:30]=center;x[30:34]=shape;x[34]=floor;x[35]=.2 if kind==26 else 0;x[36]=e;x[37]=new;x[38]=16 if kind==35 else order
 with localcontext() as ctx:
  ctx.prec=80;R,arms,points,gaps,speeds=geometry(list(map(D,x)));idx=min(range(8),key=lambda i:(gaps[i],i));r=list(map(float,arms[idx]));x[5:8]=[7 if kind==14 else 0,float(D(floor)-arms[idx][1])+gap,-4 if kind==14 else 0]
 if kind==10:
  omega=[math.copysign(.5,r[2]),0,-math.copysign(.5,r[0])];x[15:18]=omega;x[12:15]=[.3,0,.4]
 else:x[12:15]=[.3,incoming-(omega[2]*r[0]-omega[0]*r[2]),.4]
 if kind==38:x[34]=2000
 return x,code

def generate():
 receipts=[]
 for variant in range(4):
  rows=[]
  for kind in range(40):
   for order in range(16):
    x,code=fixture(kind,variant,order);y=oracle(x,code);rows.append('\t'.join(map(str,[kind,variant,order]+x+y)));receipts.append({'kind':kind,'variant':variant,'order':order,'input':x,'expected':y,'expected_code':int(y[39])})
  (O/f'fixtures-{variant}.tsv').write_text('\n'.join(rows)+'\n')
 with (O/'independent-reference.jsonl').open('w') as f:
  for r in receipts:f.write(json.dumps(r)+'\n')
 (O/'reference-proof.json').write_text(json.dumps({'precision_digits':80,'records':len(receipts),'accepted':sum(r['expected_code']==0 for r in receipts),'rejected':sum(r['expected_code']!=0 for r in receipts),'method':'Explicit rotation matrices; full3x3 inertia via matrix products; independent Gaussian-Jordan inverse; contactmetric via cross-product matrix congruence; analytic scalar impulse; Decimalmomentum/energy witnesses','production_imports':False,'supported_minimum_vertices':sorted({int(r['expected'][40]) for r in receipts if r['expected_code']==0})},indent=2)+'\n')
 print('DECIMAL_REFERENCE_GENERATED',len(receipts))
if __name__=='__main__':generate()
