#!/usr/bin/env python3
"""Recorre la interfaz org.mintmacos.Tienda1 como lo hará la ventana del App Store
y comprueba cada respuesta. Lo corre prueba.sh dentro de su bus aparte.

    cliente.py DIR_PRUEBA
"""
import json
import os
import sys
import time

from gi.repository import Gio, GLib

T = sys.argv[1]
NOMBRE, RUTA = "org.mintmacos.Tienda1", "/org/mintmacos/Tienda1"
FP = "flatpak:user/flathub/app/org.mintmacos.Juguete/x86_64/stable"
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
fallas = []
hechas = [0]


def comprobar(desc, ok, detalle=""):
    hechas[0] += 1
    if not ok:
        fallas.append(desc)
        print("  ✗ %s %s" % (desc, detalle))


def llamar(metodo, firma=None, args=(), tiempo=60000):
    r = bus.call_sync(NOMBRE, RUTA, NOMBRE, metodo, GLib.Variant(firma, args) if firma else None, None, 0, tiempo, None)
    return r.unpack()[0] if r is not None and len(r.unpack()) == 1 else (r.unpack() if r is not None else None)


senales = []


def al_recibir(con, remitente, ruta, iface, senal, params):
    senales.append((senal, params.unpack()))


bus.signal_subscribe(NOMBRE, NOMBRE, None, RUTA, None, 0, al_recibir)
ctx = GLib.MainContext.default()


def esperar_terminado(trabajo, limite=120):
    fin = time.time() + limite
    while time.time() < fin:
        while ctx.pending():
            ctx.iteration(False)
        for s, a in senales:
            if s == "Terminado" and a[0] == trabajo:
                return a
        time.sleep(0.05)
    return None


def ficha(id_):
    return llamar("Ficha", "(s)", (id_,))


# 1. La primera llamada arranca el servicio por activación y espera el índice.
t0 = time.time()
r = llamar("Buscar", "(sasu)", ("juguete", [], 10))
primera = time.time() - t0
print("  · primera llamada (activación + índice): %.2f s" % primera)
open(os.path.join(T, "primera-llamada"), "w").write("%.3f" % primera)
comprobar("Buscar: el nombre gana al resumen", [x["id"] for x in r] == [FP, "apt:juego-apt"], r)
r = llamar("Buscar", "(sasu)", ("juego", ["apt"], 10))
comprobar("Buscar con origen apt", [x["id"] for x in r] == ["apt:juego-apt"], r)
t0 = time.time()
llamar("Buscar", "(sasu)", ("juego", [], 10))
print("  · una búsqueda con el índice cargado: %.0f ms" % ((time.time() - t0) * 1000))

# 2. Secciones y categorías.
s = llamar("Secciones")
comprobar("Secciones trae create", any(x[0] == "create" and "Graphics" in x[2] for x in s))
r = llamar("ListarCategoria", "(suu)", ("games", 0, 50))
comprobar("ListarCategoria games", [x["id"] for x in r] == ["apt:juego-apt"], r)

# 3. Fichas.
f = ficha(FP)
comprobar("ficha: tamaño de descarga", f.get("tamano_descarga", 0) > 0, f)
comprobar("ficha: instalaciones del mes de Flathub", f.get("instalaciones_mes") == 1234 and f.get("fuente_instalaciones") == "flathub:/stats/org.mintmacos.Juguete", f)
comprobar("ficha: nota de ODRS", abs(f.get("nota", 0) - 3.75) < 0.01 and f.get("votos") == 4 and f.get("votos_por_estrella") == [1, 0, 0, 1, 2], f)
comprobar("ficha: no instalada", f.get("instalada") is False)
comprobar("ficha: capturas y descripción", f.get("capturas", [[""]])[0][0] == "https://img/juguete.png" and f.get("descripcion", "").startswith("<p>"), f)
f = ficha("apt:juego-apt")
comprobar("ficha apt: tamaño de PackageKit", f.get("tamano_instalada") == 4096000 and f.get("tamano_descarga") == 1024000, f)
comprobar("ficha apt: sin nota (ODRS no tiene)", "nota" not in f, f)

# 4. Estantes y reseñas.
e = {x[0]: x for x in llamar("Estantes", "(s)", ("discover",))}
comprobar("estante app del día", "app-del-dia" in e and [a["id"] for a in e["app-del-dia"][4]] == [FP], e.keys())
comprobar("estante populares: solo lo que está en el catálogo", [a["id"] for a in e.get("populares", ("", "", "", "", []))[4]] == [FP])
comprobar("estante populares dice su fuente", e.get("populares", ("",) * 4)[3] == "flathub:/collection/popular")
comprobar("estante vacío no viene", "nuevas" not in e and "apps-de-la-semana" not in e, list(e))
r = llamar("Resenas", "(su)", ("org.mintmacos.Juguete", 10))
comprobar("reseñas: sin las reportadas", len(r) == 1 and r[0].get("autor") == "Ana" and r[0].get("nota") == 5.0, r)

