"""Owned file IPC between Atlas's native USD panels and the persistent stage API."""
import argparse,importlib.util,json,signal,time
from pathlib import Path

spec=importlib.util.spec_from_file_location('atlas_usd_session',Path(__file__).with_name('usd-session.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
spec=importlib.util.spec_from_file_location('atlas_usd_preview',Path(__file__).with_name('usd-preview.py'))
preview_api=importlib.util.module_from_spec(spec);spec.loader.exec_module(preview_api)
def clean(value):return str(value).replace('\t',' ').replace('\r',' ').replace('\n',' ')[:4096]
def atomic(path,text):
    temporary=path.with_suffix('.tmp');temporary.write_text(text);temporary.replace(path)
def publish_curves(work,result):
    rows=['ATLAS_USD_CURVES_2',f'revision\t{result["revision"]}',f'path\t{result["path"]}',f'time\t{result["time"]}']
    for curve in result['curves']:
        label=curve.get('label',curve['name'])
        rows.append('\t'.join(['property',label,str(curve['value']),str(int(curve['editable'] or curve.get('spline_editable',False))),str(len(curve['keys'])),curve['name'],str(curve.get('channel',0)),str(curve.get('width',1))]))
        if curve.get('spline'):rows.append('\t'.join(['spline',label,str(int(curve.get('spline_editable',False)))]))
        if not curve['editable']:rows.append('\t'.join(['read_only',label,clean(curve.get('read_only_reason','Read-only property'))]))
        keys=curve['keys']
        # The service retains full key data; only the visual graph is downsampled.
        indices=sorted({round(i*(len(keys)-1)/255) for i in range(256)}) if len(keys)>256 else range(len(keys))
        for i in indices:
            key=keys[i]
            rows.append('\t'.join(['key',label,str(key['time']),str(key['value']),str(int(key['authored_in_target']))]))
    atomic(work/'curves.tsv','\n'.join(rows)+'\n')
def publish(work,snapshot,status,sequence):
    rows=['ATLAS_USD_EDITOR_1',f'ack\t{sequence}',f'revision\t{snapshot["revision"]}',f'status\t{clean(status)}']
    rows.append(f'start\t{snapshot["start"]}')
    rows.append(f'author_rate\t{snapshot["time_codes_per_second"]}')
    for layer in snapshot['layers']:
        label=layer['name'] if layer['editable'] else Path(layer['identifier']).name
        rows.append('\t'.join(['layer',clean(label),str(int(layer['editable'])),str(int(layer['selected']))]))
    rows.append('edit_target\t'+snapshot['edit_target'])
    rows.append('workspace\t'+clean(snapshot.get('workspace','')))
    rows.append('unsaved_changes\t'+str(int(snapshot.get('unsaved_changes',True))))
    rows.append('source_conflicts\t'+str(len(snapshot.get('source_conflicts',[]))))
    rows.append('edit_context\t'+clean(snapshot.get('edit_context','')))
    for layer in snapshot.get('working_layers',[]):
        rows.append('\t'.join(['working_layer',layer['name'],clean(layer['source']),str(int(layer['selected']))]))
    for prim in snapshot['prims'][:4096]:
        rows.append('\t'.join(['prim',prim['id'],prim['type'],clean(prim.get('stable_id',''))]))
        for name,variant in prim['variants'].items():
            rows.append('\t'.join(['variant',prim['id'],name,variant['selected']]+variant['choices']))
    rows.append('identity_issues\t'+str(len(snapshot.get('identity_issues',[]))))
    rows.append('total\t'+str(len(snapshot['prims'])))
    atomic(work/'state.tsv','\n'.join(rows)+'\n')
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path);p.add_argument('--workspace',type=Path);p.add_argument('--work',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--preview',action='store_true');args=p.parse_args()
    workspace=(args.workspace or args.output/'workspace').resolve()
    if not args.source and not (workspace/'workspace.json').is_file():p.error('Provide --source for a new workspace, or --workspace for an existing one')
    args.output.mkdir(parents=True,exist_ok=True)
    if not args.work.is_dir():raise ValueError('Missing owned IPC directory')
    signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(SystemExit(0)))
    sequence=0
    preview=preview_api.PreviewCooker(args.work, animated=True) if args.preview else None
    try:
      with module.WatchedStageSession() as stage:
          if (workspace/'workspace.json').is_file():
              snapshot=stage.request('open_workspace',source=str(workspace))
              if args.source and Path(snapshot['source'])!=args.source.resolve():raise ValueError('Workspace uses a different source; select another --workspace directory')
          else:snapshot=stage.request('open',source=str(args.source.resolve()))
          publish(args.work,snapshot,'READY: S workspace save / F6 USD delivery / P USDZ',sequence)
          while True:
              if preview:
                  preview.schedule(snapshot)
                  preview.tick(stage)
              request=args.work/'request.tsv'
              if request.exists():
                  if request.stat().st_size>16384:raise ValueError('USD panel request too large')
                  fields=request.read_text().strip('\n').split('\t')
                  if len(fields)>=2 and int(fields[0])>sequence:
                      sequence=int(fields[0]);op=fields[1]
                      try:
                          feedback=None
                          if op=='variant' and len(fields)==5:
                              stage.request(op,path=fields[2],set=fields[3],value=fields[4])
                          elif op=='curves' and len(fields)==4:
                              publish_curves(args.work,stage.request('curves',path=fields[2],time=float(fields[3])))
                          elif op=='set_key' and len(fields)==6:
                              feedback=stage.request('attribute',path=fields[2],name=fields[3],value=float(fields[4]),time=float(fields[5]))
                          elif op=='set_channel' and len(fields)==7:
                              feedback=stage.request(op,path=fields[2],name=fields[3],channel=int(fields[4]),value=float(fields[5]),time=float(fields[6]))
                          elif op=='set_spline_value' and len(fields)==6:
                              feedback=stage.request(op,path=fields[2],name=fields[3],value=float(fields[4]),time=float(fields[5]))
                          elif op=='set_interpolation' and len(fields)==5:
                              stage.request(op,path=fields[2],name=fields[3],mode=fields[4])
                          elif op=='set_tangent' and len(fields)==8:
                              stage.request(op,path=fields[2],name=fields[3],time=float(fields[4]),side=fields[5],slope=float(fields[6]),width=float(fields[7]))
                          elif op=='bake_curve' and len(fields)==8:
                              stage.request(op,path=fields[2],name=fields[3],start=float(fields[4]),end=float(fields[5]),step=float(fields[6]),max_error=float(fields[7]))
                          elif op=='convert_frame_rate' and len(fields)==3:
                              stage.request(op,rate=float(fields[2]))
                          elif op in ('move_spline_key','copy_spline_key') and len(fields)==6:
                              stage.request(op,path=fields[2],name=fields[3],from_time=float(fields[4]),time=float(fields[5]))
                          elif op=='delete_spline_key' and len(fields)==5:
                              stage.request(op,path=fields[2],name=fields[3],time=float(fields[4]))
                          elif op in ('move_key','copy_key') and len(fields)==6:
                              feedback=stage.request(op,path=fields[2],name=fields[3],from_time=float(fields[4]),time=float(fields[5]))
                          elif op=='delete_key' and len(fields)==5:
                              stage.request('clear_sample',path=fields[2],name=fields[3],time=float(fields[4]))
                          elif op in ('create_layer','select_layer') and len(fields)==3:stage.request(op,name=fields[2])
                          elif op=='cycle_source_target' and len(fields)==3:
                              targets=stage.request('source_targets',path=fields[2])['targets']
                              if not targets:raise ValueError('No writable source mapping for this prim; W creates working copies')
                              current=next((i for i,t in enumerate(targets) if t['name']==snapshot['edit_target'] and t['context']==snapshot.get('edit_context') and t['node']==snapshot.get('edit_node')), -1)
                              target=targets[(current+1)%len(targets)]
                              stage.request('select_source_layer',name=target['name'],context=target['context'],node=target['node'])
                          elif op=='select_source_layer' and len(fields)==5:
                              stage.request(op,name=fields[2],context=fields[3],node=int(fields[4]))
                          elif op=='resolve_sources' and len(fields)==3:stage.request(op,action=fields[2])
                          elif op=='clear_layer' and len(fields)==2:stage.request(op)
                          elif op in ('load','unload') and len(fields)==3:stage.request(op,path=fields[2])
                          elif op in ('assign_ids','repair_ids','reconcile_ids','begin_source_editing','reload','reset','undo','redo') and len(fields)==2:stage.request(op)
                          elif op=='save_workspace' and len(fields)==2:
                              stage.request(op,destination=str(workspace))
                              atomic(args.work/'last-workspace.txt',str(workspace)+'\n')
                          elif op=='open_workspace' and len(fields)==2:
                              if snapshot.get('unsaved_changes',True):raise ValueError('Save workspace changes before reopening')
                              stage.request(op,source=str(workspace))
                          elif op in ('save','package') and len(fields)==2:
                              destination=args.output/('edit-'+args.work.name+'-'+str(sequence)+('.usdz' if op=='package' else '.usda'))
                              stage.request(op,destination=str(destination.resolve()))
                              atomic(args.work/'last-export.txt',str(destination.resolve())+'\n')
                          else:raise ValueError('Unsupported panel command')
                          snapshot=stage.request('snapshot');status='OK '+op
                          if feedback and feedback.get('edit_feedback')=='masked_by_stronger_layer':status+=': masked by a stronger layer'
                      except Exception as error:
                          status='ERROR '+str(error)
                          try:snapshot=stage.request('snapshot')
                          except Exception:pass
                      publish(args.work,snapshot,status,sequence)
              while not stage.events.empty():
                  event=stage.events.get_nowait()
                  if event['operation']=='reload':
                      if 'error' in event:
                          try:snapshot=stage.request('snapshot')
                          except Exception:pass
                          publish(args.work,snapshot,'RELOAD ERROR '+event['error'],sequence)
                      else:
                          snapshot=stage.snapshot;publish(args.work,snapshot,'SOURCE RELOADED; local edits preserved',sequence)
              time.sleep(.025)
    finally:
      if preview:preview.close()
if __name__=='__main__':main()
