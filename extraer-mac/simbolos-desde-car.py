#!/usr/bin/env python3
"""simbolos-desde-car.py --recursos DIR --version V --salida DIR — los SF Symbols de CoreGlyphs, sacados EN LINUX del Assets.car de un disco de Mac montado,
para versiones de las que no hay una Mac encendida (Catalina). Es el equivalente del paso «simbolos» de extraer-mac/car-mac.js (que usa CoreUI en una Mac).

  --recursos DIR   .../System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources (con Assets.car y name_aliases.strings)
  --version V      10.15.8 (el tema se llama Mint-Macos-V)
  --salida DIR     de ahí sale DIR/iconos-simbolicos/Mint-Macos-V/ con index.theme, scalable/<contexto>/<nombre>-symbolic.svg, simbolos.tsv,
                   descartados.tsv y cuenta.tsv (la misma forma que la salida de car-mac). Luego: iconos/construir-tema-macos.py V

Las renditions SVG de Catalina vienen en un envoltorio DWAR con LZFSE (car.lzfse); aquí el peso es el atributo 26 y el tamaño el 27, al revés que en
Monterey. Se elige Regular tamaño M, sin color (solo negro), width y height 16 y viewBox cuadrado centrado, como car-mac. La tabla SF → freedesktop
es extraer-mac/simbolos-freedesktop.tsv; lo que no existe en esa versión va a descartados.tsv, nada se inventa. Son de Apple: la salida se queda
en referencias, nunca en el repo."""
import argparse
import sys,struct,re,collections,os,plistlib
AQUI=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,os.path.join(AQUI,'..','tema','iconos'))
import car
ap=argparse.ArgumentParser()
ap.add_argument('--recursos',required=True); ap.add_argument('--version',required=True); ap.add_argument('--salida',required=True)
A=ap.parse_args()
R=A.recursos
TEMA=os.path.join(A.salida,'iconos-simbolicos','Mint-Macos-'+A.version)
cat=car.Catalogo(R+'/Assets.car')
al=plistlib.load(open(R+'/name_aliases.strings','rb'))
tabla={}
for l in open(os.path.join(AQUI,'simbolos-freedesktop.tsv')):
    if not l.strip() or l[0]=='#': continue
    sf,fd,ctx=l.rstrip('\n').split('\t'); tabla[sf]=(fd,ctx)
CTX={'Actions':'actions','Places':'places','Status':'status','Devices':'devices','Categories':'categories','Applications':'apps','Emblems':'emblems','MimeTypes':'mimetypes'}
def txt(im):
    d=im.datos
    n=struct.unpack('<I',d[8:12])[0]; p=d[12:12+n]
    if p[:3]==b'bvx': return car.lzfse(p,struct.unpack('<I',p[4:8])[0]).decode()
    return p.decode()
por=collections.defaultdict(list); bitmap=set()
for atr,im in cat.imagenes():
    n=im.faceta or im.nombre
    if im.pixeles!='SVG' or im.datos[:4]!=b'DWAR': bitmap.add(n); continue
    w=atr.get('26',0); s=atr.get('27',0)
    nota=(1000 if atr.get('apariencia') else 0)+abs(w-4)*10+{2:0,1:1,3:2}.get(s,3)+(0.5 if (atr.get('escala') or 1)>1 else 0)
    por[n].append((nota,im,atr))
COL=re.compile(r'(fill|stroke|stop-color|color)\s*(?:=\s*["\']([^"\']*)["\']|:\s*([^;"\'}]+))',re.I)
def solo_negro(v): return re.fullmatch(r'(none|currentcolor|black|#000|#000000|#000000ff|rgb\(0,0,0\)|inherit|)',v.strip().lower().replace(' ',''))
def f(x):
    v = float(x)
    return '0' if abs(v) < 5e-5 else ('%.4f' % v).rstrip('0').rstrip('.')
