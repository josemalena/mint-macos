"""Regla 4: los menús, sus ítems, su orden y sus atajos.

mac / nuestro: {"menus": [{"id": "file", "texto": "File", "items": [ITEM…]}, …]} con
ITEM = {"texto": "Close", "atajo": "⌘W", "id": "performClose:", "separador": false, "submenu": [ITEM…]}
(el perfil da `items`/`submenu` así; org.mintmacos.Menu1 da etiqueta/atajo/hijos y nuestro.py lo convierte).
Gravedades: falta (un ítem de la Mac no está), texto (parecido), atajo (distinto o ausente), orden (los dos están pero cambiaron de lugar
respecto a los demás), sobra (un ítem nuestro que la Mac no tiene).
"""
import difflib

from . import fila, norm

REGLA = "menús"


def _planos(items, ruta):
    """[(ruta, ítem)] de los que no son separadores, en orden."""
    for it in items or []:
        if it.get("separador"):
            continue
        yield ruta + [it["texto"]], it
        yield from _planos(it.get("submenu"), ruta + [it["texto"]])


def _clave(ruta):
    return " ▸ ".join(norm(p) for p in ruta)


def revisar(mac, nuestro):
    filas = []
    for m in mac.get("menus", []):
        n = next((x for x in nuestro.get("menus", []) if norm(x["texto"]) == norm(m["texto"])), None)
        if n is None:
            filas.append(fila(REGLA, f"menú {m['texto']}", "está", "no está", "falta"))
            continue
        suyos = {_clave(r): (r, it) for r, it in _planos(n.get("items"), [])}
        orden_mac, orden_suyo = [], []
        vistos = set()
        for r, it in _planos(m.get("items"), []):
            k = _clave(r)
            vistos.add(k)
            donde = f"{m['texto']} ▸ " + " ▸ ".join(r)
            if k in suyos:
                _, ours = suyos[k]
                orden_mac.append(k)
                orden_suyo.append(k)
                a_mac, a_nu = (it.get("atajo") or "").replace(" ", ""), (ours.get("atajo") or "").replace(" ", "")
                if a_mac != a_nu:
                    filas.append(fila(REGLA, donde, a_mac or "sin atajo", a_nu or "sin atajo", "atajo"))
                continue
            cerca = difflib.get_close_matches(k, list(suyos), n=1, cutoff=0.8)
            if cerca:
                filas.append(fila(REGLA, donde, it["texto"], suyos[cerca[0]][1]["texto"], "texto"))
                orden_mac.append(k)
                orden_suyo.append(cerca[0])
            else:
                filas.append(fila(REGLA, donde, "está", "no está", "falta"))
        # el orden de los que están en los dos lados: el de la Mac contra el nuestro
        posiciones = {k: i for i, k in enumerate(suyos)}
        ordenados = sorted(orden_suyo, key=lambda x: posiciones[x])
        if orden_suyo != ordenados:
            filas.append(fila(REGLA, f"menú {m['texto']}", " → ".join(orden_mac), " → ".join(ordenados), "orden"))
        for k, (r, ours) in suyos.items():
            if k not in vistos and k not in orden_suyo:
                filas.append(fila(REGLA, f"{m['texto']} ▸ " + " ▸ ".join(r), "no está", ours["texto"], "sobra"))
    return filas
