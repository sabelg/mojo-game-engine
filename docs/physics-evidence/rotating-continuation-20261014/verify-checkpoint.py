"""Read-only preservation check; not a numerical requalification."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
sources = json.loads((HERE / 'source-hashes.json').read_text())
receipts = json.loads((HERE / 'receipt-manifest.json').read_text())
for name, expected in sources.items():
    assert sha(ROOT / name) == expected, name
for name, record in receipts.items():
    assert sha(ROOT / name) == record['sha256'], name
print(f'PASS: {len(sources)} source files and {len(receipts)} receipts preserved')