# 5. Instalar el Flatpak: progreso, Terminado e InstaladasCambiaron.
t = llamar("Instalar", "(s)", (FP,))
fin = esperar_terminado(t)
comprobar("instalar Flatpak termina bien", fin is not None and fin[1] is True, fin)
prog = [a for s_, a in senales if s_ == "Progreso" and a[0] == t]
comprobar("instalar Flatpak manda progreso hasta 100", prog and prog[-1][1] == 100 and all(prog[i][1] <= prog[i + 1][1] for i in range(len(prog) - 1)), [p[1] for p in prog])
comprobar("InstaladasCambiaron trae el Flatpak", any(s_ == "InstaladasCambiaron" and FP in a[0] for s_, a in senales))
comprobar("la ficha dice instalada", ficha(FP).get("instalada") is True)

# 6. APT por PackageKit.
t = llamar("Instalar", "(s)", ("apt:juego-apt",))
fin = esperar_terminado(t)
comprobar("instalar apt termina bien", fin is not None and fin[1] is True, fin)
comprobar("apt: la ficha dice instalada (dpkg cambió)", ficha("apt:juego-apt").get("instalada") is True)
etapas = {a[2] for s_, a in senales if s_ == "Progreso" and a[0] == t}
comprobar("apt: pasa por autorizando y descargando", {"autorizando", "descargando"} <= etapas, etapas)
t = llamar("Instalar", "(s)", ("apt:prohibido",))
fin = esperar_terminado(t)
comprobar("polkit cancelado da sin-autorizacion", fin is not None and fin[1] is False and fin[2] == "sin-autorizacion", fin)

# 7. Actualizaciones en dos.
a = {x["id"]: x for x in llamar("Actualizaciones", "(s)", ("apps",))}
comprobar("apps: el paquete con ficha", "apt:editor-viejo" in a and a["apt:editor-viejo"].get("version") == "2.0" and a["apt:editor-viejo"].get("version_instalada") == "1.0", a)
comprobar("apps: sin lo del sistema", "apt:libalgo" not in a, a)
s_ = {x["id"]: x for x in llamar("Actualizaciones", "(s)", ("sistema",))}
comprobar("sistema: el paquete sin ficha", "apt:libalgo" in s_ and "apt:editor-viejo" not in s_, s_)
t = llamar("Actualizar", "(sas)", ("sistema", []))
fin = esperar_terminado(t)
comprobar("actualizar el sistema termina bien", fin is not None and fin[1] is True, fin)
log = open(os.path.join(T, "pk.log")).read()
comprobar("PackageKit recibió UpdatePackages de libalgo", 'UpdatePackages [2, ["libalgo;1.1;amd64;ubuntu"]]' in log, log[-300:])
comprobar("SetHints interactivo", '"interactive=true"' in log)

# 8. Quitar el Flatpak.
t = llamar("Quitar", "(s)", (FP,))
fin = esperar_terminado(t)
comprobar("quitar Flatpak termina bien", fin is not None and fin[1] is True, fin)
comprobar("la ficha ya no dice instalada", ficha(FP).get("instalada") is False)

# 8b. Un ícono que solo está en la red: la primera vez viene la URL y se baja.
r = llamar("Buscar", "(sasu)", ("remoto", [], 5))
url = r[0].get("icono", "") if r else ""
comprobar("ícono remoto: primero la URL", url.startswith("http://127.0.0.1:"), r)
fin = time.time() + 15
listo = None
while time.time() < fin and not listo:
    while ctx.pending():
        ctx.iteration(False)
    listo = next((a for s_, a in senales if s_ == "IconoListo" and a[0] == url), None)
    time.sleep(0.05)
comprobar("IconoListo con la ruta bajada", listo is not None and os.path.isfile(listo[1]), listo)
r = llamar("Buscar", "(sasu)", ("remoto", [], 5))
comprobar("ícono remoto: después la ruta", r and listo and r[0].get("icono") == listo[1], r)

# 9. El salto de versión y el estado.
v = llamar("NuevaVersion")
comprobar("NuevaVersion: el salto menor", v.get("tipo") == "menor" and v.get("herramienta") == "mint-release-upgrade", v)
comprobar("sin trabajos al final", llamar("Trabajos") == [])
props = bus.call_sync(NOMBRE, RUTA, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (NOMBRE,)), None, 0, -1, None).unpack()[0]
comprobar("propiedades", props.get("Ocupado") is False and ("flatpak", "Flatpak", True) in props.get("Origenes", []), props)

print("  %s %d de %d comprobaciones" % ("✓" if not fallas else "✗", hechas[0] - len(fallas), hechas[0]))
sys.exit(1 if fallas else 0)
