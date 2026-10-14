"""Actual GPU box patches vs independent corner/constructive reference."""
from std.testing import assert_equal,assert_true
from mojo_game import RigidBody3D,MassProperties3D,Vec3
from experimental.physics_gpu.box_box import GpuBoxBoxDetection,float_bits
from experimental.physics_gpu.lifecycle import BodyCommand
from experimental.physics_gpu.collision import BoxCommand

def smoke() raises:
    var w=GpuBoxBoxDetection();var a=RigidBody3D(MassProperties3D.fixed());var b=RigidBody3D(MassProperties3D.fixed(),position=Vec3(0,0,1.5))
    var handles=w.world.bodies.submit([BodyCommand.create(a),BodyCommand.create(b)])
    _=w.world.submit_boxes([BoxCommand.attach(handles[0],Vec3(1,.6,.75)),BoxCommand.attach(handles[1],Vec3(1,.6,.75))])
    var f=w.detect();assert_equal(len(f.patches),1);assert_equal(len(f.patches[0].points),4);assert_equal(f.patches[0].separation,Float64(0));assert_equal(len(f.legacy.contacts),0)
    assert_equal(f.patches[0].normal.z,Float64(1));w.close();print("First actual GPU box/box touching face patch: 4 points, +Z normal, zero separation; legacy API remains empty")
def main() raises:
    smoke();analytic();edges();seeded_perturbations();metamorphic();lifecycle();invalid_and_extremes();capacity_and_rollback();legacy_mixed();general_rotations();tangencies_and_nine();candidate_rejection();midpoint_unique()

from std.collections import List
from std.math import sqrt
from mojo_game import Quaternion
from experimental.physics_gpu.collision import ShapeHandle
from experimental.physics_gpu.lifecycle import BodyHandle
from experimental.physics_gpu.box_oracle import OracleBox,box_axes,box_center
from experimental.physics_gpu.box_box_reference import ReferenceBox,reference_sat,reference_patch,reference_edge,scalar_dot,face,direction,scalar_cross
from experimental.physics_gpu.box_box_kernels import EPS


def add(mut w: GpuBoxBoxDetection,p: Vec3,half: Vec3,q: Quaternion=Quaternion(),offset: Vec3=Vec3(0,0,0),local: Quaternion=Quaternion()) raises -> OracleBox:
    var b=RigidBody3D(MassProperties3D.fixed(),position=p,orientation=q)
    var h=w.world.bodies.submit([BodyCommand.create(b)]);var shape=w.world.submit_boxes([BoxCommand.attach(h[0],half,offset,local)])
    return OracleBox(shape[0],h[0],1,b,half,offset,local)
def near(a: Float64,b: Float64,tolerance: Float64=1e-10) raises:
    if abs(a-b)>tolerance*(1+abs(b)):print("NEAR FAILED",a,b,tolerance)
    assert_true(abs(a-b)<=tolerance*(1+abs(b)))
def vector(a: Vec3,b: Vec3,tolerance: Float64=1e-10) raises:
    near(a.x,b.x,tolerance);near(a.y,b.y,tolerance);near(a.z,b.z,tolerance)
def input_boxes(mut w: GpuBoxBoxDetection,models: List[OracleBox]) raises -> List[ReferenceBox]:
    var result=List[ReferenceBox]()
    for _ in range(64):result.append(ReferenceBox(Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0),Vec3(0,0,0)))
    with w.world._bounds.map_to_host() as values:
        for model in models:
            var k=1+Int(model.shape.slot)*22;var expected=box_axes(model);var center=Vec3(values[k],values[k+1],values[k+2])
            var x=Vec3(values[k+13],values[k+14],values[k+15]);var y=Vec3(values[k+16],values[k+17],values[k+18]);var z=Vec3(values[k+19],values[k+20],values[k+21])
            vector(center,box_center(model),1e-12);vector(x,expected[0],32*EPS);vector(y,expected[1],32*EPS);vector(z,expected[2],32*EPS)
            result[Int(model.shape.slot)]=ReferenceBox(center,x*model.half_extents.x,y*model.half_extents.y,z*model.half_extents.z)
    return result^
def on_box(p: Vec3,b: ReferenceBox,origin: Vec3,tolerance: Float64) raises:
    var relative=p-(b.center-origin);var surface=False
    for i in range(3):
        var n=face(b,i);var extent=abs(scalar_dot(n,b.edge(i)));var coordinate=abs(scalar_dot(n,relative))
        assert_true(coordinate<=extent+tolerance)
        if abs(coordinate-extent)<=tolerance:surface=True
    assert_true(surface)
