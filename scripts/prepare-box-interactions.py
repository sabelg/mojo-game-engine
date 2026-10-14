"""Freeze a reproducible local interacting-box case matrix before qualification."""
import datetime,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'build/physics-box-interactions'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True);design=ROOT/'experimental/physics_gpu/BOX_INTERACTIONS_DESIGN.md';matrix=ROOT/'experimental/physics_gpu/BOX_INTERACTIONS_CASES.json';cases=json.loads(matrix.read_text());assert len(cases)==70
 existing=OUT/'predeclared.json'
 if existing.exists():
  old=json.loads(existing.read_text());assert digest(design)==old['design_sha256'] and digest(matrix)==old['case_matrix_sha256'];assert digest(OUT/'cases.json')==digest(matrix)
  print('Existing frozen declaration and case matrix retained');return
 (OUT/'cases.json').write_bytes(matrix.read_bytes())
 paths=list((ROOT/'experimental/physics_gpu').glob('*'))+list((ROOT/'games/yo-frankie/examples').glob('*'))+[ROOT/n for n in ['docs/PHYSICS_ROADMAP.md','build/mojo_game.mojoc','build/libmojo_graphics.a','build/mojo-game-source.tar.gz','build/atlas-release-manifest.json','games/yo-frankie/build/yo-frankie','pixi.lock','.deps/physics-gpu-g01/pixi.lock']]
 (OUT/'baseline.json').write_text(json.dumps({str(p.relative_to(ROOT)):digest(p) for p in paths if p.is_file()},indent=2)+'\n')
 (OUT/'predeclared.json').write_text(json.dumps({'recorded_at_UTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'design_path':str(design),'design_sha256':digest(design),'case_matrix_sha256':digest(matrix),'case_count':70,'execution_started':False},indent=2)+'\n')
 print('Frozen design and70 cases; no native/GPU work launched')
if __name__=='__main__':main()