def simb(t):
    t=re.sub(r'<\?xml[\s\S]*?\?>|<!--[\s\S]*?-->|<!DOCTYPE[^>]*>|<style\b[\s\S]*?</style>','',t,flags=re.I)
    m=re.search(r'<svg\b([^>]*)>([\s\S]*)</svg>\s*$',t)
    if not m: return None,'no es un <svg>',''
    cuerpo=m.group(2)
    if re.search(r'<(image|linearGradient|radialGradient|pattern|mask|filter)\b',cuerpo): return None,'trae imagen, degradado, patrón, máscara o filtro',''
    cols=set()
    for mm in COL.finditer(cuerpo):
        v=(mm.group(2) or mm.group(3) or '').strip().lower().replace(' ','')
        if not solo_negro(v): cols.add((mm.group(1).lower(),v))
    if cols:
        return None,'color distinto de negro (fill/stroke)',' '.join(sorted(a+'='+b for a,b in cols))
    a=m.group(1)
    cw=float(re.search(r'\swidth="([\d.]+)',a).group(1)); ch=float(re.search(r'\sheight="([\d.]+)',a).group(1))
    vb=re.search(r'viewBox="([^"]*)"',a)
    if vb: vx,vy,vw,vh=map(float,vb.group(1).split())
    else: vx,vy,vw,vh=0,0,cw,ch
    cuerpo=re.sub(r'\s+fill\s*=\s*"(?!none)[^"]*"','',cuerpo)
    L=max(cw,ch)
    svg=('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="16" height="16" viewBox="%s %s %s %s">'%(f(-(L-cw)/2),f(-(L-ch)/2),f(L),f(L)))+re.sub(r'>\s+<','><',cuerpo.strip())+'</svg>\n'
    return svg,'',''
# alias: viejo->nuevo; en Catalina el nombre del car puede ser el viejo o el nuevo
inv={v:k for k,v in al.items()} if isinstance(al,dict) else {}
os.makedirs(TEMA,exist_ok=True)
filas=['icono\tcontexto\tnombre_sf\talias\tclase\tatributos\tcolores_quitados\trecorte\tcar']
fuera=['nombre_sf\tclase\tmotivo\tdetalle\tcar']
hechos=set(); dirs={}; ok=0; nok=collections.Counter(); mapeados=[]
CAR='/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/Assets.car'
for n in sorted(por):
    nota,im,atr=sorted(por[n],key=lambda x:x[0])[0]
    svg,mot,det=simb(txt(im))
    if not svg:
        fuera.append('\t'.join([n,'SVG',mot,det,CAR])); nok[mot]+=1; continue
    ent=tabla.get(n) or (tabla.get(inv.get(n)) if inv.get(n) else None)
    icono=ent[0] if ent else car.archivo(n); ctx=CTX[ent[1]] if ent else 'sf'
    if icono in hechos: nok['nombre repetido']+=1; continue
    d=f'{TEMA}/scalable/{ctx}'; os.makedirs(d,exist_ok=True); dirs[ctx]=ent[1] if ent else 'SF Symbols'
    open(f'{d}/{icono}-symbolic.svg','w').write(svg); hechos.add(icono); ok+=1
    if ent: mapeados.append(n)
    filas.append('\t'.join([icono,ctx,n,'' if not ent or tabla.get(n) else inv.get(n,''),'SVG',' '.join(f'{k}={v}' for k,v in atr.items() if k!='identificador'),'','',CAR]))
for n in sorted(bitmap-set(por)):
    fuera.append('\t'.join([n,'mapa de bits','solo mapa de bits, sin vector','',CAR])); nok['solo mapa de bits (sin vector)']+=1
# tabla: qué falta
faltan=[sf for sf in tabla if sf not in mapeados and not (sf in al and al[sf] in mapeados)]
for sf in faltan:
    fuera.append('\t'.join([sf,'(tabla)','no existe en Catalina (SF Symbols 1.x) o no se pudo convertir',tabla[sf][0],CAR]))
ds=sorted(dirs)
open(TEMA+'/index.theme','w').write('\n'.join(['[Icon Theme]','Name=Mint-Macos-'+A.version,'Comment=Glifos de macOS '+A.version+', sacados de su CoreGlyphs Assets.car desde Linux (car.py). Son de Apple: no se distribuyen.','Inherits=Mint-Y,Adwaita,hicolor','Directories='+','.join('scalable/'+c for c in ds),'']+sum([[f'[scalable/{c}]',f'Context={dirs[c]}','Size=16','MinSize=8','MaxSize=512','Type=Scalable',''] for c in ds],[])))
open(TEMA+'/simbolos.tsv','w').write('\n'.join(filas)+'\n')
open(TEMA+'/descartados.tsv','w').write('\n'.join(fuera)+'\n')
c=['tipo\tsacado\tno_sacado\tmotivo','SVG (nombre original)\t%d\t0\t'%(ok-len(mapeados)),'SVG (tabla)\t%d\t0\t'%len(mapeados)]
for k,v in nok.items(): c.append(f'SVG\t\t{v}\t{k}')
open(TEMA+'/cuenta.tsv','w').write('\n'.join(c)+'\n')
print(len(por),'nombres con SVG;',ok,'sacados;',len(mapeados),'de la tabla;',len(bitmap-set(por)),'solo bitmap');print(dict(nok));print('faltan tabla:',faltan)
