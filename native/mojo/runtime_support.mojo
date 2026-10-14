from std.ffi import external_call
from std.sys import size_of
from std.collections import Array
from std.math import isfinite, sqrt, sin, cos, ceil

comptime CRawPointer = Pointer[UInt8, MutUntrackedOrigin]
comptime CPointer = Optional[CRawPointer]

def c_address[T: AnyType, origin: Origin](p: Pointer[T, origin]) -> UInt64:
    return UInt64(Int(p))
def c_nullable_address(p: CPointer) -> UInt64:
    return c_address(p.value()) if p else 0
def c_pointer(p: UInt64) -> CPointer:
    return CPointer(CRawPointer(unsafe_from_address=Int(p))) if p else CPointer(None)
def c_ref[T: AnyType](p: UInt64) -> Pointer[T, MutUntrackedOrigin]:
    return Pointer[T, MutUntrackedOrigin](unsafe_from_address=Int(p))
def c_set[dtype: DType](p: UInt64, value: SIMD[dtype, 1]) -> SIMD[dtype, 1]:
    c_ref[SIMD[dtype, 1]](p)[] = value
    return value
def c_increment[dtype: DType](p: UInt64, amount: Int, postfix: Int) -> SIMD[dtype, 1]:
    comptime T = SIMD[dtype, 1]
    var previous = c_ref[T](p)[]
    c_ref[T](p)[] += T(amount)
    return previous if postfix else c_ref[T](p)[]
def c_function[F: RegisterPassable & ImplicitlyCopyable](var address: UInt64) -> F:
    return Pointer(to=address).unsafe_bitcast[F]()[]
def port_log(format_address: UInt64, message_address: UInt64) -> Int32:
    var buffer = Array[UInt8, 4096](fill=0)
    var length = external_call["snprintf", Int32, num_fixed_args=3](c_pointer(c_address(buffer.unsafe_ptr())), UInt64(4096), c_pointer(format_address), c_pointer(message_address))
    if length > 0:
        _ = external_call["write", Int](Int(2), buffer.unsafe_ptr(), Int(min(Int(length), 4095)))
    return length

