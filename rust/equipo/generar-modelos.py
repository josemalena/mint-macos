#!/usr/bin/python3
"""Arma src/modelos.rs, la tabla identificador → nombre comercial de cada Mac.

La fuente son las páginas de Apple para identificar cada modelo («Identify your
… model», support.apple.com/en-us/…). De cada una se toma el nombre del modelo
(el encabezado de su bloque) y su «Model Identifier». Un identificador que Apple
usa para más de un modelo (iMac15,1: Mid 2015 y Late 2014) se queda con todos,
en el orden de la página: por DMI no se distinguen.

Uso:
    ./generar-modelos.py              baja las páginas y reescribe src/modelos.rs
    ./generar-modelos.py --desde DIR  usa las páginas ya bajadas (DIR/<número>.html)

Es una herramienta de construcción: el binario no la necesita. Se vuelve a correr
cuando Apple saque un modelo nuevo, y el diff de modelos.rs dice qué cambió.
"""
import argparse
import datetime
import html
import os
import re
import sys
import urllib.request

PAGINAS = [
    ("102852", "Mac mini"),
    ("108054", "iMac"),
    ("103257", "MacBook"),
    ("102869", "MacBook Air"),
    ("108052", "MacBook Pro"),
    ("102887", "Mac Pro"),
    ("102231", "Mac Studio"),
]
URL = "https://support.apple.com/en-us/{}"

# Un bloque empieza con su nombre: un encabezado (<h2>…) o un párrafo entero en
# negrita (la página del MacBook). Su identificador viene después.
NOMBRE = re.compile(r'<h[234][^>]*>(.*?)</h[234]>|<p class="gb-paragraph"><b>([^<]*)</b></p>', re.S)
ID = re.compile(r"Model Identifier:?\s*(?:</b>)?:?\s*(.*?)</p>", re.S)
UN_ID = re.compile(r"[A-Za-z]+\d+,\d+")


def limpio(x):
    return html.unescape(re.sub(r"<[^>]+>", "", x)).strip()


def leer(numero, desde):
    if desde:
        with open(os.path.join(desde, f"{numero}.html"), encoding="utf-8") as f:
            return f.read()
    pedido = urllib.request.Request(URL.format(numero), headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(pedido, timeout=30) as r:
        return r.read().decode("utf-8")


def tabla_de(texto, numero):
    """[(identificador, [nombres])] en el orden de la página."""
    eventos = sorted([(m.start(), "nombre", limpio(m.group(1) or m.group(2))) for m in NOMBRE.finditer(texto)]
                     + [(m.start(), "id", limpio(m.group(1))) for m in ID.finditer(texto)])
    out = {}
    nombre = None
    ids = 0
    for _, tipo, valor in eventos:
        if tipo == "nombre":
            nombre = valor
            continue
        ids += 1
        if not nombre:
            sys.exit(f"{numero}: un identificador sin nombre antes: {valor!r}")
        # «Mac16,10, Mac16,11» y «Macmini6,1; Macmini6,2»: la coma de adentro no lleva espacio
        for i in re.split(r";\s*|,\s+|\s+and\s+", valor):
            i = i.strip().rstrip(".")
            if not i:
                continue
            if not UN_ID.fullmatch(i):
                sys.exit(f"{numero}: identificador raro {i!r} en {valor!r}")
            nombres = out.setdefault(i, [])
            if nombre not in nombres:
                nombres.append(nombre)
    if ids == 0:
        sys.exit(f"{numero}: la página no trae ningún «Model Identifier» (¿cambió el formato?)")
    return out, ids


def rust(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("--desde")
    a = p.parse_args()

    filas = []
    vistos = {}
    resumen = []
    for numero, familia in PAGINAS:
        t, ids = tabla_de(leer(numero, a.desde), numero)
        resumen.append(f"//   {familia:<12} {URL.format(numero)}  ({ids} bloques, {len(t)} identificadores)")
        for ident, nombres in t.items():
            if ident in vistos:
                sys.exit(f"{ident} sale en {vistos[ident]} y en {numero}")
            vistos[ident] = numero
            filas.append((ident, nombres, numero))

    hoy = datetime.date.today().strftime("%d-%m-%Y")
    lineas = [
        "// GENERADO por generar-modelos.py: no editar a mano.",
        f"// Sacado el {hoy} de las páginas de Apple para identificar cada modelo:",
        *resumen,
        "//",
        "// (identificador, nombres comerciales en el orden de la página, página de Apple).",
        "// Más de un nombre: Apple usa ese identificador para varios modelos.",
        "",
        "pub const MODELOS: &[(&str, &[&str], &str)] = &[",
    ]
    for ident, nombres, numero in filas:
        lineas.append(f"    ({rust(ident)}, &[{', '.join(rust(n) for n in nombres)}], {rust(URL.format(numero))}),")
    lineas.append("];")
    destino = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src", "modelos.rs")
    with open(destino, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas) + "\n")
    varios = sum(1 for f in filas if len(f[1]) > 1)
    print(f"{destino}: {len(filas)} identificadores ({varios} con más de un modelo)")


if __name__ == "__main__":
    main()
