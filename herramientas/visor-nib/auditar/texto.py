"""Regla 1: los textos visibles.

mac:    {"textos": [{"texto": "Show scroll bars:", "clase": "TextField"}, …]}   (del perfil o del nib; lo oculto ya viene fuera)
nuestro: {"textos": ["Show scroll bars:", …]}                                    (de las fuentes o de AT-SPI)
Gravedades: falta (el texto de la Mac no está), texto (hay uno parecido pero distinto), sobra (lo nuestro que la Mac no tiene; solo si
nuestro["revisar_sobra"] es true, porque los literales de una fuente incluyen ids y datos).
"""
import difflib

from . import fila, norm

REGLA = "texto"
PARECIDO = 0.72


def revisar(mac, nuestro):
    filas = []
    suyos = {norm(t): t for t in nuestro.get("textos", [])}
    vistos = set()
    for it in mac.get("textos", []):
        t = it["texto"] if isinstance(it, dict) else it
        n = norm(t)
        if len(n) < 2 or n in vistos:
            continue
        vistos.add(n)
        if n in suyos:
            continue
        cerca = difflib.get_close_matches(n, list(suyos), n=1, cutoff=PARECIDO)
        if cerca:
            filas.append(fila(REGLA, "texto", t, suyos[cerca[0]], "texto"))
        else:
            filas.append(fila(REGLA, "texto", t, "no está", "falta"))
    if nuestro.get("revisar_sobra"):
        for n, t in sorted(suyos.items()):
            if n not in vistos and not difflib.get_close_matches(n, list(vistos), n=1, cutoff=PARECIDO):
                filas.append(fila(REGLA, "texto", "no está", t, "sobra"))
    return filas
