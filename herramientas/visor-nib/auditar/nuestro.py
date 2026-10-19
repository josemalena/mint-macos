"""Lo de nuestra pieza, en la forma que esperan las reglas.

de_fuentes(rutas)      los literales de cadena de las fuentes (Vala, JS, Python): {"textos": [...], "revisar_sobra": True}
de_atspi(pid)          la app corriendo, por AT-SPI: {"textos": [...], "controles": [{texto, x, y, ancho, alto}], "ventana": {ancho, alto}}
de_menu1(xid)          los menús de una ventana por org.mintmacos.Menu1: {"menus": [{texto, items: [...]}]}
"""
import json
import re
import subprocess


def de_fuentes(rutas):
    textos = set()
    for ruta in rutas:
        with open(ruta, encoding="utf-8") as f:
            fuente = f.read()
        fuente = re.sub(r"/\*.*?\*/", "", fuente, flags=re.S)
        fuente = re.sub(r"(?m)^\s*//.*$", "", fuente)
        for m in re.finditer(r'"((?:[^"\\\n]|\\.)*)"', fuente):
            s = m.group(1).replace("\\n", " ").replace('\\"', '"')
            if len(s) >= 3 and re.search(r"[A-Za-z]{3}", s) and not s.startswith(("com.", "org.", "/", "gtk", "mp-", "-", ".")):
                textos.add(s)
    return {"textos": sorted(textos), "revisar_sobra": True}


def de_atspi(pid):
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
    escritorio = Atspi.get_desktop(0)
    app = None
    for i in range(escritorio.get_child_count()):
        a = escritorio.get_child_at_index(i)
        if a is not None and a.get_process_id() == pid:
            app = a
            break
    if app is None:
        return {"textos": [], "controles": [], "ventana": {}}
    textos, controles, ventana = [], [], {}
    pila = [(app, 0)]
    origen = None
    while pila:
        n, nivel = pila.pop(0)
        try:
            rol, nombre = n.get_role_name(), n.get_name() or ""
            comp = n.get_component_iface()
            ext = comp.get_extents(Atspi.CoordType.SCREEN) if comp else None
        except Exception:
            continue
        if rol == "frame" and origen is None and ext is not None:
            origen = (ext.x, ext.y)
            ventana = {"ancho": ext.width, "alto": ext.height}
        if nombre and rol in ("label", "push button", "check box", "radio button", "menu item", "combo box", "page tab"):
            textos.append(nombre)
            if ext is not None and origen is not None:
                controles.append({"texto": nombre, "x": ext.x - origen[0], "y": ext.y - origen[1], "ancho": ext.width, "alto": ext.height})
        try:
            for k in range(min(n.get_child_count(), 500)):
                h = n.get_child_at_index(k)
                if h is not None:
                    pila.append((h, nivel + 1))
        except Exception:
            pass
    return {"textos": textos, "controles": controles, "ventana": ventana}


def _gdbus(metodo, *args):
    cmd = ["gdbus", "call", "--session", "--dest", "org.mintmacos.Menu1", "--object-path", "/org/mintmacos/Menu1",
           "--method", "org.mintmacos.Menu1." + metodo, *map(str, args)]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout


def de_menu1(xid):
    """Los menús de una ventana, convertidos del texto de gdbus (a{sv}) a la forma de la regla de menús."""
    from gi.repository import GLib

    def leer(texto):
        # «(uint32 1, [{…}, …])» → GVariant
        v = GLib.Variant.parse(None, texto.strip().rstrip(","))
        return v.unpack()

    def ver(i):
        d = {"texto": i.get("etiqueta", ""), "atajo": i.get("atajo", ""), "id": i.get("id", ""), "separador": i.get("tipo") == "separador"}
        if i.get("hijos"):
            d["submenu"] = [ver(h) for h in i["hijos"]]
        return d

    menus = []
    barra = leer(_gdbus("Barra", xid))
    for m in barra[1]:
        abierto = leer(_gdbus("Abrir", xid, f"'{m['id']}'"))
        menus.append({"id": m["id"], "texto": m["etiqueta"], "items": [ver(i) for i in abierto[1]]})
    return {"menus": menus}
