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


with tempfile.TemporaryDirectory(prefix='usd-source-editor-',dir=ROOT/'build') as tmp:
    root=Path(tmp);source=root/'source.usda';asset=root/'asset.usda';workspace=root/'workspace'
    asset.write_text('#usda 1.0\n(defaultPrim="Camera")\ndef Camera "Camera" {\n float focalLength=40\n}\n')
    source.write_text('#usda 1.0\ndef Xform "A" (prepend references=@asset.usda@</Camera>) {}\n')
    originals={p:p.read_bytes() for p in [source,asset]};output=root/'exports'
    for run in [0,1]:
        work=root/('ipc-'+str(run));work.mkdir()
        command=[sys.executable,str(ROOT/'scripts/usd-editor-bridge.py'),'--work',str(work),
                 '--output',str(output),'--workspace',str(workspace)]
        if run==0:command+=['--source',str(source)]
        with (root/('bridge-'+str(run)+'.log')).open('w') as log:
            process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            try:
                rows,state=wait_state(work,process,0)
                if run==0:
                    edits=['begin_source_editing','cycle_source_target\t/A','cycle_source_target\t/A',
                           'set_key\t/A\tfocalLength\t55\t3','select_layer\tsession',
                           'set_key\t/A\tfocalLength\t65\t3','cycle_source_target\t/A',
                           'cycle_source_target\t/A','set_key\t/A\tfocalLength\t56\t3','repair_ids','save_workspace']
                    for sequence,edit in enumerate(edits,1):
                        rows,state=request(work,process,sequence,edit)
                        assert state['status'][0].startswith('OK '+edit.split('\t')[0]),state
                        if sequence==9:assert 'masked by a stronger layer' in state['status'][0]
                    assert state['edit_context']==['/A'] and state['unsaved_changes']==['0']
                else:
                    assert state['edit_context']==['/A'] and state['unsaved_changes']==['0']
                    asset.write_text(asset.read_text().replace('focalLength=40','focalLength=42'))
                    _,state=request(work,process,1,'save_workspace')
                    assert state['status'][0].startswith('ERROR Source conflict'),state
                    assert state['source_conflicts']==['1']
                    _,state=request(work,process,2,'resolve_sources\tkeep_working')
                    assert state['status']==['OK resolve_sources'] and state['source_conflicts']==['0']
                    _,state=request(work,process,3,'save_workspace');assert state['status']==['OK save_workspace']
                    _,state=request(work,process,4,'cycle_source_target\t/A');assert state['status']==['OK cycle_source_target']
            finally:process.terminate();process.wait(timeout=5)
    assert source.read_bytes()==originals[source]

print('USD source editor IPC passed: working graph, target cycling, masked-edit '
      'feedback, identity repair, target restart and visible explicit conflicts')
