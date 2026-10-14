"""Atomic supported prefix plus instantaneous opening transition; no remainder advance."""
from std.memory import Pointer
from std.math import isfinite
from mojo_game import Vec3,Quaternion
from .floor_handoff import handoff_bits
from .supported_event_locator_refined import supported_event_locator
from .opening_contact_handoff import opening_contact_handoff

def supported_event_transition(inputs: Pointer[Float64,MutAnyOrigin],previous: Pointer[Float64,MutAnyOrigin],request: Pointer[Float64,MutAnyOrigin],output: Pointer[Float64,MutAnyOrigin],scratch: Pointer[Float64,MutAnyOrigin],status: Pointer[Float64,MutAnyOrigin],report: Pointer[Float64,MutAnyOrigin]):
    for k in range(192):output[unsafe_offset=k]=previous[unsafe_offset=k]
    for k in range(64):report[unsafe_offset=k]=0
    status[unsafe_offset=0]=0;status[unsafe_offset=1]=0
    var mode=request[unsafe_offset=11];var feature=request[unsafe_offset=12];var route=request[unsafe_offset=13];var H=request[unsafe_offset=8]
    if (mode!=0 and mode!=1) or not isfinite(feature) or feature < -1 or feature>7 or feature!=Float64(Int(feature)) or (route!=0 and route!=21 and route!=22 and route!=23) or not isfinite(H) or H<=0 or H>1.0/30:status[unsafe_offset=0]=1900;return
    var receipt=previous[unsafe_offset=142]==2 and previous[unsafe_offset=144]==1901
    var candidate=scratch;var local=scratch+192;var owner=scratch+4288;var private=scratch+4416;var req=scratch+4704
    for k in range(8):req[unsafe_offset=k]=request[unsafe_offset=k]
    if mode==1:
        if not receipt or handoff_bits(H)!=handoff_bits(previous[unsafe_offset=143]):status[unsafe_offset=0]=1903;return
        for k in range(96):
            if handoff_bits(inputs[unsafe_offset=k])!=handoff_bits(previous[unsafe_offset=k]):status[unsafe_offset=0]=1903;return
        if feature>=0 and feature!=previous[unsafe_offset=131]:status[unsafe_offset=0]=1905;return
        if route!=0 and route!=previous[unsafe_offset=98]:status[unsafe_offset=0]=1906;return
        opening_contact_handoff(inputs,previous,req,owner,private,status)
        if status[unsafe_offset=0]!=0:report[unsafe_offset=35]=status[unsafe_offset=1];status[unsafe_offset=1]=status[unsafe_offset=0];status[unsafe_offset=0]=1907;return
        var valid=owner[unsafe_offset=99]==previous[unsafe_offset=99] and owner[unsafe_offset=102]==0 and owner[unsafe_offset=103]==0 and owner[unsafe_offset=104]==0 and owner[unsafe_offset=98]==previous[unsafe_offset=98]
        for k in range(96):valid=valid and handoff_bits(owner[unsafe_offset=k])==handoff_bits(previous[unsafe_offset=k])
        if not valid:status[unsafe_offset=0]=1908;return
        report[unsafe_offset=32]=2;return
    if receipt:status[unsafe_offset=0]=1902;return
    supported_event_locator(inputs,previous,request,candidate,local,status,report)
    report[unsafe_offset=0]=0
    if status[unsafe_offset=0]!=0:return
    if candidate[unsafe_offset=142]!=1:status[unsafe_offset=0]=1904;return
    if feature>=0 and feature!=candidate[unsafe_offset=131]:status[unsafe_offset=0]=1905;return
    req[unsafe_offset=0]=previous[unsafe_offset=96];req[unsafe_offset=1]=previous[unsafe_offset=97]+1
    opening_contact_handoff(candidate,previous,req,owner,private,status)
    report[unsafe_offset=33]=status[unsafe_offset=0];report[unsafe_offset=34]=status[unsafe_offset=1]
    if status[unsafe_offset=0]!=0:report[unsafe_offset=35]=status[unsafe_offset=1];status[unsafe_offset=1]=status[unsafe_offset=0];status[unsafe_offset=0]=1907;return
    report[unsafe_offset=41]=owner[unsafe_offset=99]-previous[unsafe_offset=99];report[unsafe_offset=42]=owner[unsafe_offset=104];report[unsafe_offset=43]=owner[unsafe_offset=102];report[unsafe_offset=44]=owner[unsafe_offset=103];report[unsafe_offset=45]=owner[unsafe_offset=98]
    if route!=0 and route!=owner[unsafe_offset=98]:status[unsafe_offset=0]=1906;return
    if owner[unsafe_offset=99]!=previous[unsafe_offset=99]+1:status[unsafe_offset=0]=1908;return
    var m=inputs[unsafe_offset=1];var I=inputs[unsafe_offset=2];var n=Vec3(0,1,0);var p0=Vec3(inputs[unsafe_offset=5],inputs[unsafe_offset=6],inputs[unsafe_offset=7]);var p=Vec3(owner[unsafe_offset=5],owner[unsafe_offset=6],owner[unsafe_offset=7]);var v0=Vec3(inputs[unsafe_offset=12],inputs[unsafe_offset=13],inputs[unsafe_offset=14]);var v=Vec3(owner[unsafe_offset=12],owner[unsafe_offset=13],owner[unsafe_offset=14]);var w0=Vec3(inputs[unsafe_offset=15],inputs[unsafe_offset=16],inputs[unsafe_offset=17]);var w=Vec3(owner[unsafe_offset=15],owner[unsafe_offset=16],owner[unsafe_offset=17]);var F=Vec3(inputs[unsafe_offset=18],inputs[unsafe_offset=19],inputs[unsafe_offset=20])+Vec3(inputs[unsafe_offset=42],inputs[unsafe_offset=43],inputs[unsafe_offset=44])*m
    var half=Vec3(inputs[unsafe_offset=24],inputs[unsafe_offset=25],inputs[unsafe_offset=26]);var center=Vec3(inputs[unsafe_offset=27],inputs[unsafe_offset=28],inputs[unsafe_offset=29]);var shape=Quaternion(inputs[unsafe_offset=30],inputs[unsafe_offset=31],inputs[unsafe_offset=32],inputs[unsafe_offset=33]);var Q=Quaternion(owner[unsafe_offset=8],owner[unsafe_offset=9],owner[unsafe_offset=10],owner[unsafe_offset=11]);var eventM=Vec3(0,0,0);var eventO=Vec3(0,0,0)
    for k in range(2):
        var j=Int(owner[unsafe_offset=40+k]);var corner=Vec3(-half.x if j%2==0 else half.x,-half.y if (j//2)%2==0 else half.y,-half.z if (j//4)%2==0 else half.z);var arm=Q.rotate(center+shape.rotate(corner));var J=n*owner[unsafe_offset=102+k];eventM=eventM+arm.cross(J);eventO=eventO+(p+arm).cross(J)
    var tau=candidate[unsafe_offset=128];var totalJ=F*tau+n*(candidate[unsafe_offset=133]+owner[unsafe_offset=102]+owner[unsafe_offset=103]);var totalM=Vec3(candidate[unsafe_offset=134],candidate[unsafe_offset=135],candidate[unsafe_offset=136])+eventM;var totalO=Vec3(candidate[unsafe_offset=138],candidate[unsafe_offset=139],candidate[unsafe_offset=140])+eventO
    var T0=.5*(m*v0.dot(v0)+I*w0.dot(w0));var delta=.5*(m*v.dot(v)+I*w.dot(w))-T0;var extwork=F.dot(p-p0);var loss=owner[unsafe_offset=104];var work=candidate[unsafe_offset=137];var pe=((v-v0)*m-totalJ).length();var me=((w-w0)*I-totalM).length();var oe=((w-w0)*I+p.cross(v*m)-p0.cross(v0*m)-totalO).length();var ee=abs(delta-extwork-work+loss);var ideal=abs(delta-extwork+loss);var EB=1e-9*(1+T0)
    report[unsafe_offset=36]=pe;report[unsafe_offset=37]=me;report[unsafe_offset=38]=oe;report[unsafe_offset=39]=ee;report[unsafe_offset=40]=ideal
    if pe>1e-10*(1+totalJ.length()) or me>1e-10*(1+totalM.length()) or oe>1e-10*(1+totalO.length()) or ee>EB or ideal>EB or abs(work)+ee>EB:status[unsafe_offset=0]=1909;return
    for k in range(128):output[unsafe_offset=k]=owner[unsafe_offset=k]
    output[unsafe_offset=96]=previous[unsafe_offset=96]+1;output[unsafe_offset=97]=request[unsafe_offset=1]
    for k in range(128,143):output[unsafe_offset=k]=candidate[unsafe_offset=k]
    output[unsafe_offset=142]=2;output[unsafe_offset=143]=H;output[unsafe_offset=144]=1901;output[unsafe_offset=145]=previous[unsafe_offset=96];output[unsafe_offset=146]=previous[unsafe_offset=97];output[unsafe_offset=147]=extwork;output[unsafe_offset=148]=loss
    for k in range(3):
        output[unsafe_offset=149+k]=totalJ.x if k==0 else totalJ.y if k==1 else totalJ.z;output[unsafe_offset=152+k]=totalM.x if k==0 else totalM.y if k==1 else totalM.z;output[unsafe_offset=155+k]=totalO.x if k==0 else totalO.y if k==1 else totalO.z
    output[unsafe_offset=158]=delta;report[unsafe_offset=0]=tau;report[unsafe_offset=32]=1