def compare(mut w: GpuBoxBoxDetection,models: List[OracleBox],expected_pairs: Int=-1,expected_points: Int=-1) raises:
    var frame=w.detect();candidate_guards(w);var boxes=input_boxes(w,models);var hits=0
    for i in range(len(models)):
        for j in range(i+1,len(models)):
            var a=boxes[Int(models[i].shape.slot)];var b=boxes[Int(models[j].shape.slot)];var expected=reference_sat(a,b)
            if expected[0]:
                hits+=1;var found=0
                for index in range(len(frame.patches)):
                    var key=frame.patches[index].key
                    if key.a.slot==min(models[i].shape.slot,models[j].shape.slot) and key.b.slot==max(models[i].shape.slot,models[j].shape.slot):found+=1
                assert_equal(found,1)
    assert_equal(len(frame.patches),hits)
    if expected_pairs>=0:assert_equal(len(frame.patches),expected_pairs)
    var previous_pair=Int(-1)
    for patch_index in range(len(frame.patches)):
        ref patch=frame.patches[patch_index]
        var pair_order=Int(patch.key.a.slot)*64+Int(patch.key.b.slot)
        assert_true(patch.key.a.slot<patch.key.b.slot and pair_order>previous_pair);previous_pair=pair_order
        for model in models:
            if model.shape.slot==patch.key.a.slot or model.shape.slot==patch.key.b.slot:
                var first=model.shape.slot==patch.key.a.slot
                assert_equal(model.shape.owner,patch.key.a.owner if first else patch.key.b.owner)
                assert_equal(model.shape.generation,patch.key.a.generation if first else patch.key.b.generation)
                assert_equal(model.revision,patch.key.revision_a if first else patch.key.revision_b)
                var body=patch.key.body_a if first else patch.key.body_b
                assert_equal(model.body_handle.slot,body.slot);assert_equal(model.body_handle.generation,body.generation);assert_equal(model.body_handle.owner,body.owner)
        var a=boxes[Int(patch.key.a.slot)];var b=boxes[Int(patch.key.b.slot)];var expected=reference_sat(a,b)
        assert_true(expected[0]);near(patch.separation,expected[1],1e-10)
        near(scalar_dot(patch.normal,patch.normal),1,1e-12)
        var scale=max(1.0,max(max(abs(a.e0.x),max(abs(a.e0.y),abs(a.e0.z))),max(abs(b.e0.x),max(abs(b.e0.y),abs(b.e0.z)))))
        scale=max(scale,max(max(abs(a.e1.x),max(abs(a.e1.y),abs(a.e1.z))),max(abs(a.e2.x),max(abs(a.e2.y),abs(a.e2.z)))))
        scale=max(scale,max(max(abs(b.e1.x),max(abs(b.e1.y),abs(b.e1.z))),max(abs(b.e2.x),max(abs(b.e2.y),abs(b.e2.z)))))
        var resolution=32*EPS*scale;var tolerance=512*EPS*scale
        if expected_points>=0:assert_equal(len(patch.points),expected_points)
        assert_true(len(patch.points)>=1 and len(patch.points)<=9);assert_true(patch.depth()>=0)
        for p in patch.points:
            vector(p.witness_b_relative-p.witness_a_relative,patch.normal*p.separation,1e-10)
            on_box(p.witness_a_relative,a,a.center,tolerance);on_box(p.witness_b_relative,b,a.center,tolerance)
            assert_true(p.separation<=0);assert_true(p.depth()>=0);assert_equal(p.depth(),-p.separation)
        for i in range(1,len(patch.points)):
            var previous=(patch.points[i-1].witness_a_relative+patch.points[i-1].witness_b_relative)*.5
            var current=(patch.points[i].witness_a_relative+patch.points[i].witness_b_relative)*.5
            assert_true(current.x>previous.x or (current.x==previous.x and current.y>previous.y) or (current.x==previous.x and current.y==previous.y and current.z>previous.z))
        for i in range(len(patch.points)):
            for j in range(i+1,len(patch.points)):
                var a_mid=(patch.points[i].witness_a_relative+patch.points[i].witness_b_relative)*.5
                var b_mid=(patch.points[j].witness_a_relative+patch.points[j].witness_b_relative)*.5;var d=a_mid-b_mid
                assert_true(max(abs(d.x),max(abs(d.y),abs(d.z)))>resolution)
        if patch.feature<6:
            var reference=reference_patch(a,b,Int(patch.feature),resolution)
            var condition=intersection_condition(a,b)
            var construction_bound=tolerance/max(EPS,condition)
            # Missing and extra vertex distances are measured separately. A
            # count alone cannot conceal a duplicate replacing a missing corner.
            assert_true(len(reference)>0)
            # Boundary distance remains at the fixed geometric gate. Corner
            # location error has a derived inverse-turn conditioning bound:
            # almost parallel intersecting lines amplify binary64 basis error.
            for i in range(len(reference)):
                var r=reference[i];var midpoint=(r.a+r.b)*.5
                var previous=(reference[(i+len(reference)-1)%len(reference)].a+reference[(i+len(reference)-1)%len(reference)].b)*.5
                var next=(reference[(i+1)%len(reference)].a+reference[(i+1)%len(reference)].b)*.5
                var u=midpoint-previous;var v=next-midpoint
                var product=sqrt(scalar_dot(u,u)*scalar_dot(v,v));var turn=Float64(1)
                if product>0:turn=sqrt(scalar_dot(scalar_cross(u,v),scalar_cross(u,v)))/product
                var corner_bound=tolerance/max(EPS,min(turn,condition));var nearest=Float64(1e300)
                for p in patch.points:
                    var d=(p.witness_a_relative+p.witness_b_relative)*.5-midpoint;nearest=min(nearest,sqrt(scalar_dot(d,d)))
                assert_true(nearest<=corner_bound)
                # GPU points are lexicographic, not cyclic. All pair segments
                # contain the polygon edges, so convex containment plus this
                # distance check proves no resolved boundary corner is missing.
                var boundary=Float64(1e300)
                for j in range(len(patch.points)):
                    var a_mid=(patch.points[j].witness_a_relative+patch.points[j].witness_b_relative)*.5
                    boundary=min(boundary,sqrt(scalar_dot(midpoint-a_mid,midpoint-a_mid)))
                    for k in range(j+1,len(patch.points)):
                        var b_mid=(patch.points[k].witness_a_relative+patch.points[k].witness_b_relative)*.5
                        boundary=min(boundary,segment_distance(midpoint,a_mid,b_mid))
                assert_true(boundary<=construction_bound)
            for p in patch.points:
                var midpoint=(p.witness_a_relative+p.witness_b_relative)*.5;var boundary=Float64(1e300)
                for i in range(len(reference)):
                    var ra=(reference[i].a+reference[i].b)*.5;var rb=(reference[(i+1)%len(reference)].a+reference[(i+1)%len(reference)].b)*.5
                    boundary=min(boundary,segment_distance(midpoint,ra,rb))
                assert_true(boundary<=construction_bound)
        else:
            assert_equal(len(patch.points),1)
            var independent=reference_edge(a,b,Int(patch.feature))
            vector(patch.points[0].witness_a_relative,independent.a,1e-10);vector(patch.points[0].witness_b_relative,independent.b,1e-10)


