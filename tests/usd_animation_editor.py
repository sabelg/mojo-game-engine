"""Real editor bridge controls for splines, tangents, bake and physical retiming."""
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
def wait(work,process,sequence):
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        assert process.poll() is None,'Bridge exited unexpectedly'
        if (work/'state.tsv').exists():
            fields={r[0]:r[1:] for line in (work/'state.tsv').read_text().splitlines() if len(r:=line.split('\t'))>1 and r[0]!='layer'}
            if fields.get('ack')==[str(sequence)]:return fields
        time.sleep(.02)
    raise AssertionError('Bridge timed out')
def request(work,process,sequence,command):
    tmp=work/'request.tmp';tmp.write_text(str(sequence)+'\t'+command+'\n');tmp.replace(work/'request.tsv')
    state=wait(work,process,sequence);assert state['status']==['OK '+command.split('\t')[0]],state
    return state
with tempfile.TemporaryDirectory(prefix='usd-animation-editor-',dir=ROOT/'build') as tmp:
    root=Path(tmp);source=root/'source.usda';workspace=root/'workspace'
    source.write_text('#usda 1.0\n(startTimeCode=0\nendTimeCode=10\ntimeCodesPerSecond=24)\ndef Camera "Camera" {\n float focalLength.timeSamples={0:40,10:80}\n}\n')
    original=source.read_bytes()
    for run in [0,1]:
        work=root/('ipc-'+str(run));work.mkdir()
        command=[sys.executable,str(ROOT/'scripts/usd-editor-bridge.py'),'--work',str(work),'--workspace',str(workspace),'--output',str(root/'exports')]
        if run==0:command+=['--source',str(source)]
        with (root/('bridge-'+str(run)+'.log')).open('w') as log:
            process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            try:
                state=wait(work,process,0)
                if run==0:
                    commands=['set_interpolation\t/Camera\tfocalLength\tbezier','curves\t/Camera\t0',
                              'set_tangent\t/Camera\tfocalLength\t0\tout\t4\t3.3333333333333335',
                              'bake_curve\t/Camera\tfocalLength\t0\t10\t2\t0.001','undo',
                              'set_spline_value\t/Camera\tfocalLength\t53\t0',
                              'copy_spline_key\t/Camera\tfocalLength\t10\t15',
                              'move_spline_key\t/Camera\tfocalLength\t15\t16',
                              'delete_spline_key\t/Camera\tfocalLength\t16','begin_source_editing','select_layer\tsession',
                              'convert_frame_rate\t48','save_workspace']
                    for sequence,command in enumerate(commands,1):
                        state=request(work,process,sequence,command)
                        if sequence==2:
                            rows=[r.split('\t') for r in (work/'curves.tsv').read_text().splitlines()]
                            assert ['spline','focalLength','1'] in rows
                            assert next(r for r in rows if r[:2]==['property','focalLength'])[3:5]==['1','2']
                    assert float(state['author_rate'][0])==48
                else:
                    state=request(work,process,1,'curves\t/Camera\t0')
                    assert float(state['author_rate'][0])==48
                    rows=[r.split('\t') for r in (work/'curves.tsv').read_text().splitlines()]
                    assert float(next(r for r in rows if r[:2]==['property','focalLength'])[2])==53
                    assert ['spline','focalLength','1'] in rows
            finally:process.terminate();process.wait(timeout=5)
    assert source.read_bytes()==original
print('Animation editor IPC passed: spline knots, tangent controls, explicit bake, '
      'value/copy/move/delete, owned rate conversion and author clock across restart')
