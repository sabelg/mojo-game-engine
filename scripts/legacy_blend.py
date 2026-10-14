"""Compatibility launcher; the implementation belongs to games/yo-frankie."""
import os,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
os.chdir(root/"games/yo-frankie")
os.execv(sys.executable,[sys.executable,str(root/"games/yo-frankie/scripts/legacy_blend.py"),*sys.argv[1:]])