def intersection_condition(a: ReferenceBox,b: ReferenceBox) -> Float64:
    # Three independent edge directions and three face normals. The smallest
    # nonzero sine bounds edge intersections and the contact-plane cut.
    var condition=Float64(1)
    for kind in range(2):
        for i in range(3):
            var u=direction(a.edge(i)) if kind==0 else face(a,i)
            for j in range(3):
                var v=direction(b.edge(j)) if kind==0 else face(b,j)
                var cross=scalar_cross(u,v);var sine=sqrt(scalar_dot(cross,cross))
                if sine>0:condition=min(condition,sine)
    return condition

def segment_distance(p: Vec3,a: Vec3,b: Vec3) -> Float64:
    var v=b-a;var denominator=scalar_dot(v,v);var t=Float64(0)
    if denominator>0:t=max(0.0,min(1.0,scalar_dot(p-a,v)/denominator))
    var d=p-a-v*t;return sqrt(scalar_dot(d,d))

def analytic() raises:
    for gap in [Float64(-.2),Float64(0),Float64(1e-8)]:
        var w=GpuBoxBoxDetection();var m: List[OracleBox]=[add(w,Vec3(0,0,0),Vec3(.8,.5,.3)),add(w,Vec3(0,0,.6+gap),Vec3(.8,.5,.3))]
        compare(w,m,0 if gap>0 else 1,4);w.close()
    var contained=GpuBoxBoxDetection();var m: List[OracleBox]=[add(contained,Vec3(0,0,0),Vec3(2,2,2)),add(contained,Vec3(.1,.05,.02),Vec3(.5,.7,.9))]
    compare(contained,m,1,4);var f=contained.detect();near(f.patches[0].separation,-2.4);contained.close()
    for yaw in [Float64(.43),Float64(-.78),Float64(1.31)]:
        var w=GpuBoxBoxDetection();var q=Quaternion.axis_angle(Vec3(0,0,1),yaw)
        var m: List[OracleBox]=[add(w,Vec3(0,0,0),Vec3(1,.7,.25),q),add(w,Vec3(0,0,.5),Vec3(1,.7,.25),Quaternion(),Vec3(0,0,0),q)]
        compare(w,m,1,4);w.close()
    var octagon=GpuBoxBoxDetection();var octagon_models: List[OracleBox]=[add(octagon,Vec3(0,0,0),Vec3(1,1,.25)),add(octagon,Vec3(0,0,.4),Vec3(1,1,.25),Quaternion.axis_angle(Vec3(0,0,1),.3))]
    compare(octagon,octagon_models,1,8);octagon.close()
    print("GPU box/box analytic face rectangles, separated/touch/deep/contained, rounded quaternion routes and eight-vertex patch passed")

def edges() raises:
    var q=Quaternion.axis_angle(Vec3(0,1,0),.43)*Quaternion.axis_angle(Vec3(1,0,0),.61)*Quaternion.axis_angle(Vec3(0,0,1),.91)
    var w=GpuBoxBoxDetection();var m: List[OracleBox]=[add(w,Vec3(0,0,0),Vec3(1.2,.13,.17)),add(w,Vec3(0,0,.4),Vec3(1.2,.13,.17),q)]
    compare(w,m,1,1);var f=w.detect();assert_true(f.patches[0].feature>=6)
    var axes=box_axes(m[1]);var raw=direction(scalar_cross(Vec3(1,0,0),axes[0]));var n=raw if raw.z>=0 else raw*(-1);vector(f.patches[0].normal,n,1e-12);w.close()
    var separated=GpuBoxBoxDetection();var separate_models: List[OracleBox]=[add(separated,Vec3(0,0,0),Vec3(1.2,.13,.17)),add(separated,Vec3(0,0,.4)+n*.05,Vec3(1.2,.13,.17),q)]
    compare(separated,separate_models,0);var inputs=input_boxes(separated,separate_models)
    for i in range(6):assert_true(vertex_gap(inputs[0],inputs[1],face(inputs[0],i) if i<3 else face(inputs[1],i-3))<0)
    assert_true(vertex_gap(inputs[0],inputs[1],n)>0);separated.close();print("GPU skew edge/edge contact and independently vertex-checked edge-cross separating direction passed")

from experimental.physics_gpu.box_box_reference import vertex_gap

def seeded_perturbations() raises:
    var state=UInt64(0x2bb030713);var tested=0
    for scale in [Float64(1e-12),Float64(1e-10),Float64(1e-8),Float64(1e-6)]:
        for sample in range(12):
            state=state^(state<<7);state=state^(state>>9);state=state^(state<<8)
            var j=Float64(state&UInt64(65535))/65535*2-1
            state=state^(state<<7);state=state^(state>>9);state=state^(state<<8)
            var k=Float64(state&UInt64(65535))/65535*2-1
            var q=Quaternion.axis_angle(Vec3(0,0,1),.57)
            var perturbed=q*Quaternion.axis_angle(Vec3(.3,-.7,.2),scale*j)
            var w=GpuBoxBoxDetection();var a=add(w,Vec3(0,0,0),Vec3(.9,.65,.23),q)
            var b=add(w,Vec3(scale*j,scale*k,.46-2e-8),Vec3(.9,.65,.23),perturbed if sample%2==0 else Quaternion(),Vec3(0,0,0),Quaternion() if sample%2==0 else perturbed)
            var models: List[OracleBox]=[a,b];compare(w,models,1);var before=w.debug_publication();_=w.detect();var after=w.debug_publication();
            for i in range(len(before)-4):assert_equal(before[i],after[i])
            w.close();tested+=1
    assert_equal(tested,48);print("GPU box/box seeded near-coplanar/parallel perturbations:",tested,"with separate missing/extra/duplicate checks passed")

