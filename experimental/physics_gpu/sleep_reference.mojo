"""Qualification-only CPU BFS state machine with rational 1/240-second dwell.

Analytic fixtures supply edges, motion/support eligibility and command intent.
No GPU labels, contact output or production compensation/union routine is read.
"""
from std.collections import List

@fieldwise_init
struct SleepEdge(ImplicitlyCopyable,Movable):
    var a: Int
    var b: Int

@fieldwise_init
struct ReferenceReport(ImplicitlyCopyable,Movable):
    var asleep: Int32
    var entered: Int32
    var woke: Int32
    var idle: Bool

struct SleepReference(Movable):
    var asleep: List[Bool]
    var dwell: List[Int]
    var roots: List[Int]
    var generations: List[Int]
    var active: List[Bool]
    var previous_edges: List[SleepEdge]
    var target_ticks: Int

    def __init__(out self,count: Int,target_ticks: Int):
        self.asleep=List[Bool]();self.dwell=List[Int]();self.roots=List[Int]();self.generations=List[Int]();self.active=List[Bool]();self.previous_edges=List[SleepEdge]();self.target_ticks=target_ticks
        for _ in range(count):self.asleep.append(False);self.dwell.append(0);self.roots.append(-1);self.generations.append(0);self.active.append(False)

    def tick(mut self,edges: List[SleepEdge],elapsed_ticks: Int,eligible: List[Bool],dirty: List[Bool],active: List[Bool],generations: List[Int]) -> ReferenceReport:
        var count=len(self.asleep);var roots=List[Int]();var affected=List[Bool]()
        for i in range(count):roots.append(-1);affected.append(dirty[i] or self.active[i]!=active[i] or self.generations[i]!=generations[i])
        for seed in range(count):
            if not active[seed] or roots[seed]>=0:continue
            var queue=List[Int]();queue.append(seed);roots[seed]=-2;var head=0;var minimum=seed
            while head<len(queue):
                var vertex=queue[head];head+=1;minimum=min(minimum,vertex)
                for edge in edges:
                    var other=edge.b if edge.a==vertex else edge.a if edge.b==vertex else -1
                    if other>=0 and active[other] and roots[other]==-1:roots[other]=-2;queue.append(other)
            for vertex in queue:roots[vertex]=minimum
        for which in [0,1]:
            for edge in (edges if which==0 else self.previous_edges):
                var matched=False
                for previous in (self.previous_edges if which==0 else edges):
                    if edge.a==previous.a and edge.b==previous.b:matched=True
                if not matched:affected[edge.a]=True;affected[edge.b]=True
        for i in range(count):
            if roots[i]!=self.roots[i]:affected[i]=True
        # Propagate through both old and new components until closure; no fixed
        # vertices exist in this independent dynamic-only graph.
        for _ in range(count):
            for i in range(count):
                if not affected[i]:continue
                for j in range(count):
                    if (self.roots[i]>=0 and self.roots[i]==self.roots[j]) or (roots[i]>=0 and roots[i]==roots[j]):affected[j]=True
        var result=ReferenceReport(0,0,0,True);var live=0
        for i in range(count):
            if not active[i]:self.asleep[i]=False;self.dwell[i]=0;continue
            live+=1;var calm=not affected[i] and eligible[i]
            for j in range(count):
                if active[j] and roots[j]==roots[i] and not eligible[j]:calm=False
            var prior=self.active[i] and self.generations[i]==generations[i] and self.asleep[i]
            if not calm or not prior:result.idle=False
            if calm:self.dwell[i]+=elapsed_ticks
            else:self.dwell[i]=0
            var next=calm and self.dwell[i]>=self.target_ticks
            if next:result.asleep+=1
            if prior and not next:result.woke+=1
            if not prior and next:result.entered+=1
            self.asleep[i]=next
        if live==0:result.idle=False
        self.roots=roots^;self.generations=generations.copy();self.active=active.copy();self.previous_edges=edges.copy()
        return result
