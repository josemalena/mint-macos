#!/usr/bin/env python3
# Antes de correr: ningún caso (ni lib.sh, ni sesion.sh) puede matar procesos por nombre sin filtro de
# sandbox. Tres veces el 18 y el 19-10-2026 una prueba mató algo de la sesión de José: los residentes, su
# xss-lock y su Edge (un `pkill -x msedge`). Se marca pkill, killall y pgrep -u, salvo que en esa línea o en
# las dos siguientes se filtre por el entorno de la prueba (environ, HOME=, XDG_RUNTIME_DIR, la marca
# MINT_MACOS_PRUEBA, un perfil bajo $HOME o DISPLAY), o que la línea diga «# sandbox: <por qué>».
# Sale con 1 y lista las líneas si encuentra alguna.
import re, sys
PELIGRO = re.compile(r'\b(pkill|killall)\b|\bpgrep\b[^|#]*-u\b')
FILTRO = re.compile(r'environ|HOME=|\$HOME/|XDG_RUNTIME_DIR|MINT_MACOS_PRUEBA|DISPLAY=|# sandbox:')
malas = []
for ruta in sys.argv[1:]:
    lineas = open(ruta, encoding='utf-8', errors='replace').read().splitlines()
    for i, l in enumerate(lineas):
        codigo = l.split('#', 1)[0] if not l.lstrip().startswith('#') else ''
        if not PELIGRO.search(codigo):
            continue
        if any(FILTRO.search(x) for x in lineas[i:i + 3]):
            continue
        malas.append(f'{ruta}:{i + 1}: {l.strip()}')
if malas:
    print('✗ matan procesos por nombre sin filtro de sandbox (mataría lo de José):')
    print('\n'.join('    ' + m for m in malas))
    sys.exit(1)
