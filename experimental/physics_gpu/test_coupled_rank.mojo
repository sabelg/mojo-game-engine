"""Device regression for roundoff-amplified null pivots; independent SVD gold."""
from std.collections import Array
from std.memory import Pointer
from std.testing import assert_true,assert_equal
from experimental.physics_gpu.lifecycle import GpuWorld
from experimental.physics_gpu.coupled_friction_math import linear8

def rank_kernel(output: Pointer[Float64,MutAnyOrigin]):
    var h: Array[Float64,64]=[0.7762344094319772,-0.04812065618278194,0.7731651492806009,0.3078385492561112,0.42027520399308416,-0.0511899163341588,0.41720594384170745,0.30476928910473444,-0.048120656182781905,0.7745746035669232,-0.04510387297287807,0.42470144149655675,0.3017525058875846,0.777591386776827,0.3047692890974884,0.4277182247064606,0.7775913867790366,-0.3017525058947827,0.7745746035690703,0.04812065618282024,0.42771822470143356,-0.30476928910474904,0.4247014414914674,0.045103872972854044,0.05118991633413784,0.4202752039982483,0.04812065618282025,0.7762344094302789,-0.3047692890978928,0.4172059438469307,-0.30783854924921045,0.7731651492789614,0.4247014414928291,0.04510387297273126,0.4277182247026957,-0.30476928909330914,0.7745746035588695,0.048120656182597775,0.7775913867687361,-0.30175250588344266,-0.3078385492515007,0.7731651492724754,-0.30476928910016543,0.41720594383837695,0.048120656182597775,0.7762344094238108,0.051189916333933196,0.4202752039897123,0.4172059438436002,0.3047692890933236,0.4202752039948764,-0.051189916333912254,0.773165149270836,0.3078385492445999,0.7762344094221124,-0.0481206561826361,0.3047692891005698,0.42771822469766857,0.3017525058906408,0.7775913867709452,-0.04510387297270716,0.42470144148773936,-0.04812065618263603,0.7745746035610164]
    var rhs: Array[Float64,8]=[8.451007898637881e-12,4.679454697974614e-11,-1.1687045698012976e-11,4.714077511324247e-11,-1.1687035848057433e-11,4.714077195165148e-11,8.451008347559747e-12,4.679453005840075e-11]
    # Exercise row/column permutations of the same rank-three reduced system.
    for variant in range(4):
        var a=Array[Float64,64](fill=0);var b=Array[Float64,8](fill=0)
        for i in range(8):
            var ri=(i+variant*2)%8;b[i]=rhs[ri]
            for j in range(8):a[i*8+j]=h[ri*8+(j+variant)%8]
        var result=linear8(a,b,8);output[unsafe_offset=variant*10]=Float64(result.rank);output[unsafe_offset=variant*10+1]=1 if result.valid else 0
        for i in range(8):output[unsafe_offset=variant*10+2+(i+variant)%8]=result.value[i]

def main() raises:
    var world=GpuWorld();var output=world._ctx.enqueue_create_buffer[DType.float64](41);output.enqueue_fill(-1234567)
    world._ctx.enqueue_function[rank_kernel](output,grid_dim=1,block_dim=1);world._ctx.synchronize()
    var gold: Array[Float64,8]=[-6.753763042583317e-13,1.960471293667658e-11,-6.753762679141739e-13,1.960470872164097e-11,-6.753720892227367e-13,1.960471297302074e-11,-6.753720528785725e-13,1.960470875798514e-11]
    with output.map_to_host() as values:
        for variant in range(4):
            print("RANK_REGRESSION",variant,"rank",values[variant*10],"first correction",values[variant*10+2])
            assert_equal(Float64(values[variant*10]),Float64(3));assert_equal(Float64(values[variant*10+1]),Float64(1))
            for i in range(8):assert_true(abs(Float64(values[variant*10+2+i])-gold[i])<=1e-12)
        assert_equal(Float64(values[40]),Float64(-1234567))
    world.close();print("Actual GPU rank-three least-norm correction and permutations pass independent SVD gold, original256eps cutoff and canary")
