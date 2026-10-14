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


with tempfile.TemporaryDirectory(prefix='usd-workspace-editor-',dir=ROOT/'build') as tmp:
    root=Path(tmp)
    source=root/'source.usda'
    source.write_text('#usda 1.0\ndef Camera "Camera" {\n float focalLength = 40\n}\n')
    original=source.read_bytes()
    output=root/'exports'
    workspace=root/'workspace'
    for run in [0,1]:
        work=root/('ipc-'+str(run));work.mkdir()
        command=[sys.executable,str(ROOT/'scripts/usd-editor-bridge.py'),
                 '--work',str(work),'--output',str(output),'--workspace',str(workspace)]
        if run==0:command+=['--source',str(source)]
        with (root/('bridge-'+str(run)+'.log')).open('w') as log:
            process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            try:
                rows,state=wait_state(work,process,0)
                if run==0:
                    assert state['unsaved_changes']==['1']
                    for sequence,edit in enumerate(['create_layer\tAnimation','set_key\t/Camera\tfocalLength\t55\t3',
                                                   'create_layer\tShot','set_key\t/Camera\tfocalLength\t65\t3',
                                                   'select_layer\tAnimation','save_workspace'],1):
                        rows,state=request(work,process,sequence,edit)
                        assert state['status']==['OK '+edit.split('\t')[0]]
                    assert state['unsaved_changes']==['0']
                    assert (work/'last-workspace.txt').read_text().strip()==str(workspace)
                else:
                    assert state['edit_target']==['Animation']
                    assert state['unsaved_changes']==['0']
                    assert [row[1] for row in rows if row[0]=='layer' and row[2]=='1']==['session','Shot','Animation']
                    _,state=request(work,process,1,'clear_layer')
                    assert state['unsaved_changes']==['1']
                    _,state=request(work,process,2,'open_workspace')
                    assert state['status'][0].startswith('ERROR Save workspace changes')
                    _,state=request(work,process,3,'undo')
                    assert state['unsaved_changes']==['0']
                    _,state=request(work,process,4,'open_workspace')
                    assert state['status']==['OK open_workspace']
                    _,state=request(work,process,5,'save')
                    assert state['status']==['OK save']
                    _,state=request(work,process,6,'package')
                    assert state['status']==['OK package']
            finally:
                process.terminate();process.wait(timeout=5)
    assert source.read_bytes()==original
    assert len(list(output.glob('*.usda')))==len(list(output.glob('*.usdz')))==1
    assert (workspace/'workspace.json').is_file()

print('USD workspace editor IPC passed: new workspace, dirty state, saved layer '
      'restart, source-free reopen, unsaved protection and separate USD/USDZ delivery')
