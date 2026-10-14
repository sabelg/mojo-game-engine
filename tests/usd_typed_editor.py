"""Exercise the actual editor IPC service across process restarts without a GPU."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]


def wait_state(work, process, sequence):
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        if process.poll() is not None:
            raise AssertionError('Editor bridge exited unexpectedly')
        file=work/'state.tsv'
        if file.exists():
            rows=[row.split('\t') for row in file.read_text().splitlines()]
            fields={row[0]:row[1:] for row in rows if len(row)>1 and row[0]!='layer'}
            if fields.get('ack')==[str(sequence)]:return rows,fields
        time.sleep(.02)
    raise AssertionError('Editor bridge did not acknowledge '+str(sequence))


def request(work, process, sequence, command):
    temporary=work/'request.tmp'
    temporary.write_text(str(sequence)+'\t'+command+'\n')
    temporary.replace(work/'request.tsv')
    return wait_state(work,process,sequence)


with tempfile.TemporaryDirectory(prefix='usd-typed-editor-',dir=ROOT/'build') as tmp:
    root=Path(tmp);source=root/'source.usda';workspace=root/'workspace';output=root/'exports'
    source.write_text('#usda 1.0\ndef Xform "Dolly" {\n double3 xformOp:translate.timeSamples={0:(0,10,20),10:(10,30,40)}\n uniform token[] xformOpOrder=["xformOp:translate"]\n}\n')
    original=source.read_bytes()
    for run in [0,1]:
        work=root/('ipc-'+str(run));work.mkdir()
        command=[sys.executable,str(ROOT/'scripts/usd-editor-bridge.py'),'--work',str(work),
                 '--output',str(output),'--workspace',str(workspace)]
        if run==0:command+=['--source',str(source)]
        with (root/('bridge-'+str(run)+'.log')).open('w') as log:
            process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            try:
                _,state=wait_state(work,process,0)
                if run==0:
                    edits=['curves\t/Dolly\t1.25','set_channel\t/Dolly\txformOp:translate\t0\t5.25\t1.25',
                           'copy_key\t/Dolly\txformOp:translate\t1.25\t2.75',
                           'move_key\t/Dolly\txformOp:translate\t2.75\t3.5',
                           'delete_key\t/Dolly\txformOp:translate\t3.5','undo','save_workspace']
                    for sequence,edit in enumerate(edits,1):
                        _,state=request(work,process,sequence,edit)
                        assert state['status']==['OK '+edit.split('\t')[0]],state
                        if sequence==1:
                            data=[row.split('\t') for row in (work/'curves.tsv').read_text().splitlines()]
                            assert data[0]==['ATLAS_USD_CURVES_2']
                            props=[row for row in data if row[0]=='property']
                            assert [p[1] for p in props]==['xformOp:translate[x]','xformOp:translate[y]','xformOp:translate[z]']
                            assert [p[6] for p in props]==['0','1','2']
                else:
                    _,state=request(work,process,1,'curves\t/Dolly\t3.5')
                    props=[row.split('\t') for row in (work/'curves.tsv').read_text().splitlines() if row.startswith('property\t')]
                    assert [float(row[2]) for row in props]==[5.25,12.5,22.5]
                    assert all(row[4]=='4' for row in props)
            finally:process.terminate();process.wait(timeout=5)
    assert source.read_bytes()==original

print('Typed editor IPC passed: channel labels and IDs, fractional values, tuple '
      'copy/move/delete/undo, workspace restart and unchanged source')
