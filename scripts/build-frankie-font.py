"""Bake a redistributable Liberation Sans Bold ASCII atlas for the native HUD."""
from pathlib import Path
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
out=root/'assets/ui'
out.mkdir(parents=True,exist_ok=True)
font=Path('/usr/share/fonts/liberation/LiberationSans-Bold.ttf')
license_path=Path('/usr/share/licenses/ttf-liberation/LICENSE')
if not font.exists() or not license_path.exists():
    raise SystemExit('Install the Liberation fonts (including their license) to rebuild the atlas.')
args=['magick','-size','1024x384','xc:none','-font',str(font),'-pointsize','52','-fill','white']
for index in range(96):
    char=chr(index+32)
    if char=='\x7f': char='?'
    char=char.replace('\\','\\\\').replace('"','\\"')
    args+=['-draw',f'text {index%16*64+5},{index//16*64+50} "{char}"']
subprocess.run(args+['BMP:'+str(out/'frankie-font.bmp')],check=True)
shutil.copy2(license_path,out/'FONT-LICENSE.txt')
print('Built smooth ASCII atlas:',out/'frankie-font.bmp')
