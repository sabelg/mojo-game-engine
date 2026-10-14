"""Animation transitions/events/root loops, camera obstruction and tiled routes."""
from std.testing import assert_true,assert_equal,assert_raises
from mojo_game import Vec3,Mat4,Transform3D,Skeleton,Joint,AnimationClip,PoseTrack,PoseKey,CollisionWorld3D,CollisionBox,Bounds3D,Input,CharacterController3D
from mojo_game.animator3d import Animator3D,AnimationState3D
from mojo_game.camera3d import ThirdPersonCamera
from mojo_game.actions import ActionMap,ControllerState
from mojo_game.navigation3d import Navigation3D,PathFollower3D

def main() raises:
    var skeleton=Skeleton()
    skeleton.joints.append(Joint(-1,Transform3D(),Mat4()))
    var walking=AnimationClip()
    var track=PoseTrack(0,0)
    track.keys.append(PoseKey(0,0,0,0,0))
    track.keys.append(PoseKey(1,2,0,0,0))
    walking.tracks.append(track^)
    walking.duration=1
    var animator=Animator3D()
    _=animator.add(AnimationState3D(walking.copy(),root=0))
    _=animator.add(AnimationState3D(walking.copy(),False))
    animator.event(0,.2,"step")
    animator.event(0,.9,"step")
    animator.transition(skeleton,0)
    var traveled: Float64=0
    var fired=0
    for _ in range(10):
        animator.update(skeleton,.25)
        traveled+=animator.root_delta.x
        fired+=len(animator.fired)
        assert_equal(animator.pose[0].position.x,0.0)
    assert_true(abs(traveled-5)<1e-8)
    assert_equal(fired,5)
    animator.transition(skeleton,1,.5)
    animator.update(skeleton,.1)
    var blended=animator.pose[0].position.x
    assert_true(blended>0 and blended<.2)
    animator.transition(skeleton,0,.5)
    assert_equal(animator.pose[0].position.x,blended)
    with assert_raises():animator.update(skeleton,1)
    var actions=ActionMap()
    actions.axis("move",4,7)
    actions.button("jump",44)
    var input=Input()
    input.key(7,True,False);input.key(44,True,False)
    assert_equal(actions.value(input,"move"),1.0)
    assert_true(actions.pressed(input,"jump"))
    var pad=ControllerState()
    pad.connected=True
    pad.held=1;pad.presses=1;pad.axes[0]=-.7
    actions.axis("move",4,7,0)
    actions.button("jump",44,0)
    input.key(7,False);input.key(44,False);input.clear_edges()
    assert_equal(actions.value(input,"move",pad),-.7)
    assert_true(actions.pressed(input,"jump",pad))
    input.lose_focus()
    assert_equal(actions.value(input,"move"),0.0)
    assert_true(not actions.pressed(input,"jump"))
    assert_equal(actions.value(input,"move",pad),0.0)
    assert_true(not actions.held(input,"jump",pad))
    var collision=CollisionWorld3D()
    collision.boxes.append(CollisionBox(Bounds3D(Vec3(-10,-1,-10),Vec3(10,0,10))))
    collision.boxes.append(CollisionBox(Bounds3D(Vec3(-2,0,2),Vec3(2,4,2.2))))
    var rooted=CharacterController3D(Vec3(0,0,0))
    rooted.step(collision,Vec3(0,0,0),.01)
    rooted.step_root_motion(collision,Vec3(0,0,20),Transform3D().rotation,.1)
    assert_true(rooted.position.z<1.66)
    var camera=ThirdPersonCamera()
    camera.pitch=0
    camera.update(collision,Vec3(0,0,0),1.0/60)
    assert_true(camera.position.z<1.81)
    camera.orbit(1.57079632679,0)
    camera.update(collision,Vec3(0,0,0),.1)
    assert_true(camera.actual_distance<camera.distance)
    var nav=Navigation3D(1,4,4)
    for x in range(2):nav.build(collision,x,0,10,-5)
    # The wall blocks direct travel; a resident tile supplies an outer route.
    var route=nav.path(collision,Vec3(.5,0,.5),Vec3(4.7,0,3.7))
    assert_true(len(route)>5)
    var follower=PathFollower3D()
    follower.route=route^
    var character=CharacterController3D(Vec3(.5,0,.5))
    for _ in range(600):
        var velocity=follower.follow(character.position,2,1.0/60)
        character.step(collision,velocity,1.0/60)
    assert_true((character.position-Vec3(4.7,0,3.7)).length()<.1)
    nav.remove(1,0)
    assert_equal(len(nav.path(collision,Vec3(.5,0,.5),Vec3(4.7,0,3.7))),0)
    print("Gameplay services passed: interrupted fades, loop events/root motion, named input, camera obstruction, tile eviction and capsule path following")
