"""Telemetry parser checks against independent known distributions and corrupt logs."""
import importlib.util,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('atlas_report',ROOT/'scripts/report-atlas-benchmark.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
 path=Path(directory)/'samples.tsv'
 source='device\tfixture\n'+''.join(f'frame\t{i}\t-1\t1\t3\n' for i in range(1,101))+'measured\t100\t1\t0\nvalidation\t0\n'
 path.write_text(source)
 result=module.report(path,{'frozen':'identity'})
 assert result['host']=={'median_ms':50.5,'p95_ms':95.0,'p99_ms':99.0,'max_ms':100.0}
 assert result['gpu'] is None and result['identity']=={'frozen':'identity'}
 for invalid in [source.replace('validation\t0','validation\t1'),source.replace('measured\t100','measured\t99'),source.replace('frame\t1\t-1','frame\tnan\t-1'),source.replace('frame\t1\t-1\t1\t3','frame\t1\t-1\t1')]:
  path.write_text(invalid)
  try:module.report(path)
  except ValueError:pass
  else:raise AssertionError('Invalid telemetry accepted')
print('Benchmark reports passed: percentiles, unavailable GPU timers, frozen identity, invalid/incomplete logs')