def metamorphic() raises:
    var base=GpuBoxBoxDetection();var q=Quaternion.axis_angle(Vec3(0,0,1),.3)
    var models: List[OracleBox]=[add(base,Vec3(0,0,0),Vec3(1,.7,.25)),add(base,Vec3(.2,.1,.4),Vec3(1,.7,.25),q)]
    compare(base,models,1);var original=base.detect()
    for scale in [Float64(.01),Float64(1),Float64(100)]:
        for shift in [Vec3(0,0,0),Vec3(1000,-2000,3000)]:
            for reverse in [False,True]:
                var w=GpuBoxBoxDetection();var first=add(w,shift+(Vec3(.2,.1,.4)*scale if reverse else Vec3(0,0,0)),Vec3(1,.7,.25)*scale,q if reverse else Quaternion())
                var second=add(w,shift+(Vec3(0,0,0) if reverse else Vec3(.2,.1,.4)*scale),Vec3(1,.7,.25)*scale,Quaternion() if reverse else q)
                var model: List[OracleBox]=[first,second];compare(w,model,1);var f=w.detect()
                near(f.patches[0].separation/scale,original.patches[0].separation,1e-8);vector(f.patches[0].normal,original.patches[0].normal*(-1) if reverse else original.patches[0].normal,1e-10)
                assert_equal(len(f.patches[0].points),len(original.patches[0].points))
                for p in original.patches[0].points:
                    var best=Float64(1e300);var target=(p.witness_a_relative+p.witness_b_relative)*.5
                    for actual in f.patches[0].points:
                        var midpoint=(actual.witness_a_relative+actual.witness_b_relative)*(.5/scale)
                        if reverse:midpoint=midpoint+Vec3(.2,.1,.4)
                        var d=midpoint-target;best=min(best,sqrt(scalar_dot(d,d)))
                    assert_true(best<=1e-8)
                w.close()
    base.close();print("GPU box/box scale/translation/body-permutation contact-set and signed-normal invariants passed")

from std.testing import assert_raises
from std.memory import Pointer
from max.gpu import block_idx,block_dim,thread_idx
from experimental.physics_gpu.collision import SphereCommand
from experimental.physics_gpu.contact_oracle import OracleSphere
from experimental.physics_gpu.box_oracle import mixed_frame
from experimental.physics_gpu.shape_kernels import BAD_SHAPE,SHAPE_WORLD,SHAPE_STALE,SHAPE_FULL,GEOMETRY_RANGE,PAIR_OVERFLOW,CONTACT_OVERFLOW,SHAPE_STRIDE
from experimental.physics_gpu.box_box_kernels import BB_PAIRS_FULL,BB_POINTS_FULL,BB_EPOCH_FULL,BB_GEOMETRY,publish_boxes

