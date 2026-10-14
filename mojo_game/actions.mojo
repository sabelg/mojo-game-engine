"""Named, remappable keyboard and controller actions with focus suppression."""
from std.collections import Dict
from std.collections import Array
from std.ffi import external_call
from .input import Input

struct ControllerState(Copyable,Movable):
    var connected: Bool
    var held: UInt32
    var presses: UInt32
    var axes: Array[Float64,4]
    def __init__(out self):
        self.connected=False
        self.held=0
        self.presses=0
        self.axes=Array[Float64,4](fill=0)
    def poll(mut self,focused: Bool=True):
        var previous=self.held
        self.held=external_call["mg_pad_poll",UInt32](Int32(focused))
        self.connected=external_call["mg_pad_connected",Int32]()!=0
        self.presses=self.held&~previous
        for axis in range(4):self.axes[axis]=external_call["mg_pad_axis",Float64](Int32(axis))

@fieldwise_init
struct AxisBinding(ImplicitlyCopyable,Movable):
    var negative: Int
    var positive: Int
    var pad_axis: Int
    var invert: Bool

struct ActionMap:
    var buttons: Dict[String,Int]
    var axes: Dict[String,AxisBinding]
    var pad_buttons: Dict[String,Int]
    def __init__(out self):
        self.buttons=Dict[String,Int]()
        self.axes=Dict[String,AxisBinding]()
        self.pad_buttons=Dict[String,Int]()
    def button(mut self,name: String,scan: Int,pad_button: Int=-1) raises:
        if name.byte_length()==0 or scan<0 or scan>=512 or pad_button < -1 or pad_button>=21 or len(self.buttons)>=128 and name not in self.buttons:raise Error("Invalid action binding")
        self.buttons[name]=scan
        self.pad_buttons[name]=pad_button
    def axis(mut self,name: String,negative: Int,positive: Int,pad_axis: Int=-1,invert: Bool=False) raises:
        if name.byte_length()==0 or negative<0 or negative>=512 or positive<0 or positive>=512 or pad_axis < -1 or pad_axis>=4 or len(self.axes)>=128 and name not in self.axes:raise Error("Invalid axis binding")
        self.axes[name]=AxisBinding(negative,positive,pad_axis,invert)
    def held(self,input: Input,name: String,pad: ControllerState=ControllerState()) raises -> Bool:
        if name not in self.buttons:raise Error("Unknown button action: "+name)
        if input.focus_lost:return False
        var button=self.pad_buttons.get(name,-1)
        return input.down(self.buttons[name]) or pad.connected and button>=0 and (pad.held&(UInt32(1)<<UInt32(button)))!=0
    def pressed(self,input: Input,name: String,pad: ControllerState=ControllerState()) raises -> Bool:
        if name not in self.buttons:raise Error("Unknown button action: "+name)
        if input.focus_lost:return False
        var button=self.pad_buttons.get(name,-1)
        return input.pressed(self.buttons[name]) or pad.connected and button>=0 and (pad.presses&(UInt32(1)<<UInt32(button)))!=0
    def value(self,input: Input,name: String,pad: ControllerState=ControllerState()) raises -> Float64:
        if name not in self.axes:raise Error("Unknown axis action: "+name)
        if input.focus_lost:return 0
        var binding=self.axes[name]
        var keyboard=input.axis(binding.negative,binding.positive)
        var controller=pad.axes[binding.pad_axis]*(Float64(-1) if binding.invert else Float64(1)) if pad.connected and binding.pad_axis>=0 else Float64(0)
        return keyboard if abs(keyboard)>=abs(controller) else controller
