"""Fixed-step animation states, interruption-safe fades, events and root motion."""
from std.math import isfinite,floor
from .skeletal import Skeleton,AnimationClip,blend_pose
from .transform3d import Transform3D
from .math3d import Vec3

comptime ANIM_IDLE=0
comptime ANIM_WALK=1
comptime ANIM_RUN=2
comptime ANIM_JUMP=3
comptime ANIM_FALL=4

@fieldwise_init
struct AnimationEvent(Copyable,Movable):
    var state: Int
    var time: Float64
    var name: String

struct AnimationState3D(Copyable,Movable):
    var clip: AnimationClip
    var looping: Bool
    var speed: Float64
    var root: Int
    def __init__(out self,var clip: AnimationClip,looping: Bool=True,speed: Float64=1,root: Int=-1) raises:
        if not isfinite(speed) or speed<=0:raise Error("Invalid animation state speed")
        self.clip=clip^
        self.looping=looping
        self.speed=speed
        self.root=root

struct Animator3D:
    var states: List[AnimationState3D]
    var events: List[AnimationEvent]
    var fired: List[String]
    var current: Int
    var clock: Float64
    var fade_clock: Float64
    var fade_duration: Float64
    var source: List[Transform3D]
    var pose: List[Transform3D]
    var root_delta: Vec3
    def __init__(out self):
        self.states=List[AnimationState3D]()
        self.events=List[AnimationEvent]()
        self.fired=List[String]()
        self.current=-1
        self.clock=0
        self.fade_clock=0
        self.fade_duration=0
        self.source=List[Transform3D]()
        self.pose=List[Transform3D]()
        self.root_delta=Vec3(0,0,0)
    def add(mut self,var state: AnimationState3D) raises -> Int:
        if len(self.states)>=128:raise Error("Animation state limit exceeded")
        self.states.append(state^)
        return len(self.states)-1
    def event(mut self,state: Int,time: Float64,name: String) raises:
        if state<0 or state>=len(self.states) or not isfinite(time) or time<0 or time>self.states[state].clip.duration or name.byte_length()==0:raise Error("Invalid animation event")
        if len(self.events)>=4096:raise Error("Animation event limit exceeded")
        self.events.append(AnimationEvent(state,time,name))
    def transition(mut self,skeleton: Skeleton,state: Int,fade: Float64=.15) raises:
        if state<0 or state>=len(self.states) or fade<0 or not isfinite(fade):raise Error("Invalid animation transition")
        if state==self.current:return
        var next=self.states[state].clip.sample(skeleton,0,self.states[state].looping)
        var root=self.states[state].root
        if root>=0:
            if root>=len(next):raise Error("Animation root outside skeleton")
            next[root].position=skeleton.joints[root].bind.position
        self.source=self.pose.copy() if self.current>=0 else next.copy()
        self.pose=next^
        self.fade_clock=0
        self.fade_duration=fade if self.current>=0 else 0.0
        if self.fade_duration>0:self.pose=self.source.copy()
        self.current=state
        self.clock=0
        self.root_delta=Vec3(0,0,0)
        self.fired.clear()
    def update(mut self,skeleton: Skeleton,dt: Float64) raises:
        if self.current<0 or dt<0 or dt>.25 or not isfinite(dt):raise Error("Animation timestep must be in [0,0.25]")
        ref state=self.states[self.current]
        var before=self.clock
        var after=before+dt*state.speed
        var duration=state.clip.duration
        var cycles=0.0
        var first=self.clock
        var last: Float64
        if state.looping and duration>0:
            cycles=floor(after/duration)
            if cycles>1024:raise Error("Animation loop budget exceeded")
            last=after-cycles*duration
        else:last=min(after,duration)
        var next=state.clip.sample(skeleton,last,False)
        self.root_delta=Vec3(0,0,0)
        if state.root>=0:
            if state.root>=len(next):raise Error("Animation root outside skeleton")
            var start=state.clip.sample(skeleton,first,False)
            self.root_delta=next[state.root].position-start[state.root].position
            if cycles>0:
                var end_pose=state.clip.sample(skeleton,duration,False)
                var begin_pose=state.clip.sample(skeleton,0,False)
                self.root_delta=self.root_delta+(end_pose[state.root].position-begin_pose[state.root].position)*cycles
            # Controller consumes translation; the rendered pose stays in place.
            next[state.root].position=skeleton.joints[state.root].bind.position
        self.fired.clear()
        for event in self.events:
            if event.state!=self.current:continue
            var occurrences=0
            if cycles==0:
                if event.time>first and event.time<=last:occurrences=1
            else:
                occurrences=Int(cycles)-1
                if event.time>first:occurrences+=1
                if event.time<=last:occurrences+=1
            if len(self.fired)+occurrences>4096:raise Error("Animation event delivery budget exceeded")
            for _ in range(occurrences):self.fired.append(event.name)
        self.clock=last
        self.fade_clock+=dt
        if self.fade_duration>0 and self.fade_clock<self.fade_duration:self.pose=blend_pose(self.source,next,self.fade_clock/self.fade_duration)
        else:self.pose=next^
    @staticmethod
    def locomotion(grounded: Bool,vertical_speed: Float64,speed: Float64,running: Bool=False) -> Int:
        if not grounded:return ANIM_JUMP if vertical_speed>0 else ANIM_FALL
        if speed<.05:return ANIM_IDLE
        return ANIM_RUN if running else ANIM_WALK
