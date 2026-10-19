"""Las reglas de `mac-visor-nib auditar`: cada una compara lo que dice la Mac (el perfil de la versión activa o el nib) con lo que tiene
nuestra pieza y devuelve filas. Un archivo por regla, cada uno con `revisar(mac, nuestro) -> [filas]`:

    texto.py       los textos visibles (etiquetas, botones, opciones de popup)
    menus.py       los menús: ítems, orden y atajos
    geometria.py   el tamaño de la ventana y el orden de arriba abajo de los controles

`nuestro.py` saca lo de nuestra pieza: de sus fuentes (literales), de la app corriendo (AT-SPI) o de org.mintmacos.Menu1.
Los datos de la Mac no entran al repo: se leen de ~/.local/share/mint-macos/ (perfiles y nib exportados) cuando se corre.

Una fila es un dict: {regla, que, mac, nuestro, gravedad, nota}. Gravedades: falta, texto, orden, sobra, tamaño, atajo.
"""

GRAVEDADES = ("falta", "texto", "orden", "sobra", "tamaño", "atajo")


def fila(regla, que, mac, nuestro, gravedad, nota=""):
    assert gravedad in GRAVEDADES, gravedad
    return {"regla": regla, "que": que, "mac": mac, "nuestro": nuestro, "gravedad": gravedad, "nota": nota}


def a_markdown(filas, titulo=""):
    """Las filas como la tabla de referencias/auditoria-nib/<pieza>.md."""
    out = [f"# {titulo}\n"] if titulo else []
    out.append("| Regla | Qué | La Mac dice | Lo nuestro tiene | Gravedad | Nota |\n|---|---|---|---|---|---|")
    for f in filas:
        out.append(f"| {f['regla']} | {f['que']} | {f['mac']} | {f['nuestro']} | {f['gravedad']} | {f['nota']} |")
    por = {}
    for f in filas:
        por[f["gravedad"]] = por.get(f["gravedad"], 0) + 1
    out.append("\n" + ", ".join(f"{n} {g}" for g, n in sorted(por.items())) if por else "\nSin diferencias.")
    return "\n".join(out) + "\n"


def norm(s):
    """El texto sin lo que no cambia el sentido: espacios, puntos suspensivos, dos puntos, mayúsculas, comillas tipográficas."""
    import re
    s = (s or "").replace("’", "'").replace("…", "...").replace("“", '"').replace("”", '"')
    s = re.sub(r"\s+", " ", s.strip())
    return re.sub(r"[\s:.]+$", "", s).lower()
