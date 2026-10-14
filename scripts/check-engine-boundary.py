"""Reject reverse source dependencies and accidental game content in the engine SDK."""
from pathlib import Path
import importlib.util,re
ROOT=Path(__file__).resolve().parents[1]
for folder in ['mojo_game','native','shaders']:
 for p in (ROOT/folder).rglob('*'):
  if p.suffix not in ['.mojo','.vert','.frag','.glsl']:continue
  text=p.read_text()
  assert not re.search(r'\b(?:from|import)\s+frankie\b',text),p
  assert 'yofrankie' not in text.lower() and 'third_party/' not in text,p
  assert 'yf_' not in text,p
  # Literal storage is generated numeric data; inspect decoded paths as well.
  for m in re.finditer(r'comptime c_literal_data_\d+:[^\n]+ = \[([^]]+)\]',text):
   decoded=bytes(map(int,m[1].split(','))).decode(errors='replace').lower()
   assert 'frankie' not in decoded and 'yofrankie' not in decoded,p
spec=importlib.util.spec_from_file_location('sdk',ROOT/'scripts/package-atlas.py');sdk=importlib.util.module_from_spec(spec);spec.loader.exec_module(sdk)
for name in sdk.engine_files():
 assert not any(word in name.lower() for word in ['frankie','games/','third_party/','art/']),name
print('Engine boundary passed: generic source only; no game imports, baked game paths or game content in SDK')
