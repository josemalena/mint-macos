#!/usr/bin/env python3
"""Genera src/gpus.rs: el nombre de mercado de las GPU de Intel por id PCI
(«Intel HD Graphics 4000» para 8086:0166), de las tablas de Mesa en un tag fijo.

Mint no instala esas tablas (vienen dentro de libgallium, comprimidas), así que se
bajan de Mesa al construir y se guardan en el código; mint-macos-equipo las lee al
arrancar sin GL. Mesa es MIT. Las de AMD no hacen falta: /usr/share/libdrm/amdgpu.ids
ya está en el sistema y se lee en tiempo de arranque.

    rust/equipo/generar-gpus.py            baja y escribe src/gpus.rs
    MESA_TAG=mesa-25.3.0 …                 otro tag
"""
import os
import re
import sys
import urllib.request

TAG = os.environ.get("MESA_TAG", "mesa-25.2.8")
ARCHIVOS = ["crocus_pci_ids.h", "iris_pci_ids.h"]
BASE = "https://gitlab.freedesktop.org/mesa/mesa/-/raw/{tag}/include/pci_ids/{f}"
LINEA = re.compile(r'^CHIPSET\(0x([0-9a-fA-F]{4}),\s*\w+,\s*"[^"]*",\s*"([^"]+)"\)')


def limpiar(n):
    # Como lo escribe la Mac: sin (R) ni (TM).
    return re.sub(r"\s+", " ", n.replace("(R)", "").replace("(TM)", "")).strip()


def main():
    filas = {}
    cuentas = []
    for f in ARCHIVOS:
        url = BASE.format(tag=TAG, f=f)
        t = urllib.request.urlopen(url, timeout=30).read().decode()
        n = 0
        for l in t.splitlines():
            m = LINEA.match(l.strip())
            if m:
                filas.setdefault(m.group(1).lower(), limpiar(m.group(2)))
                n += 1
        if n == 0:
            sys.exit("✗ %s no trajo ninguna línea CHIPSET: cambió el formato" % url)
        cuentas.append((f, url, n))
    sal = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", "gpus.rs")
    with open(sal, "w") as o:
        o.write("// GENERADO por generar-gpus.py: no editar a mano.\n")
        o.write("// Nombres de mercado de las GPU de Intel, de Mesa %s (licencia MIT):\n" % TAG)
        for f, url, n in cuentas:
            o.write("//   %-18s %s  (%d ids)\n" % (f, url, n))
        o.write("//\n// (device id de PCI con vendor 8086, nombre sin (R) ni (TM)).\n\n")
        o.write("#[allow(dead_code)]\npub const MESA_TAG: &str = \"%s\";\n\n" % TAG)
        o.write("pub const INTEL: &[(u16, &str)] = &[\n")
        for k in sorted(filas):
            o.write('    (0x%s, "%s"),\n' % (k, filas[k].replace("\\", "\\\\").replace('"', '\\"')))
        o.write("];\n")
    print("src/gpus.rs: %d ids de Mesa %s" % (len(filas), TAG))


if __name__ == "__main__":
    main()