def exact(a: List[UInt64],b: List[UInt64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(a[i],b[i])
def raw_equal(a: List[Float64],b: List[Float64]) raises:
    assert_equal(len(a),len(b))
    for i in range(len(a)):assert_equal(float_bits(a[i]),float_bits(b[i]))
def reject_shape(mut w: GpuBoxBoxDetection,commands: List[BoxCommand],code: Int32) raises:
    var before=w.debug_publication();var registry=w.world.debug_registry();var bodies=w.world.bodies.raw();var metadata=w.world.bodies.metadata()
    with assert_raises():_=w.world.submit_boxes(commands)
    assert_equal(w.world.last_error,code);exact(before,w.debug_publication())
    var after=w.world.debug_registry();exact(registry[0],after[0]);raw_equal(registry[1],after[1]);raw_equal(bodies,w.world.bodies.raw());exact(metadata,w.world.bodies.metadata())
def lifecycle() raises:
    var w=GpuBoxBoxDetection();var models: List[OracleBox]=[add(w,Vec3(0,0,0),Vec3(1,1,1)),add(w,Vec3(0,0,1.9),Vec3(1,1,1))]
    compare(w,models,1,4);var original=w.detect();var old_body=models[0].body_handle;var old_shape=models[0].shape
    models[1].body.position=Vec3(0,0,5);_=w.world.bodies.submit([BodyCommand.update(models[1].body_handle,models[1].body)]);compare(w,models,0)
    models[1].body.position=Vec3(0,0,1.9);_=w.world.bodies.submit([BodyCommand.update(models[1].body_handle,models[1].body)]);compare(w,models,1,4)
    _=w.world.submit_boxes([BoxCommand.reshape(models[0].shape,Vec3(.9,.8,1))]);models[0].half_extents=Vec3(.9,.8,1);models[0].revision+=1;compare(w,models,1,4)
    var changed=w.detect();assert_equal(changed.patches[0].key.revision_a,UInt64(2));assert_equal(original.patches[0].key.revision_a,UInt64(1))
    _=w.world.bodies.submit([BodyCommand.remove(old_body)]);var removed=w.detect();assert_equal(len(removed.patches),0)
    var replacement=add(w,Vec3(0,0,0),Vec3(1,1,1));assert_equal(replacement.shape.slot,old_shape.slot);assert_equal(replacement.shape.generation,old_shape.generation+1);assert_equal(replacement.body_handle.generation,old_body.generation+1)
    models[0]=replacement;compare(w,models,1,4)
    reject_shape(w,[BoxCommand.reshape(old_shape,Vec3(1,1,1))],SHAPE_STALE)
    var saved=w.debug_publication()
    with assert_raises():_=w.world.bodies.submit([BodyCommand.update(old_body,replacement.body)])
    exact(saved,w.debug_publication());compare(w,models,1,4)
    var other=GpuBoxBoxDetection();var foreign=add(other,Vec3(0,0,0),Vec3(1,1,1));reject_shape(w,[BoxCommand.detach(foreign.shape)],SHAPE_WORLD);other.close()
    _=w.world.submit_boxes([BoxCommand.detach(replacement.shape)]);assert_equal(len(w.detect().patches),0)
    var attached=w.world.submit_boxes([BoxCommand.attach(replacement.body_handle,Vec3(1,1,1))]);assert_equal(attached[0].generation,replacement.shape.generation+1);models[0].shape=attached[0];compare(w,models,1,4)
    reject_shape(w,[BoxCommand.detach(replacement.shape)],SHAPE_STALE)
    assert_equal(original.patches[0].key.a.generation,old_shape.generation);assert_equal(len(original.patches[0].points),4)
    var bodies=w.world.bodies.raw();var metadata=w.world.bodies.metadata();_=w.detect();raw_equal(bodies,w.world.bodies.raw());exact(metadata,w.world.bodies.metadata())
    w.close();w.close()
    with assert_raises():_=w.detect()
    with assert_raises():_=w.debug_publication()
    print("GPU box/box edits/revisions/removal/orphan reconciliation/slot reuse, stale/foreign rejection, immutable old frame and body-byte preservation passed")

def invalid_and_extremes() raises:
    var w=GpuBoxBoxDetection();var a=add(w,Vec3(0,0,0),Vec3(1,1,1));_=add(w,Vec3(0,0,1.9),Vec3(1,1,1));_=w.detect()
    var huge=Float64(1e308);var inf=huge*huge
    for x in [Float64(-1),Float64(0),Float64(1e-7),Float64(1e4+1),inf,inf-inf]:
        with assert_raises():_=BoxCommand.attach(a.body_handle,Vec3(x,1,1))
        var command=BoxCommand.reshape(a.shape,Vec3(1,1,1));command.half_extents.x=x
        reject_shape(w,[BoxCommand.reshape(a.shape,Vec3(.8,.8,.8)),command],BAD_SHAPE);assert_equal(w.world.last_bad_command,Int32(1))
    for q in [Quaternion(0,0,0,0),Quaternion(inf,0,0,1),Quaternion(inf-inf,0,0,1),Quaternion(0,0,0,1e-13),Quaternion(0,0,0,1e13)]:
        with assert_raises():_=BoxCommand.attach(a.body_handle,Vec3(1,1,1),orientation=q)
        var command=BoxCommand.reshape(a.shape,Vec3(1,1,1));command.local_orientation=q;reject_shape(w,[command],BAD_SHAPE)
    for x in [inf,inf-inf,Float64(1e6+1)]:
        var command=BoxCommand.reshape(a.shape,Vec3(1,1,1));command.local_center.x=x;reject_shape(w,[command],BAD_SHAPE)
    w.close()
    for size in [Float64(1e-6),Float64(1e4)]:
        var extreme=GpuBoxBoxDetection();var model: List[OracleBox]=[add(extreme,Vec3(0,0,0),Vec3(size,size,size)),add(extreme,Vec3(0,0,size*1.9),Vec3(size,size,size))]
        compare(extreme,model,1,4);extreme.close()
    # Largest admitted center with local witnesses, and most anisotropic boxes.
    var translated=GpuBoxBoxDetection();var model: List[OracleBox]=[add(translated,Vec3(1e9,1e9,1e9),Vec3(1e-6,1e4,1)),add(translated,Vec3(1e9,1e9,1e9-1.9),Vec3(1e-6,1e4,1))]
    compare(translated,model,1,4);translated.close()
    for qscale in [Float64(-1e12),Float64(1e-12)]:
        var scaled=GpuBoxBoxDetection();var q=Quaternion.axis_angle(Vec3(0,0,1),.57);var local=Quaternion(q.x*qscale,q.y*qscale,q.z*qscale,q.w*qscale)
        # At exactly 1e-12 the max quaternion component is below the admitted
        # descriptor threshold. Normalize max-component to exercise the boundary.
        var maximum=max(abs(q.x),max(abs(q.y),max(abs(q.z),abs(q.w))));local=Quaternion(local.x/maximum,local.y/maximum,local.z/maximum,local.w/maximum)
        var scaled_models: List[OracleBox]=[add(scaled,Vec3(0,0,0),Vec3(.9,.65,.23),q),add(scaled,Vec3(0,0,.46-1e-8),Vec3(.9,.65,.23),Quaternion(),Vec3(0,0,0),local)]
        compare(scaled,scaled_models,1,4);scaled.close()
    var range_world=GpuBoxBoxDetection();_=add(range_world,Vec3(1e9+1,0,0),Vec3(1,1,1));var before=range_world.debug_publication()
    with assert_raises():_=range_world.detect()
    assert_equal(range_world.last_error,GEOMETRY_RANGE);exact(before,range_world.debug_publication());range_world.close()
    print("GPU box/box zero/nonfinite/raw packet rollback, admitted extent/quaternion/anisotropy/translation limits and center-range rejection passed")

def overwrite_u64(words: Pointer[UInt64,MutAnyOrigin],offset: Int32,value: UInt64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def capacity_and_rollback() raises:
    var empty=GpuBoxBoxDetection(pair_limit=0,point_limit=0);assert_equal(len(empty.detect().patches),0);empty.close()
    for pair_failure in [False,True]:
        var w=GpuBoxBoxDetection(pair_limit=Int32(0 if pair_failure else 1),point_limit=Int32(4 if pair_failure else 3));_=add(w,Vec3(0,0,0),Vec3(1,1,1));_=add(w,Vec3(0,0,1.9),Vec3(1,1,1))
        var before=w.debug_publication();var body_before=w.world.bodies.raw()
        with assert_raises():_=w.detect()
        assert_equal(w.last_error,BB_PAIRS_FULL if pair_failure else BB_POINTS_FULL);exact(before,w.debug_publication());raw_equal(body_before,w.world.bodies.raw());w.close()
    var retry=GpuBoxBoxDetection(pair_limit=1,point_limit=4);var a=add(retry,Vec3(0,0,0),Vec3(1,1,1));var b=add(retry,Vec3(0,0,1.9),Vec3(1,1,1));_=retry.detect()
    var before=retry.debug_publication();var extra=add(retry,Vec3(0,0,0),Vec3(1,1,1));var body_before=retry.world.bodies.raw()
    with assert_raises():_=retry.detect()
    assert_equal(retry.last_error,BB_PAIRS_FULL);exact(before,retry.debug_publication());raw_equal(body_before,retry.world.bodies.raw())
    _=retry.world.bodies.submit([BodyCommand.remove(extra.body_handle)]);var frame=retry.detect();assert_equal(len(frame.patches),1);assert_equal(frame.epoch,UInt64(2))
    retry.world.bodies._ctx.enqueue_function[overwrite_u64](retry._state,Int32(1),UInt64.MAX-1,grid_dim=1,block_dim=1);retry.world.bodies._ctx.synchronize();var max_frame=retry.detect();assert_equal(max_frame.epoch,UInt64.MAX);before=retry.debug_publication()
    with assert_raises():_=retry.detect()
    assert_equal(retry.last_error,BB_EPOCH_FULL);exact(before,retry.debug_publication());retry.close()
    for limit in [Int32(-1),Int32(2017)]:
        with assert_raises():_=GpuBoxBoxDetection(pair_limit=limit)
    for limit in [Int32(-1),Int32(18145)]:
        with assert_raises():_=GpuBoxBoxDetection(point_limit=limit)
    var full=GpuBoxBoxDetection(pair_limit=2016,point_limit=18144);var commands=List[BodyCommand]()
    for _ in range(256):commands.append(BodyCommand.create(RigidBody3D(MassProperties3D.fixed())))
    var handles=full.world.bodies.submit(commands);var boxes=List[BoxCommand]()
    for i in range(64):boxes.append(BoxCommand.attach(handles[i],Vec3(1,1,1)))
    var shapes=full.world.submit_boxes(boxes);var all=full.detect();assert_equal(len(all.patches),2016)
    var total=0;var previous=Int(-1)
    for i in range(len(all.patches)):
        ref patch=all.patches[i];var order=Int(patch.key.a.slot)*64+Int(patch.key.b.slot);assert_true(order>previous);previous=order;assert_equal(len(patch.points),4);total+=len(patch.points)
    assert_equal(total,8064);var saved=full.debug_publication()
    with assert_raises():_=full.world.submit_boxes([BoxCommand.attach(handles[64],Vec3(1,1,1))])
    assert_equal(full.world.last_error,SHAPE_FULL);exact(saved,full.debug_publication());full.close()
    print("GPU box/box 256 bodies/64 boxes/2016 ordered patches/8064 points, zero capacities, pair/point overflow, failed retry and UInt64 epoch rollback passed")

def legacy_mixed() raises:
    var w=GpuBoxBoxDetection();var boxes: List[OracleBox]=[add(w,Vec3(0,0,0),Vec3(1,1,1)),add(w,Vec3(0,0,1.9),Vec3(1,1,1))]
    var body=RigidBody3D(MassProperties3D.sphere(2,.5),position=Vec3(1.3,0,0));var h=w.world.bodies.submit([BodyCommand.create(body)]);var shapes=w.world.submit_shapes([SphereCommand.attach(h[0],.5)])
    var spheres: List[OracleSphere]=[OracleSphere(shapes[0],h[0],1,body,.5,Vec3(0,0,0))];var f=w.detect();var expected=mixed_frame(spheres,boxes)
    assert_equal(len(f.patches),1);assert_equal(len(f.legacy.contacts),len(expected.contacts));assert_equal(len(f.legacy.candidates),len(expected.candidates))
    for i in range(len(f.legacy.contacts)):
        var a=f.legacy.contacts[i];var b=expected.contacts[i];assert_equal(a.key.a.slot,b.key.a.slot);assert_equal(a.key.b.slot,b.key.b.slot);vector(a.normal,b.normal);near(a.separation,b.separation);vector(a.witness_a,b.witness_a);vector(a.witness_b,b.witness_b)
    w.close()
    for candidate_failure in [False,True]:
        var limited=GpuBoxBoxDetection(legacy_pair_limit=Int32(0 if candidate_failure else 10),legacy_contact_limit=Int32(10 if candidate_failure else 0));_=add(limited,Vec3(0,0,0),Vec3(1,1,1))
        var handles=limited.world.bodies.submit([BodyCommand.create(body)]);_=limited.world.submit_shapes([SphereCommand.attach(handles[0],.5)]);var before=limited.debug_publication()
        with assert_raises():_=limited.detect()
        assert_equal(limited.last_error,PAIR_OVERFLOW if candidate_failure else CONTACT_OVERFLOW);exact(before,limited.debug_publication());limited.close()
    print("GPU box/box separate patch stream, independent old sphere/OBB comparison and legacy output failure preserves box publication passed")

def general_rotations() raises:
    var state=UInt64(0xbb030713);var tested=0
    for _ in range(96):
        state=state^(state<<7);state=state^(state>>9);state=state^(state<<8);var x=Float64(state&65535)/65535*2-1
        state=state^(state<<7);state=state^(state>>9);state=state^(state<<8);var y=Float64(state&65535)/65535*2-1
        state=state^(state<<7);state=state^(state>>9);state=state^(state<<8);var z=Float64(state&65535)/65535*2-1
        var q0=Quaternion.axis_angle(Vec3(.7,-.3,.2),x*2);var q1=Quaternion.axis_angle(Vec3(-.2,.9,.4),y*2)
        var w=GpuBoxBoxDetection();var models: List[OracleBox]=[add(w,Vec3(.1,-.2,.3),Vec3(.9,.4,.6),q0),add(w,Vec3(x*2,y*2,z*2),Vec3(.7,.3,.5),q1)]
        compare(w,models);w.close();tested+=1
    assert_equal(tested,96);print("GPU general seeded rotated face/edge and separated pairs: 96 independent corner SAT and constructive/Gram witnesses passed")

from experimental.physics_gpu.box_box_kernels import BoxGeometry,SatResult,face_patch,sort_patch

def clip_nine_kernel(output: Pointer[Float64,MutAnyOrigin]):
    var q=Quaternion(.09981414946992548,.12463072476706054,.1811254634227923,.9704111935203092)
    var a=BoxGeometry(Vec3(0,0,0),Vec3(1,1,.25),Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,1))
    var b=BoxGeometry(Vec3(-.08205539024948501,.1076356145571069,.2528877698939498),Vec3(1.0717570763714046,.9452964065003434,.25),q.rotate(Vec3(1,0,0)),q.rotate(Vec3(0,1,0)),q.rotate(Vec3(0,0,1)))
    # Deliberate reference-face selection to exercise the clipper's full bound.
    # This is a helper test; SAT may choose another feature for this pair.
    var p=face_patch(a,b,SatResult(True,Vec3(0,0,1),-.1,2,False));sort_patch(p,32*EPS*1.1)
    output[unsafe_offset=0]=Float64(p.error);output[unsafe_offset=1]=Float64(p.count)
    for i in range(Int(p.count)):
        var k=2+i*7;output[unsafe_offset=k]=p.a[i].x;output[unsafe_offset=k+1]=p.a[i].y;output[unsafe_offset=k+2]=p.a[i].z
        output[unsafe_offset=k+3]=p.b[i].x;output[unsafe_offset=k+4]=p.b[i].y;output[unsafe_offset=k+5]=p.b[i].z;output[unsafe_offset=k+6]=p.separation[i]

def tangencies_and_nine() raises:
    for corners in [False,True]:
        var w=GpuBoxBoxDetection();var models: List[OracleBox]=[add(w,Vec3(0,0,0),Vec3(1,1,1)),add(w,Vec3(2,2,Float64(2 if corners else 0)),Vec3(1,1,1))]
        compare(w,models,1,1 if corners else 2);w.close()
    var probe=GpuBoxBoxDetection();var output=probe.world.bodies._ctx.enqueue_create_buffer[DType.float64](66);output.enqueue_fill(-987654321.25)
    probe.world.bodies._ctx.enqueue_function[clip_nine_kernel](output,grid_dim=1,block_dim=1);probe.world.bodies._ctx.synchronize()
    var q=Quaternion(.09981414946992548,.12463072476706054,.1811254634227923,.9704111935203092)
    var a=ReferenceBox(Vec3(0,0,0),Vec3(1,0,0),Vec3(0,1,0),Vec3(0,0,.25));var b=ReferenceBox(Vec3(-.08205539024948501,.1076356145571069,.2528877698939498),q.rotate(Vec3(1,0,0))*1.0717570763714046,q.rotate(Vec3(0,1,0))*.9452964065003434,q.rotate(Vec3(0,0,1))*.25)
    var reference=reference_patch(a,b,2,32*EPS*1.1);assert_equal(len(reference),9)
    with output.map_to_host() as words:
        assert_equal(words[0],Float64(0));assert_equal(words[1],Float64(9));assert_equal(words[65],Float64(-987654321.25))
        for i in range(9):
            var k=2+i*7;var wa=Vec3(words[k],words[k+1],words[k+2]);var wb=Vec3(words[k+3],words[k+4],words[k+5]);var sep=Float64(words[k+6])
            assert_true(sep<=0);on_box(wa,a,a.center,512*EPS*1.1);on_box(wb,b,a.center,512*EPS*1.1);vector(wb-wa,Vec3(0,0,sep),1e-12)
            var best=Float64(1e300)
            for point in reference:
                var d=(wa+wb-point.a-point.b)*.5;best=min(best,sqrt(scalar_dot(d,d)))
            assert_true(best<=512*EPS*1.1)
            if i>0:
                var previous=2+(i-1)*7
                var prior=(Vec3(words[previous],words[previous+1],words[previous+2])+Vec3(words[previous+3],words[previous+4],words[previous+5]))*.5
                var current=(wa+wb)*.5
                assert_true(current.x>prior.x or (current.x==prior.x and current.y>prior.y) or (current.x==prior.x and current.y==prior.y and current.z>prior.z))
            for j in range(i+1,9):
                var offset=2+j*7;var difference=(wa+wb-Vec3(words[offset],words[offset+1],words[offset+2])-Vec3(words[offset+3],words[offset+4],words[offset+5]))*.5
                assert_true(max(abs(difference.x),max(abs(difference.y),abs(difference.z)))>32*EPS*1.1)
    probe.close();print("GPU exact line/point tangency and nine-point clipping helper upper bound, independent contour, membership, depth and uniqueness passed")

def overwrite_i32(words: Pointer[Int32,MutAnyOrigin],offset: Int32,value: Int32):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def overwrite_f64(words: Pointer[Float64,MutAnyOrigin],offset: Int32,value: Float64):
    if Int(block_idx.x*block_dim.x+thread_idx.x)==0:words[unsafe_offset=Int(offset)]=value

def candidate_rejection() raises:
    var w=GpuBoxBoxDetection();_=add(w,Vec3(0,0,0),Vec3(1,1,1));_=add(w,Vec3(0,0,1.9),Vec3(1,1,1))
    var huge=Float64(1e308);var inf=huge*huge
    for invalid in range(8):
        _=w.detect();var before=w.debug_publication()
        if invalid<2:w.world.bodies._ctx.enqueue_function[overwrite_i32](w._counts,Int32(1),Int32(0 if invalid==0 else 10),grid_dim=1,block_dim=1)
        elif invalid==2:w.world.bodies._ctx.enqueue_function[overwrite_f64](w._values,Int32(1),inf-inf,grid_dim=1,block_dim=1)
        elif invalid==3:w.world.bodies._ctx.enqueue_function[overwrite_f64](w._points,Int32(7),Float64(.1),grid_dim=1,block_dim=1)
        elif invalid==4:w.world.bodies._ctx.enqueue_function[overwrite_u64](w._features,Int32(1),UInt64(15),grid_dim=1,block_dim=1)
        elif invalid==5:w.world.bodies._ctx.enqueue_function[overwrite_f64](w._values,Int32(6),Float64(0),grid_dim=1,block_dim=1)
        elif invalid==6:w.world.bodies._ctx.enqueue_function[overwrite_i32](w._flags,Int32(1),Int32(2),grid_dim=1,block_dim=1)
        else:w.world.bodies._ctx.enqueue_function[overwrite_i32](w._errors,Int32(1),BB_GEOMETRY,grid_dim=1,block_dim=1)
        w.world.bodies._ctx.enqueue_function[publish_boxes](w.world._meta,w.world._statuses,w._flags,w._counts,w._errors,w._features,w._values,w._points,w._headers,w._output,w._point_output,w._state,w._summary,w._pair_limit,w._point_limit,grid_dim=1,block_dim=1)
        w.world.bodies._ctx.synchronize()
        with w._summary.map_to_host() as summary:assert_equal(summary[0],BB_GEOMETRY)
        exact(before,w.debug_publication())
    w.close();print("GPU private candidate malformed count/feature/flag/normal/nonfinite/positive-depth/error rejection preserves all publication bits passed")

def candidate_guards(mut w: GpuBoxBoxDetection) raises:
    with w._flags.map_to_host() as f,w._counts.map_to_host() as c,w._errors.map_to_host() as e:
        assert_equal(f[0],Int32(-98765));assert_equal(f[2017],Int32(-98765));assert_equal(c[0],Int32(-98765));assert_equal(c[2017],Int32(-98765));assert_equal(e[0],Int32(-98765));assert_equal(e[2017],Int32(-98765))
    with w._features.map_to_host() as f,w._values.map_to_host() as v,w._points.map_to_host() as p:
        assert_equal(f[0],UInt64.MAX);assert_equal(f[4033],UInt64.MAX)
        assert_equal(v[0],Float64(-987654321.25));assert_equal(v[14113],Float64(-987654321.25));assert_equal(p[0],Float64(-987654321.25));assert_equal(p[127009],Float64(-987654321.25))

from experimental.physics_gpu.box_box_kernels import Patch

def midpoint_unique_kernel(output: Pointer[Float64,MutAnyOrigin]):
    var patch=Patch();patch.count=3
    patch.a[0]=Vec3(0,0,0);patch.b[0]=Vec3(0,0,0)
    patch.a[1]=Vec3(0,0,0);patch.b[1]=Vec3(0,0,1.5e-12)
    patch.a[2]=Vec3(3e-12,0,0);patch.b[2]=Vec3(3e-12,0,0)
    sort_patch(patch,1e-12)
    output[unsafe_offset=0]=Float64(patch.count);output[unsafe_offset=1]=1 if patch.coalesced else 0
    output[unsafe_offset=2]=patch.a[0].x;output[unsafe_offset=3]=patch.a[1].x

def midpoint_unique() raises:
    assert_equal(float_bits(Float64(1)),UInt64(0x3ff0000000000000));assert_equal(float_bits(Float64(-0.0)),UInt64(1)<<63)
    var w=GpuBoxBoxDetection();var output=w.world.bodies._ctx.enqueue_create_buffer[DType.float64](5);output.enqueue_fill(-987654321.25)
    w.world.bodies._ctx.enqueue_function[midpoint_unique_kernel](output,grid_dim=1,block_dim=1);w.world.bodies._ctx.synchronize()
    with output.map_to_host() as values:
        assert_equal(values[0],Float64(2));assert_equal(values[1],Float64(1));assert_equal(values[2],Float64(0));assert_equal(values[3],Float64(3e-12));assert_equal(values[4],Float64(-987654321.25))
    w.close();print("GPU final witness-midpoint coalescing preserves resolved vertices/order and diagnostic raw bits passed")