from std.builtin.globals import global_constant
comptime c_literal_data_0: Array[UInt8,3] = [37,115,0]
def c_literal_0() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_0]()))
comptime c_literal_data_1: Array[UInt8,16] = [37,115,58,32,86,107,82,101,115,117,108,116,32,37,100,0]
def c_literal_1() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_1]()))
comptime c_literal_data_2: Array[UInt8,23] = [86,117,108,107,97,110,32,118,97,108,105,100,97,116,105,111,110,58,32,37,115,10,0]
def c_literal_2() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_2]()))
comptime c_literal_data_3: Array[UInt8,33] = [78,111,32,99,111,109,112,97,116,105,98,108,101,32,86,117,108,107,97,110,32,109,101,109,111,114,121,32,116,121,112,101,0]
def c_literal_3() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_3]()))
comptime c_literal_data_4: Array[UInt8,51] = [118,107,67,114,101,97,116,101,66,117,102,102,101,114,40,103,45,62,100,101,118,105,99,101,44,32,38,105,110,102,111,44,32,78,85,76,76,44,32,38,98,45,62,98,117,102,102,101,114,41,0]
def c_literal_4() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_4]()))
comptime c_literal_data_5: Array[UInt8,59] = [118,107,65,108,108,111,99,97,116,101,77,101,109,111,114,121,40,103,45,62,100,101,118,105,99,101,44,32,38,97,108,108,111,99,97,116,105,111,110,44,32,78,85,76,76,44,32,38,98,45,62,109,101,109,111,114,121,41,0]
def c_literal_5() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_5]()))
comptime c_literal_data_6: Array[UInt8,55] = [118,107,66,105,110,100,66,117,102,102,101,114,77,101,109,111,114,121,40,103,45,62,100,101,118,105,99,101,44,32,98,45,62,98,117,102,102,101,114,44,32,98,45,62,109,101,109,111,114,121,44,32,48,41,0]
def c_literal_6() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_6]()))
comptime c_literal_data_7: Array[UInt8,67] = [118,107,77,97,112,77,101,109,111,114,121,40,103,45,62,100,101,118,105,99,101,44,32,98,45,62,109,101,109,111,114,121,44,32,48,44,32,86,75,95,87,72,79,76,69,95,83,73,90,69,44,32,48,44,32,38,98,45,62,109,97,112,112,101,100,41,0]
def c_literal_7() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_7]()))
comptime c_literal_data_8: Array[UInt8,30] = [66,117,102,102,101,114,32,119,114,105,116,101,32,101,120,99,101,101,100,115,32,99,97,112,97,99,105,116,121,0]
def c_literal_8() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_8]()))
comptime c_literal_data_9: Array[UInt8,53] = [118,107,67,114,101,97,116,101,73,109,97,103,101,40,103,45,62,100,101,118,105,99,101,44,32,38,105,110,102,111,44,32,78,85,76,76,44,32,38,105,109,97,103,101,45,62,105,109,97,103,101,41,0]
def c_literal_9() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_9]()))
comptime c_literal_data_10: Array[UInt8,63] = [118,107,65,108,108,111,99,97,116,101,77,101,109,111,114,121,40,103,45,62,100,101,118,105,99,101,44,32,38,97,108,108,111,99,97,116,105,111,110,44,32,78,85,76,76,44,32,38,105,109,97,103,101,45,62,109,101,109,111,114,121,41,0]
def c_literal_10() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_10]()))
comptime c_literal_data_11: Array[UInt8,61] = [118,107,66,105,110,100,73,109,97,103,101,77,101,109,111,114,121,40,103,45,62,100,101,118,105,99,101,44,32,105,109,97,103,101,45,62,105,109,97,103,101,44,32,105,109,97,103,101,45,62,109,101,109,111,114,121,44,32,48,41,0]
def c_literal_11() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_11]()))
comptime c_literal_data_12: Array[UInt8,56] = [118,107,67,114,101,97,116,101,73,109,97,103,101,86,105,101,119,40,103,45,62,100,101,118,105,99,101,44,32,38,118,105,101,119,44,32,78,85,76,76,44,32,38,105,109,97,103,101,45,62,118,105,101,119,41,0]
def c_literal_12() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_12]()))
comptime c_literal_data_13: Array[UInt8,62] = [118,107,87,97,105,116,70,111,114,70,101,110,99,101,115,40,103,45,62,100,101,118,105,99,101,44,32,49,44,32,38,103,45,62,102,101,110,99,101,44,32,86,75,95,84,82,85,69,44,32,85,73,78,84,54,52,95,77,65,88,41,0]
def c_literal_13() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_13]()))
comptime c_literal_data_14: Array[UInt8,36] = [118,107,82,101,115,101,116,67,111,109,109,97,110,100,66,117,102,102,101,114,40,103,45,62,99,111,109,109,97,110,100,44,32,48,41,0]
def c_literal_14() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_14]()))
comptime c_literal_data_15: Array[UInt8,41] = [118,107,66,101,103,105,110,67,111,109,109,97,110,100,66,117,102,102,101,114,40,103,45,62,99,111,109,109,97,110,100,44,32,38,98,101,103,105,110,41,0]
def c_literal_15() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_15]()))
comptime c_literal_data_16: Array[UInt8,31] = [118,107,69,110,100,67,111,109,109,97,110,100,66,117,102,102,101,114,40,103,45,62,99,111,109,109,97,110,100,41,0]
def c_literal_16() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_16]()))
comptime c_literal_data_17: Array[UInt8,39] = [118,107,82,101,115,101,116,70,101,110,99,101,115,40,103,45,62,100,101,118,105,99,101,44,32,49,44,32,38,103,45,62,102,101,110,99,101,41,0]
def c_literal_17() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_17]()))
comptime c_literal_data_18: Array[UInt8,14] = [118,107,81,117,101,117,101,83,117,98,109,105,116,0]
def c_literal_18() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_18]()))
comptime c_literal_data_19: Array[UInt8,60] = [118,107,67,114,101,97,116,101,82,101,110,100,101,114,80,97,115,115,40,103,45,62,100,101,118,105,99,101,44,32,38,105,110,102,111,44,32,78,85,76,76,44,32,38,103,45,62,115,104,97,100,111,119,95,112,97,115,115,41,0]
def c_literal_19() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_19]()))
comptime c_literal_data_20: Array[UInt8,59] = [118,107,67,114,101,97,116,101,82,101,110,100,101,114,80,97,115,115,40,103,45,62,100,101,118,105,99,101,44,32,38,105,110,102,111,44,32,78,85,76,76,44,32,38,103,45,62,99,111,108,111,114,95,112,97,115,115,41,0]
def c_literal_20() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_20]()))
comptime c_literal_data_21: Array[UInt8,56] = [118,107,67,114,101,97,116,101,82,101,110,100,101,114,80,97,115,115,40,103,45,62,100,101,118,105,99,101,44,38,105,110,102,111,44,78,85,76,76,44,38,103,45,62,119,97,116,101,114,95,112,97,115,115,41,0]
def c_literal_21() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_21]()))
comptime c_literal_data_22: Array[UInt8,51] = [118,107,67,114,101,97,116,101,83,104,97,100,101,114,77,111,100,117,108,101,40,103,45,62,100,101,118,105,99,101,44,32,38,109,111,100,117,108,101,44,32,78,85,76,76,44,32,38,118,41,0]
def c_literal_22() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_22]()))
comptime c_literal_data_23: Array[UInt8,23] = [102,114,97,103,109,101,110,116,32,115,104,97,100,101,114,32,109,111,100,117,108,101,0]
def c_literal_23() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_23]()))
comptime c_literal_data_24: Array[UInt8,5] = [109,97,105,110,0]
def c_literal_24() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_24]()))
comptime c_literal_data_25: Array[UInt8,18] = [103,114,97,112,104,105,99,115,32,112,105,112,101,108,105,110,101,0]
def c_literal_25() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_25]()))
comptime c_literal_data_26: Array[UInt8,28] = [118,107,68,101,118,105,99,101,87,97,105,116,73,100,108,101,40,103,45,62,100,101,118,105,99,101,41,0]
def c_literal_26() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_26]()))
comptime c_literal_data_27: Array[UInt8,56] = [118,107,67,114,101,97,116,101,70,114,97,109,101,98,117,102,102,101,114,40,103,45,62,100,101,118,105,99,101,44,32,38,102,98,44,32,78,85,76,76,44,32,38,103,45,62,99,111,108,111,114,95,102,98,41,0]
def c_literal_27() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_27]()))
comptime c_literal_data_28: Array[UInt8,59] = [118,107,67,114,101,97,116,101,70,114,97,109,101,98,117,102,102,101,114,40,103,45,62,100,101,118,105,99,101,44,38,102,98,44,78,85,76,76,44,38,103,45,62,115,99,101,110,101,95,100,101,112,116,104,95,102,98,41,0]
def c_literal_28() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_28]()))
comptime c_literal_data_29: Array[UInt8,30] = [116,101,120,116,117,114,101,32,100,101,115,99,114,105,112,116,111,114,32,97,108,108,111,99,97,116,105,111,110,0]
def c_literal_29() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_29]()))
comptime c_literal_data_30: Array[UInt8,70] = [118,107,67,114,101,97,116,101,68,101,115,99,114,105,112,116,111,114,83,101,116,76,97,121,111,117,116,40,103,45,62,100,101,118,105,99,101,44,32,38,108,97,121,111,117,116,44,32,78,85,76,76,44,32,38,103,45,62,115,101,116,95,108,97,121,111,117,116,41,0]
def c_literal_30() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_30]()))
comptime c_literal_data_31: Array[UInt8,64] = [118,107,67,114,101,97,116,101,68,101,115,99,114,105,112,116,111,114,80,111,111,108,40,103,45,62,100,101,118,105,99,101,44,32,38,112,111,111,108,44,32,78,85,76,76,44,32,38,103,45,62,100,101,115,99,114,105,112,116,111,114,115,41,0]
def c_literal_31() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_31]()))
comptime c_literal_data_32: Array[UInt8,72] = [118,107,67,114,101,97,116,101,80,105,112,101,108,105,110,101,76,97,121,111,117,116,40,103,45,62,100,101,118,105,99,101,44,32,38,112,105,112,101,108,105,110,101,44,32,78,85,76,76,44,32,38,103,45,62,112,105,112,101,108,105,110,101,95,108,97,121,111,117,116,41,0]
def c_literal_32() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_32]()))
comptime c_literal_data_33: Array[UInt8,57] = [118,107,67,114,101,97,116,101,70,114,97,109,101,98,117,102,102,101,114,40,103,45,62,100,101,118,105,99,101,44,32,38,102,98,44,32,78,85,76,76,44,32,38,103,45,62,115,104,97,100,111,119,95,102,98,41,0]
def c_literal_33() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_33]()))
comptime c_literal_data_34: Array[UInt8,63] = [118,107,67,114,101,97,116,101,83,97,109,112,108,101,114,40,103,45,62,100,101,118,105,99,101,44,32,38,115,97,109,112,108,101,114,44,32,78,85,76,76,44,32,38,103,45,62,115,104,97,100,111,119,95,115,97,109,112,108,101,114,41,0]
def c_literal_34() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_34]()))
comptime c_literal_data_35: Array[UInt8,64] = [118,107,67,114,101,97,116,101,83,97,109,112,108,101,114,40,103,45,62,100,101,118,105,99,101,44,32,38,115,97,109,112,108,101,114,44,32,78,85,76,76,44,32,38,103,45,62,116,101,120,116,117,114,101,95,115,97,109,112,108,101,114,41,0]
def c_literal_35() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_35]()))
comptime c_literal_data_36: Array[UInt8,31] = [84,111,111,32,109,97,110,121,32,83,68,76,32,86,117,108,107,97,110,32,101,120,116,101,110,115,105,111,110,115,0]
def c_literal_36() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_36]()))
comptime c_literal_data_37: Array[UInt8,28] = [86,75,95,76,65,89,69,82,95,75,72,82,79,78,79,83,95,118,97,108,105,100,97,116,105,111,110,0]
def c_literal_37() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_37]()))
comptime c_literal_data_38: Array[UInt8,19] = [77,79,74,79,95,86,75,95,86,65,76,73,68,65,84,73,79,78,0]
def c_literal_38() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_38]()))
comptime c_literal_data_39: Array[UInt8,2] = [48,0]
def c_literal_39() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_39]()))
comptime c_literal_data_40: Array[UInt8,19] = [86,75,95,69,88,84,95,100,101,98,117,103,95,117,116,105,108,115,0]
def c_literal_40() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_40]()))
comptime c_literal_data_41: Array[UInt8,11] = [65,116,108,97,115,32,77,111,106,111,0]
def c_literal_41() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_41]()))
comptime c_literal_data_42: Array[UInt8,10] = [109,111,106,111,95,103,97,109,101,0]
def c_literal_42() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_42]()))
comptime c_literal_data_43: Array[UInt8,44] = [118,107,67,114,101,97,116,101,73,110,115,116,97,110,99,101,40,38,105,110,102,111,44,32,78,85,76,76,44,32,38,103,45,62,105,110,115,116,97,110,99,101,41,0]
def c_literal_43() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_43]()))
comptime c_literal_data_44: Array[UInt8,31] = [118,107,67,114,101,97,116,101,68,101,98,117,103,85,116,105,108,115,77,101,115,115,101,110,103,101,114,69,88,84,0]
def c_literal_44() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_44]()))
comptime c_literal_data_45: Array[UInt8,35] = [86,117,108,107,97,110,32,100,101,98,117,103,32,109,101,115,115,101,110,103,101,114,32,117,110,97,118,97,105,108,97,98,108,101,0]
def c_literal_45() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_45]()))
comptime c_literal_data_46: Array[UInt8,45] = [99,114,101,97,116,101,40,103,45,62,105,110,115,116,97,110,99,101,44,32,38,100,101,98,117,103,44,32,78,85,76,76,44,32,38,103,45,62,100,101,98,117,103,41,0]
def c_literal_46() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_46]()))
comptime c_literal_data_47: Array[UInt8,54] = [118,107,69,110,117,109,101,114,97,116,101,80,104,121,115,105,99,97,108,68,101,118,105,99,101,115,40,103,45,62,105,110,115,116,97,110,99,101,44,32,38,99,111,117,110,116,44,32,78,85,76,76,41,0]
def c_literal_47() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_47]()))
comptime c_literal_data_48: Array[UInt8,45] = [78,111,32,86,117,108,107,97,110,32,100,101,118,105,99,101,32,102,111,117,110,100,59,32,105,110,115,116,97,108,108,32,97,32,86,117,108,107,97,110,32,73,67,68,0]
def c_literal_48() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_48]()))
comptime c_literal_data_49: Array[UInt8,30] = [68,101,118,105,99,101,32,108,105,115,116,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_49() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_49]()))
comptime c_literal_data_50: Array[UInt8,18] = [101,110,117,109,101,114,97,116,101,32,100,101,118,105,99,101,115,0]
def c_literal_50() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_50]()))
comptime c_literal_data_51: Array[UInt8,17] = [77,79,74,79,95,86,75,95,83,79,70,84,87,65,82,69,0]
def c_literal_51() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_51]()))
comptime c_literal_data_52: Array[UInt8,25] = [77,79,74,79,95,86,75,95,82,69,81,85,73,82,69,95,72,65,82,68,87,65,82,69,0]
def c_literal_52() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_52]()))
comptime c_literal_data_53: Array[UInt8,69] = [77,79,74,79,95,86,75,95,83,79,70,84,87,65,82,69,32,97,110,100,32,77,79,74,79,95,86,75,95,82,69,81,85,73,82,69,95,72,65,82,68,87,65,82,69,32,99,97,110,110,111,116,32,98,111,116,104,32,98,101,32,101,110,97,98,108,101,100,0]
def c_literal_53() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_53]()))
comptime c_literal_data_54: Array[UInt8,29] = [81,117,101,117,101,32,108,105,115,116,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_54() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_54]()))
comptime c_literal_data_55: Array[UInt8,127] = [78,111,32,99,111,109,112,97,116,105,98,108,101,32,104,97,114,100,119,97,114,101,32,86,117,108,107,97,110,32,71,80,85,32,105,115,32,97,99,99,101,115,115,105,98,108,101,46,32,67,104,101,99,107,32,71,80,85,32,100,101,118,105,99,101,32,97,99,99,101,115,115,32,97,110,100,32,116,104,101,32,104,111,115,116,32,86,117,108,107,97,110,32,100,114,105,118,101,114,59,32,67,80,85,32,102,97,108,108,98,97,99,107,32,105,115,32,100,105,115,97,98,108,101,100,46,0]
def c_literal_55() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_55]()))
comptime c_literal_data_56: Array[UInt8,109] = [78,111,32,99,111,109,112,97,116,105,98,108,101,32,67,80,85,32,86,117,108,107,97,110,32,100,101,118,105,99,101,32,105,115,32,97,99,99,101,115,115,105,98,108,101,46,32,73,110,115,116,97,108,108,32,97,32,110,97,116,105,118,101,32,77,101,115,97,32,108,97,118,97,112,105,112,101,32,73,67,68,32,111,114,32,117,110,115,101,116,32,77,79,74,79,95,86,75,95,83,79,70,84,87,65,82,69,46,0]
def c_literal_56() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_56]()))
comptime c_literal_data_57: Array[UInt8,60] = [78,111,32,99,111,109,112,97,116,105,98,108,101,32,86,117,108,107,97,110,32,103,114,97,112,104,105,99,115,47,112,114,101,115,101,110,116,32,113,117,101,117,101,32,111,114,32,105,109,97,103,101,32,102,111,114,109,97,116,0]
def c_literal_57() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_57]()))
comptime c_literal_data_58: Array[UInt8,13] = [77,79,74,79,95,86,75,95,77,83,65,65,0]
def c_literal_58() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_58]()))
comptime c_literal_data_59: Array[UInt8,31] = [77,79,74,79,95,86,75,95,77,83,65,65,32,109,117,115,116,32,98,101,32,49,44,32,50,32,111,114,32,52,0]
def c_literal_59() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_59]()))
comptime c_literal_data_60: Array[UInt8,177] = [118,107,71,101,116,80,104,121,115,105,99,97,108,68,101,118,105,99,101,73,109,97,103,101,70,111,114,109,97,116,80,114,111,112,101,114,116,105,101,115,40,103,45,62,112,104,121,115,105,99,97,108,44,86,75,95,70,79,82,77,65,84,95,82,56,71,56,66,56,65,56,95,85,78,79,82,77,44,32,86,75,95,73,77,65,71,69,95,84,89,80,69,95,50,68,44,86,75,95,73,77,65,71,69,95,84,73,76,73,78,71,95,79,80,84,73,77,65,76,44,86,75,95,73,77,65,71,69,95,85,83,65,71,69,95,67,79,76,79,82,95,65,84,84,65,67,72,77,69,78,84,95,66,73,84,44,48,44,38,99,111,108,111,114,95,112,114,111,112,101,114,116,105,101,115,41,0]
def c_literal_60() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_60]()))
comptime c_literal_data_61: Array[UInt8,181] = [118,107,71,101,116,80,104,121,115,105,99,97,108,68,101,118,105,99,101,73,109,97,103,101,70,111,114,109,97,116,80,114,111,112,101,114,116,105,101,115,40,103,45,62,112,104,121,115,105,99,97,108,44,86,75,95,70,79,82,77,65,84,95,68,51,50,95,83,70,76,79,65,84,44,32,86,75,95,73,77,65,71,69,95,84,89,80,69,95,50,68,44,86,75,95,73,77,65,71,69,95,84,73,76,73,78,71,95,79,80,84,73,77,65,76,44,86,75,95,73,77,65,71,69,95,85,83,65,71,69,95,68,69,80,84,72,95,83,84,69,78,67,73,76,95,65,84,84,65,67,72,77,69,78,84,95,66,73,84,44,48,44,38,100,101,112,116,104,95,112,114,111,112,101,114,116,105,101,115,41,0]
def c_literal_61() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_61]()))
comptime c_literal_data_62: Array[UInt8,17] = [86,75,95,75,72,82,95,115,119,97,112,99,104,97,105,110,0]
def c_literal_62() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_62]()))
comptime c_literal_data_63: Array[UInt8,55] = [118,107,67,114,101,97,116,101,68,101,118,105,99,101,40,103,45,62,112,104,121,115,105,99,97,108,44,32,38,100,101,118,105,99,101,44,32,78,85,76,76,44,32,38,103,45,62,100,101,118,105,99,101,41,0]
def c_literal_63() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_63]()))
comptime c_literal_data_64: Array[UInt8,16] = [77,79,74,79,95,86,75,95,80,82,79,70,73,76,69,0]
def c_literal_64() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_64]()))
comptime c_literal_data_65: Array[UInt8,21] = [77,79,74,79,95,86,75,95,80,82,69,83,69,78,84,95,83,89,78,67,0]
def c_literal_65() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_65]()))
comptime c_literal_data_66: Array[UInt8,58] = [118,107,67,114,101,97,116,101,81,117,101,114,121,80,111,111,108,40,103,45,62,100,101,118,105,99,101,44,38,113,117,101,114,105,101,115,44,78,85,76,76,44,38,103,45,62,116,105,109,101,115,116,97,109,112,115,41,0]
def c_literal_66() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_66]()))
comptime c_literal_data_67: Array[UInt8,54] = [118,107,67,114,101,97,116,101,67,111,109,109,97,110,100,80,111,111,108,40,103,45,62,100,101,118,105,99,101,44,32,38,112,111,111,108,44,32,78,85,76,76,44,32,38,103,45,62,112,111,111,108,41,0]
def c_literal_67() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_67]()))
comptime c_literal_data_68: Array[UInt8,62] = [118,107,65,108,108,111,99,97,116,101,67,111,109,109,97,110,100,66,117,102,102,101,114,115,40,103,45,62,100,101,118,105,99,101,44,32,38,97,108,108,111,99,97,116,105,111,110,44,32,38,103,45,62,99,111,109,109,97,110,100,41,0]
def c_literal_68() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_68]()))
comptime c_literal_data_69: Array[UInt8,50] = [118,107,67,114,101,97,116,101,70,101,110,99,101,40,103,45,62,100,101,118,105,99,101,44,32,38,102,101,110,99,101,44,32,78,85,76,76,44,32,38,103,45,62,102,101,110,99,101,41,0]
def c_literal_69() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_69]()))
comptime c_literal_data_70: Array[UInt8,61] = [118,107,67,114,101,97,116,101,83,101,109,97,112,104,111,114,101,40,103,45,62,100,101,118,105,99,101,44,32,38,115,101,109,97,112,104,111,114,101,44,32,78,85,76,76,44,32,38,103,45,62,97,99,113,117,105,114,101,100,41,0]
def c_literal_70() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_70]()))
comptime c_literal_data_71: Array[UInt8,32] = [118,107,68,101,115,116,114,111,121,68,101,98,117,103,85,116,105,108,115,77,101,115,115,101,110,103,101,114,69,88,84,0]
def c_literal_71() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_71]()))
comptime c_literal_data_72: Array[UInt8,26] = [73,110,118,97,108,105,100,32,119,105,110,100,111,119,32,100,105,109,101,110,115,105,111,110,115,0]
def c_literal_72() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_72]()))
comptime c_literal_data_73: Array[UInt8,27] = [71,114,97,112,104,105,99,115,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_73() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_73]()))
comptime c_literal_data_74: Array[UInt8,18] = [73,110,118,97,108,105,100,32,109,101,115,104,32,100,97,116,97,0]
def c_literal_74() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_74]()))
comptime c_literal_data_75: Array[UInt8,25] = [77,101,115,104,32,105,110,100,101,120,32,111,117,116,32,111,102,32,98,111,117,110,100,115,0]
def c_literal_75() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_75]()))
comptime c_literal_data_76: Array[UInt8,27] = [71,80,85,32,109,101,115,104,32,99,97,112,97,99,105,116,121,32,101,120,99,101,101,100,101,100,0]
def c_literal_76() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_76]()))
comptime c_literal_data_77: Array[UInt8,18] = [83,116,97,108,101,32,109,101,115,104,32,104,97,110,100,108,101,0]
def c_literal_77() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_77]()))
comptime c_literal_data_78: Array[UInt8,26] = [84,101,120,116,117,114,101,32,99,97,112,97,99,105,116,121,32,101,120,99,101,101,100,101,100,0]
def c_literal_78() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_78]()))
comptime c_literal_data_79: Array[UInt8,23] = [73,110,118,97,108,105,100,32,116,101,120,116,117,114,101,32,112,105,120,101,108,115,0]
def c_literal_79() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_79]()))
comptime c_literal_data_80: Array[UInt8,3] = [114,98,0]
def c_literal_80() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_80]()))
comptime c_literal_data_81: Array[UInt8,34] = [73,110,118,97,108,105,100,32,110,111,114,109,97,108,45,109,97,112,32,116,101,120,116,117,114,101,32,104,97,110,100,108,101,0]
def c_literal_81() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_81]()))
comptime c_literal_data_82: Array[UInt8,27] = [73,110,118,97,108,105,100,32,79,82,77,32,116,101,120,116,117,114,101,32,104,97,110,100,108,101,0]
def c_literal_82() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_82]()))
comptime c_literal_data_83: Array[UInt8,36] = [73,110,118,97,108,105,100,32,116,114,105,112,108,97,110,97,114,32,109,97,116,101,114,105,97,108,32,111,114,32,115,99,97,108,101,0]
def c_literal_83() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_83]()))
comptime c_literal_data_84: Array[UInt8,44] = [84,114,105,112,108,97,110,97,114,32,109,97,112,112,105,110,103,32,114,101,113,117,105,114,101,115,32,97,110,32,111,112,97,113,117,101,32,97,108,98,101,100,111,0]
def c_literal_84() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_84]()))
comptime c_literal_data_85: Array[UInt8,42] = [84,114,105,112,108,97,110,97,114,32,97,110,100,32,102,111,108,105,97,103,101,32,109,111,100,101,115,32,97,114,101,32,101,120,99,108,117,115,105,118,101,0]
def c_literal_85() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_85]()))
comptime c_literal_data_86: Array[UInt8,41] = [73,110,118,97,108,105,100,32,102,111,108,105,97,103,101,32,109,97,116,101,114,105,97,108,32,111,114,32,116,114,97,110,115,109,105,115,115,105,111,110,0]
def c_literal_86() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_86]()))
comptime c_literal_data_87: Array[UInt8,40] = [70,111,108,105,97,103,101,32,97,110,100,32,116,101,114,114,97,105,110,32,109,111,100,101,115,32,97,114,101,32,101,120,99,108,117,115,105,118,101,0]
def c_literal_87() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_87]()))
comptime c_literal_data_88: Array[UInt8,22] = [73,110,118,97,108,105,100,32,119,105,110,100,32,109,97,116,101,114,105,97,108,0]
def c_literal_88() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_88]()))
comptime c_literal_data_89: Array[UInt8,33] = [87,105,110,100,32,114,101,113,117,105,114,101,115,32,97,32,102,111,108,105,97,103,101,32,109,97,116,101,114,105,97,108,0]
def c_literal_89() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_89]()))
comptime c_literal_data_90: Array[UInt8,31] = [73,110,118,97,108,105,100,32,119,105,110,100,32,116,105,109,101,32,111,114,32,97,109,112,108,105,116,117,100,101,0]
def c_literal_90() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_90]()))
comptime c_literal_data_91: Array[UInt8,28] = [73,110,118,97,108,105,100,32,115,108,111,112,101,45,116,105,110,116,32,109,97,116,101,114,105,97,108,0]
def c_literal_91() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_91]()))
comptime c_literal_data_92: Array[UInt8,51] = [83,108,111,112,101,32,116,105,110,116,32,114,101,113,117,105,114,101,115,32,97,110,32,111,112,97,113,117,101,32,110,111,110,45,102,111,108,105,97,103,101,32,109,97,116,101,114,105,97,108,0]
def c_literal_92() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_92]()))
comptime c_literal_data_93: Array[UInt8,23] = [73,110,118,97,108,105,100,32,119,97,116,101,114,32,109,97,116,101,114,105,97,108,0]
def c_literal_93() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_93]()))
comptime c_literal_data_94: Array[UInt8,22] = [73,110,118,97,108,105,100,32,102,97,99,101,32,109,97,116,101,114,105,97,108,0]
def c_literal_94() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_94]()))
comptime c_literal_data_95: Array[UInt8,21] = [73,110,118,97,108,105,100,32,102,97,99,105,97,108,32,108,97,121,101,114,0]
def c_literal_95() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_95]()))
comptime c_literal_data_96: Array[UInt8,19] = [73,110,118,97,108,105,100,32,102,97,99,105,97,108,32,114,105,103,0]
def c_literal_96() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_96]()))
comptime c_literal_data_97: Array[UInt8,29] = [68,114,97,119,32,113,117,101,117,101,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_97() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_97]()))
comptime c_literal_data_98: Array[UInt8,34] = [115,104,97,100,111,119,95,98,101,103,105,110,32,109,117,115,116,32,115,116,97,114,116,32,116,104,101,32,102,114,97,109,101,0]
def c_literal_98() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_98]()))
comptime c_literal_data_99: Array[UInt8,25] = [83,116,97,108,101,32,115,104,97,100,111,119,32,109,101,115,104,32,104,97,110,100,108,101,0]
def c_literal_99() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_99]()))
comptime c_literal_data_100: Array[UInt8,23] = [73,110,118,97,108,105,100,32,115,104,97,100,111,119,32,116,101,120,116,117,114,101,0]
def c_literal_100() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_100]()))
comptime c_literal_data_101: Array[UInt8,29] = [73,110,118,97,108,105,100,32,101,110,118,105,114,111,110,109,101,110,116,32,108,105,103,104,116,105,110,103,0]
def c_literal_101() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_101]()))
comptime c_literal_data_102: Array[UInt8,29] = [73,110,118,97,108,105,100,32,99,105,110,101,109,97,116,105,99,32,97,116,109,111,115,112,104,101,114,101,0]
def c_literal_102() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_102]()))
comptime c_literal_data_103: Array[UInt8,23] = [73,110,118,97,108,105,100,32,116,101,120,116,117,114,101,32,104,97,110,100,108,101,0]
def c_literal_103() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_103]()))
comptime c_literal_data_104: Array[UInt8,35] = [73,110,99,111,109,112,97,116,105,98,108,101,32,109,111,114,112,104,32,109,101,115,104,101,115,32,111,114,32,98,108,101,110,100,0]
def c_literal_104() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_104]()))
comptime c_literal_data_105: Array[UInt8,39] = [73,110,99,111,109,112,97,116,105,98,108,101,32,99,114,111,115,115,102,97,100,101,32,109,101,115,104,101,115,32,111,114,32,98,108,101,110,100,0]
def c_literal_105() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_105]()))
comptime c_literal_data_106: Array[UInt8,26] = [79,118,101,114,108,97,121,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_106() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_106]()))
comptime c_literal_data_107: Array[UInt8,19] = [73,110,118,97,108,105,100,32,102,111,110,116,32,97,116,108,97,115,0]
def c_literal_107() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_107]()))
comptime c_literal_data_108: Array[UInt8,19] = [73,110,118,97,108,105,100,32,116,101,120,116,32,115,99,97,108,101,0]
def c_literal_108() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_108]()))
comptime c_literal_data_109: Array[UInt8,42] = [115,104,97,100,111,119,95,98,101,103,105,110,32,109,117,115,116,32,115,116,97,114,116,32,101,97,99,104,32,86,117,108,107,97,110,32,102,114,97,109,101,0]
def c_literal_109() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_109]()))
comptime c_literal_data_110: Array[UInt8,30] = [82,101,108,101,97,115,101,100,32,109,101,115,104,32,105,110,32,115,104,97,100,111,119,32,113,117,101,117,101,0]
def c_literal_110() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_110]()))
comptime c_literal_data_111: Array[UInt8,28] = [82,101,108,101,97,115,101,100,32,109,101,115,104,32,105,110,32,100,114,97,119,32,113,117,101,117,101,0]
def c_literal_111() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_111]()))
comptime c_literal_data_112: Array[UInt8,48] = [86,117,108,107,97,110,32,118,97,108,105,100,97,116,105,111,110,32,114,101,112,111,114,116,101,100,32,97,110,32,101,114,114,111,114,59,32,115,101,101,32,115,116,100,101,114,114,0]
def c_literal_112() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_112]()))
comptime c_literal_data_113: Array[UInt8,111] = [118,107,71,101,116,81,117,101,114,121,80,111,111,108,82,101,115,117,108,116,115,40,103,45,62,100,101,118,105,99,101,44,103,45,62,116,105,109,101,115,116,97,109,112,115,44,48,44,50,44,115,105,122,101,111,102,40,116,105,99,107,115,41,44,116,105,99,107,115,44,115,105,122,101,111,102,40,117,105,110,116,54,52,95,116,41,44,86,75,95,81,85,69,82,89,95,82,69,83,85,76,84,95,54,52,95,66,73,84,41,0]
def c_literal_113() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_113]()))
comptime c_literal_data_114: Array[UInt8,74] = [118,107,71,101,116,80,104,121,115,105,99,97,108,68,101,118,105,99,101,83,117,114,102,97,99,101,67,97,112,97,98,105,108,105,116,105,101,115,75,72,82,40,103,45,62,112,104,121,115,105,99,97,108,44,32,103,45,62,115,117,114,102,97,99,101,44,32,38,99,97,112,115,41,0]
def c_literal_114() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_114]()))
comptime c_literal_data_115: Array[UInt8,47] = [83,117,114,102,97,99,101,32,100,111,101,115,32,110,111,116,32,115,117,112,112,111,114,116,32,116,114,97,110,115,102,101,114,32,112,114,101,115,101,110,116,97,116,105,111,110,0]
def c_literal_115() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_115]()))
comptime c_literal_data_116: Array[UInt8,76] = [118,107,71,101,116,80,104,121,115,105,99,97,108,68,101,118,105,99,101,83,117,114,102,97,99,101,70,111,114,109,97,116,115,75,72,82,40,103,45,62,112,104,121,115,105,99,97,108,44,32,103,45,62,115,117,114,102,97,99,101,44,32,38,99,111,117,110,116,44,32,78,85,76,76,41,0]
def c_literal_116() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_116]()))
comptime c_literal_data_117: Array[UInt8,23] = [83,117,114,102,97,99,101,32,104,97,115,32,110,111,32,102,111,114,109,97,116,115,0]
def c_literal_117() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_117]()))
comptime c_literal_data_118: Array[UInt8,33] = [83,117,114,102,97,99,101,32,102,111,114,109,97,116,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_118() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_118]()))
comptime c_literal_data_119: Array[UInt8,16] = [115,117,114,102,97,99,101,32,102,111,114,109,97,116,115,0]
def c_literal_119() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_119]()))
comptime c_literal_data_120: Array[UInt8,52] = [83,117,114,102,97,99,101,32,114,101,113,117,105,114,101,115,32,97,110,32,117,110,115,117,112,112,111,114,116,101,100,32,112,114,101,115,101,110,116,97,116,105,111,110,32,102,111,114,109,97,116,0]
def c_literal_120() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_120]()))
comptime c_literal_data_121: Array[UInt8,21] = [77,79,74,79,95,86,75,95,80,82,69,83,69,78,84,95,77,79,68,69,0]
def c_literal_121() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_121]()))
comptime c_literal_data_122: Array[UInt8,5] = [102,105,102,111,0]
def c_literal_122() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_122]()))
comptime c_literal_data_123: Array[UInt8,8] = [109,97,105,108,98,111,120,0]
def c_literal_123() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_123]()))
comptime c_literal_data_124: Array[UInt8,45] = [77,79,74,79,95,86,75,95,80,82,69,83,69,78,84,95,77,79,68,69,32,109,117,115,116,32,98,101,32,102,105,102,111,32,111,114,32,109,97,105,108,98,111,120,0]
def c_literal_124() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_124]()))
comptime c_literal_data_125: Array[UInt8,83] = [118,107,71,101,116,80,104,121,115,105,99,97,108,68,101,118,105,99,101,83,117,114,102,97,99,101,80,114,101,115,101,110,116,77,111,100,101,115,75,72,82,40,103,45,62,112,104,121,115,105,99,97,108,44,103,45,62,115,117,114,102,97,99,101,44,38,109,111,100,101,95,99,111,117,110,116,44,78,85,76,76,41,0]
def c_literal_125() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_125]()))
comptime c_literal_data_126: Array[UInt8,31] = [80,114,101,115,101,110,116,32,109,111,100,101,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_126() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_126]()))
comptime c_literal_data_127: Array[UInt8,22] = [115,117,114,102,97,99,101,32,112,114,101,115,101,110,116,32,109,111,100,101,115,0]
def c_literal_127() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_127]()))
comptime c_literal_data_128: Array[UInt8,20] = [77,79,74,79,95,86,75,95,83,87,65,80,95,73,77,65,71,69,83,0]
def c_literal_128() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_128]()))
comptime c_literal_data_129: Array[UInt8,38] = [77,79,74,79,95,86,75,95,83,87,65,80,95,73,77,65,71,69,83,32,109,117,115,116,32,98,101,32,50,44,32,51,32,111,114,32,52,0]
def c_literal_129() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_129]()))
comptime c_literal_data_130: Array[UInt8,59] = [118,107,67,114,101,97,116,101,83,119,97,112,99,104,97,105,110,75,72,82,40,103,45,62,100,101,118,105,99,101,44,32,38,105,110,102,111,44,32,78,85,76,76,44,32,38,114,101,112,108,97,99,101,109,101,110,116,41,0]
def c_literal_130() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_130]()))
comptime c_literal_data_131: Array[UInt8,71] = [118,107,71,101,116,83,119,97,112,99,104,97,105,110,73,109,97,103,101,115,75,72,82,40,103,45,62,100,101,118,105,99,101,44,32,103,45,62,115,119,97,112,99,104,97,105,110,44,32,38,103,45,62,115,119,97,112,95,99,111,117,110,116,44,32,78,85,76,76,41,0]
def c_literal_131() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_131]()))
comptime c_literal_data_132: Array[UInt8,34] = [83,119,97,112,99,104,97,105,110,32,105,109,97,103,101,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_132() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_132]()))
comptime c_literal_data_133: Array[UInt8,81] = [118,107,71,101,116,83,119,97,112,99,104,97,105,110,73,109,97,103,101,115,75,72,82,40,103,45,62,100,101,118,105,99,101,44,32,103,45,62,115,119,97,112,99,104,97,105,110,44,32,38,103,45,62,115,119,97,112,95,99,111,117,110,116,44,32,103,45,62,115,119,97,112,95,105,109,97,103,101,115,41,0]
def c_literal_133() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_133]()))
comptime c_literal_data_134: Array[UInt8,41] = [80,114,101,115,101,110,116,97,116,105,111,110,32,115,101,109,97,112,104,111,114,101,32,97,108,108,111,99,97,116,105,111,110,32,102,97,105,108,101,100,0]
def c_literal_134() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_134]()))
comptime c_literal_data_135: Array[UInt8,68] = [118,107,67,114,101,97,116,101,83,101,109,97,112,104,111,114,101,40,103,45,62,100,101,118,105,99,101,44,32,38,115,101,109,97,112,104,111,114,101,44,32,78,85,76,76,44,32,38,103,45,62,112,114,101,115,101,110,116,95,100,111,110,101,91,105,93,41,0]
def c_literal_135() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_135]()))
comptime c_literal_data_136: Array[UInt8,35] = [67,97,110,110,111,116,32,115,110,97,112,115,104,111,116,32,97,32,109,105,110,105,109,105,122,101,100,32,119,105,110,100,111,119,0]
def c_literal_136() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_136]()))
comptime c_literal_data_137: Array[UInt8,3] = [119,98,0]
def c_literal_137() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_137]()))
comptime c_literal_data_138: Array[UInt8,40] = [86,117,108,107,97,110,32,118,97,108,105,100,97,116,105,111,110,32,101,114,114,111,114,32,100,117,114,105,110,103,32,115,110,97,112,115,104,111,116,0]
def c_literal_138() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_138]()))
comptime c_literal_data_139: Array[UInt8,58] = [118,107,87,97,105,116,70,111,114,70,101,110,99,101,115,40,103,45,62,100,101,118,105,99,101,44,49,44,38,103,45,62,102,101,110,99,101,44,86,75,95,84,82,85,69,44,85,73,78,84,54,52,95,77,65,88,41,0]
def c_literal_139() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_139]()))
comptime c_literal_data_140: Array[UInt8,24] = [97,99,113,117,105,114,101,32,115,119,97,112,99,104,97,105,110,32,105,109,97,103,101,0]
def c_literal_140() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_140]()))
comptime c_literal_data_141: Array[UInt8,18] = [112,114,101,115,101,110,116,32,115,119,97,112,99,104,97,105,110,0]
def c_literal_141() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_141]()))
comptime c_literal_data_142: Array[UInt8,44] = [86,117,108,107,97,110,32,118,97,108,105,100,97,116,105,111,110,32,101,114,114,111,114,32,100,117,114,105,110,103,32,112,114,101,115,101,110,116,97,116,105,111,110,0]
def c_literal_142() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_142]()))
comptime c_literal_data_143: Array[UInt8,9] = [104,101,97,100,108,101,115,115,0]
def c_literal_143() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_143]()))
comptime c_literal_data_144: Array[UInt8,26] = [73,110,118,97,108,105,100,32,114,101,115,105,122,101,32,100,105,109,101,110,115,105,111,110,115,0]
def c_literal_144() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_144]()))
comptime c_literal_data_145: Array[UInt8,33] = [83,68,76,95,86,73,68,69,79,95,83,89,78,67,95,87,73,78,68,79,87,95,79,80,69,82,65,84,73,79,78,83,0]
def c_literal_145() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_145]()))
comptime c_literal_data_146: Array[UInt8,2] = [49,0]
def c_literal_146() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_146]()))
comptime c_literal_data_147: Array[UInt8,29] = [70,117,108,108,115,99,114,101,101,110,32,114,101,113,117,105,114,101,115,32,97,32,119,105,110,100,111,119,0]
def c_literal_147() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_147]()))
comptime c_literal_data_148: Array[UInt8,19] = [65,116,108,97,115,32,97,115,115,101,116,32,114,101,97,100,101,114,0]
def c_literal_148() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_148]()))
comptime c_literal_data_149: Array[UInt8,33] = [65,117,100,105,111,32,105,110,105,116,105,97,108,105,122,97,116,105,111,110,32,102,97,105,108,101,100,58,32,37,115,10,0]
def c_literal_149() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_149]()))
comptime c_literal_data_150: Array[UInt8,25] = [65,117,100,105,111,32,100,101,118,105,99,101,32,102,97,105,108,101,100,58,32,37,115,10,0]
def c_literal_150() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_150]()))
comptime c_literal_data_167: Array[UInt8,28] = [109,111,106,111,45,103,97,109,101,45,101,110,103,105,110,101,46,114,117,110,116,105,109,101,46,118,49,0]
def c_literal_167() -> UInt64:
    return c_address(Pointer(to=global_constant[c_literal_data_167]()))
