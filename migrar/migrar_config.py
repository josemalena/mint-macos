#!/usr/bin/env python3
"""La segunda parte del migrador (José, 18-10-2026): «leer el avatar, el fondo de pantalla y los
archivos de configuración de la Mac y convertirlos al formato que usan sus equivalentes en Linux».
La primera parte (las carpetas y el Guest) es migrar-datos.sh. Lo llama migrar-config.sh, que monta
el disco de la Mac en solo lectura.

    migrar_config.py --datos DIR --sistema DIR --usuario NOMBRE [--aplicar] [--informe ARCHIVO]
    migrar_config.py --deshacer [CARPETA]

Sin --aplicar solo dice qué haría (simular). Con --aplicar, antes de cada cambio anota el valor de
antes en ~/.local/share/mint-macos/migracion/<fecha>/deshacer.sh, y --deshacer lo corre.

Reglas:
  - Del disco de la Mac solo se leen las claves de la lista (nada del llavero, ni claves, ni tokens,
    ni cuentas de Mail, ni otros usuarios). Del registro del usuario en dslocal, SOLO jpegphoto,
    picture y realname: ese archivo trae también el hash de la clave y las llaves de Kerberos.
  - Las claves de destino son las que leen las piezas, dadas por sus dueños (Dev-Dock y Dev,
    19-10-2026); lo que no tiene equivalente, o tiene uno sin verificar, va al informe y no se aplica.
  - Lo que ya está igual no se toca.
"""
import argparse
import datetime
import json
import os
import plistlib
import shlex
import shutil
import sqlite3
import subprocess
import sys

HOGAR = os.path.expanduser("~")
MIGRACION = os.path.join(HOGAR, ".local/share/mint-macos/migracion")


# ── Leer la Mac ──────────────────────────────────────────────────────────────
def plist(ruta):
    try:
        with open(ruta, "rb") as f:
            return plistlib.load(f)
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None


GLOBALES = ["AppleInterfaceStyle", "AppleInterfaceStyleSwitchesAutomatically", "AppleAccentColor",
            "AppleHighlightColor", "AppleShowScrollBars", "AppleActionOnDoubleClick",
            "AppleMiniaturizeOnDoubleClick", "com.apple.swipescrolldirection", "com.apple.mouse.scaling",
            "KeyRepeat", "InitialKeyRepeat", "NSTableViewDefaultSizeMode", "NSUserKeyEquivalents"]
DOCK = ["tilesize", "magnification", "largesize", "orientation", "autohide", "show-recents",
        "wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner"]
FINDER = ["ShowPathbar", "ShowStatusBar", "ShowSidebar", "ShowPreviewPane", "ShowTabView",
          "FXPreferredViewStyle", "FXRemoveOldTrashItems", "ShowHardDrivesOnDesktop",
          "ShowExternalHardDrivesOnDesktop", "ShowRemovableMediaOnDesktop", "ShowMountedServersOnDesktop",
          "NewWindowTarget", "NewWindowTargetPath", "FXDefaultSearchScope", "FavoriteTagNames"]


def leer_mac(datos, sistema, usuario):
    pref = os.path.join(datos, "Users", usuario, "Library/Preferences")
    m = {"usuario": usuario}
    v = plist(os.path.join(sistema, "System/Library/CoreServices/SystemVersion.plist")) or {}
    m["version"] = v.get("ProductVersion")
    g = plist(os.path.join(pref, ".GlobalPreferences.plist")) or {}
    m["global"] = {k: g[k] for k in GLOBALES if k in g}
    d = plist(os.path.join(pref, "com.apple.dock.plist")) or {}
    m["dock"] = {k: d[k] for k in DOCK if k in d}
    m["dock"]["apps"] = [(a.get("tile-data") or {}).get("file-label") for a in d.get("persistent-apps", [])]
    f = plist(os.path.join(pref, "com.apple.finder.plist")) or {}
    m["finder"] = {k: f[k] for k in FINDER if k in f}
    # el registro del usuario: solo estas tres claves
    r = plist(os.path.join(datos, "private/var/db/dslocal/nodes/Default/users", usuario + ".plist")) or {}
    m["avatar"] = {"realname": (r.get("realname") or [None])[0],
                   "picture": (r.get("picture") or [None])[0],
                   "jpegphoto": bool(r.get("jpegphoto"))}
    m["_jpegphoto"] = (r.get("jpegphoto") or [None])[0]   # bytes; no va al informe
    m["fondo"] = fondo(datos, usuario)
    return m


def fondo(datos, usuario):
    """desktoppicture.db: la carpeta (clave 10) y el archivo (clave 16) de la imagen puesta; la unión de
    las dos claves sale de un guion de MacScripter, sin documentación de Apple (hipótesis). Sin clave 16
    no hay una imagen fija: el de fábrica de la versión o una carpeta que rota."""
    db = os.path.join(datos, "Users", usuario, "Library/Application Support/Dock/desktoppicture.db")
    if not os.path.exists(db):
        return {"tipo": "sin-base"}
    try:
        c = sqlite3.connect("file:%s?mode=ro&immutable=1" % db, uri=True)
        filas = c.execute("select p.key, d.value from preferences p join data d on d.rowid = p.data_id").fetchall()
    except sqlite3.Error as e:
        return {"tipo": "error", "detalle": str(e)}
    claves = {}
    for k, val in filas:
        claves.setdefault(k, val)
    carpeta, archivo = claves.get(10), claves.get(16)
    if isinstance(archivo, str) and archivo:
        ruta = archivo if archivo.startswith("/") else os.path.join(str(carpeta or ""), archivo)
        return {"tipo": "imagen", "ruta_mac": ruta}
    return {"tipo": "sin-imagen-fija", "carpeta": carpeta}


# ── Lo que se hace en Linux ──────────────────────────────────────────────────
def gs_get(esquema, clave):
    r = subprocess.run(["gsettings", "get", esquema, clave], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def esquema_dock():
    """El Dock: Muelle si su esquema existe, si no el de Plank (Dev-Dock, 19-10-2026)."""
    lista = subprocess.run(["gsettings", "list-relocatable-schemas"], capture_output=True, text=True).stdout.split()
    if "org.mintmacos.muelle.dock.settings" in lista:
        return "org.mintmacos.muelle.dock.settings:/org/mintmacos/muelle/docks/dock1/"
    return "net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"


ESQUINAS = {  # wvous-*-corner → comando de hotcorner-layout (Dev-Dock, misioncontrol.vala)
    2: "scale", 4: "desktop", 5: "cinnamon-screensaver-command -a", 10: "xset dpms force off",
    11: os.path.join(HOGAR, ".local/bin/mac-launchpad"), 13: "cinnamon-screensaver-command -l",
    3: "gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval global.mintMacosAppWindows()",
    12: "gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval global.mintMacosNotificationCenter()",
}
VERSIONES = [("10.13", "highsierra-10.13"), ("10.15", "catalina-10.15"), ("12.", "monterey-12.7.6"),
             ("15.", "sequoia-15.8.1"), ("26.", "macos-27"), ("27.", "macos-27")]


def plan(m):
    """Lista de (qué, acción, detalle). acción: ("gs", esquema, clave, valor) | ("cmd", [...], deshacer) |
    ("archivo", origen_bytes|ruta, destino) | None (solo informe)."""
    p = []
    # versión → perfil
    ver = m.get("version") or ""
    perfil = next((pid for pre, pid in VERSIONES if ver.startswith(pre)), None)
    if perfil:
        actual = (json.load(open(os.path.join(HOGAR, ".config/mint-macos/macos.json"))) or {}).get("version") \
            if os.path.exists(os.path.join(HOGAR, ".config/mint-macos/macos.json")) else None
        p.append(("versión de macOS %s → perfil %s" % (ver, perfil),
                  None if actual == perfil else ("cmd", ["mint-macos-version", "--poner", perfil],
                                                  ["mint-macos-version", "--poner", actual] if actual else None),
                  "ya está" if actual == perfil else ""))
    else:
        p.append(("versión de macOS %s" % ver, None, "sin perfil para esa versión"))
    # apariencia → Apariencia1
    g = m["global"]
    ap = "auto" if g.get("AppleInterfaceStyleSwitchesAutomatically") else ("dark" if g.get("AppleInterfaceStyle") == "Dark" else "light")
    acentos = {-1: "Graphite", 0: "Red", 1: "Orange", 2: "Yellow", 3: "Green", 4: "Blue", 5: "Purple", 6: "Pink"}
    ac = acentos.get(g.get("AppleAccentColor"), "Blue") if "AppleAccentColor" in g else "Blue"
    nota = "" if "AppleAccentColor" not in g else " (número de acento → color: tabla de la comunidad, sin fuente de Apple; hipótesis)"
    p.append(("apariencia %s, acento %s%s" % (ap, ac, nota),
              ("cmd", ["gdbus", "call", "--session", "-d", "org.mintmacos.Apariencia1", "-o", "/org/mintmacos/Apariencia1",
                       "-m", "org.mintmacos.Apariencia1.Poner", ap, ac, ""], "apariencia"), ""))
    if "AppleHighlightColor" in g:
        p.append(("color de resaltado «%s»" % g["AppleHighlightColor"], None, "sin convertir todavía: va a mano en General"))
    # General y Mouse
    sb = {"Always": "false", "WhenScrolling": "true"}.get(g.get("AppleShowScrollBars"))
    if sb:
        p.append(("Show scroll bars: %s" % g["AppleShowScrollBars"], ("gs", "org.cinnamon.desktop.interface", "gtk-overlay-scrollbars", sb), ""))
    elif "AppleShowScrollBars" in g:
        p.append(("Show scroll bars: %s" % g["AppleShowScrollBars"], None, "«Automatic» no existe en Linux"))
    dc = {"Maximize": "'toggle-maximize'", "Minimize": "'minimize'", "None": "'none'"}.get(g.get("AppleActionOnDoubleClick"))
    if dc:
        p.append(("doble clic en la barra de título: %s" % g["AppleActionOnDoubleClick"],
                  ("gs", "org.cinnamon.desktop.wm.preferences", "action-double-click-titlebar", dc), ""))
    if "com.apple.swipescrolldirection" in g:
        v = "true" if g["com.apple.swipescrolldirection"] else "false"
        p.append(("scroll natural: %s" % v, ("gs", "org.cinnamon.desktop.peripherals.mouse", "natural-scroll", v), ""))
    if "com.apple.mouse.scaling" in g:
        p.append(("velocidad del puntero %s" % g["com.apple.mouse.scaling"], None,
                  "sin verificar: la escala de la Mac contra las 10 marcas del panel sale de memoria, falta una captura"))
    for k in ("KeyRepeat", "InitialKeyRepeat"):
        if k in g:
            p.append(("%s=%s" % (k, g[k]), None, "sin convertir todavía"))
    if "NSTableViewDefaultSizeMode" in g:
        p.append(("Sidebar icon size", None, "sin clave en Linux (el control sigue en gris)"))
    if g.get("NSUserKeyEquivalents"):
        p.append(("App Shortcuts (%d)" % len(g["NSUserKeyEquivalents"]), None, "sin convertir todavía"))
    # Dock
    d, ed = m["dock"], esquema_dock()
    if "tilesize" in d:
        p.append(("Dock: tamaño %d" % d["tilesize"], ("gs", ed, "icon-size", str(int(round(d["tilesize"])))), ""))
    lupa = bool(d.get("magnification"))
    p.append(("Dock: lupa %s" % ("sí" if lupa else "no"), ("gs", ed, "zoom-enabled", "true" if lupa else "false"), ""))
    if lupa and d.get("largesize") and d.get("tilesize"):
        z = max(100, min(300, round(d["largesize"] / d["tilesize"] * 100)))
        p.append(("Dock: lupa al %d %%" % z, ("gs", ed, "zoom-percent", str(z)), ""))
    pos = {"left": "'left'", "right": "'right'"}.get(d.get("orientation"), "'bottom'")
    p.append(("Dock: posición %s" % pos.strip("'"), ("gs", ed, "position", pos), ""))
    p.append(("Dock: esconder %s" % ("sí" if d.get("autohide") else "no"), ("gs", ed, "hide-mode", "'auto'" if d.get("autohide") else "'none'"), ""))
    if "show-recents" in d:
        p.append(("Dock: apps recientes %s" % ("sí" if d["show-recents"] else "no"), ("gs", ed, "show-recent-apps", "true" if d["show-recents"] else "false"), ""))
    p.append(("Dock: apps fijas (%d)" % len(d.get("apps", [])), None,
              "no se reordena lo que ya armó tema/plank/configurar.sh (consejo de Dev-Dock): " + ", ".join(a or "?" for a in d.get("apps", []))))
    # Hot Corners → hotcorner-layout (arriba-izq, arriba-der, abajo-izq, abajo-der)
    esquinas, sin = [], []
    for e in ("tl", "tr", "bl", "br"):
        n = d.get("wvous-%s-corner" % e)
        cmd = ESQUINAS.get(n)
        if n and n > 1 and not cmd:
            sin.append("%s=%s" % (e, n))
        esquinas.append("%s:true:0" % cmd if cmd else "expo:false:0")
    if any(d.get("wvous-%s-corner" % e) for e in ("tl", "tr", "bl", "br")):
        p.append(("Hot Corners", ("gs", "org.cinnamon", "hotcorner-layout", repr(esquinas).replace('"', "'")),
                  ("sin equivalente: " + ", ".join(sin)) if sin else ""))
    # Finder: las claves de Fynder las da Dev
    if m["finder"]:
        p.append(("Finder: %d preferencias" % len(m["finder"]), None, "pendiente: las claves de Fynder las está dando Dev"))
    # Avatar y fondo
    av = m["avatar"]
    if av["jpegphoto"] or av["picture"]:
        p.append(("foto de la cuenta → ~/.face", ("archivo", "jpegphoto" if av["jpegphoto"] else av["picture"], os.path.join(HOGAR, ".face")),
                  "la de la pantalla de entrada (AccountsService) pide root: va el comando en el informe"))
    fo = m["fondo"]
    if fo.get("tipo") == "imagen":
        p.append(("fondo de pantalla: %s" % os.path.basename(fo["ruta_mac"]), ("fondo", fo["ruta_mac"]), "hipótesis: carpeta (clave 10) + archivo (clave 16) de desktoppicture.db"))
    else:
        p.append(("fondo de pantalla", None, "sin imagen propia en desktoppicture.db (%s): queda el de fábrica que pone desde-mac.sh" % fo.get("tipo")))
    p.append(("llavero, claves, tokens, cuentas de Mail y otros usuarios", None, "no se migran (regla)"))
    return p


# ── Aplicar, con su vuelta atrás ─────────────────────────────────────────────
class Deshacer:
    def __init__(self):
        self.dir = os.path.join(MIGRACION, datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
        os.makedirs(self.dir, exist_ok=True)
        self.archivo = os.path.join(self.dir, "deshacer.sh")
        with open(self.archivo, "w") as f:
            f.write("#!/bin/bash\n# Vuelta atrás de migrar-config.sh (en orden inverso).\nset -u\n")
        os.chmod(self.archivo, 0o755)
        self.lineas = []

    def anotar(self, linea):
        self.lineas.insert(0, linea)
        with open(self.archivo, "w") as f:
            f.write("#!/bin/bash\n# Vuelta atrás de migrar-config.sh (en orden inverso).\nset -u\n" + "\n".join(self.lineas) + "\n")


def correr(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e:
        return subprocess.CompletedProcess(cmd, 127, "", str(e))


def aplicar(m, p, dz, datos):
    hechos = []
    for que, acc, nota in p:
        if acc is None:
            continue
        if acc[0] == "gs":
            _, esq, clave, valor = acc
            antes = gs_get(esq, clave)
            if antes == valor:
                hechos.append((que, "ya estaba"))
                continue
            r = correr(["gsettings", "set", esq, clave, valor])
            if r.returncode == 0 and antes is not None:
                dz.anotar("gsettings set %s %s %s" % (shlex.quote(esq), clave, shlex.quote(antes)))
            hechos.append((que, "hecho" if r.returncode == 0 else "falló: " + r.stderr.strip()))
        elif acc[0] == "cmd":
            _, cmd, vuelta = acc
            if vuelta == "apariencia":
                e = correr([os.path.join(os.path.expanduser("~"), ".local/lib/mint-macos/mint-macos-apariencia"), "--estado"])
                try:
                    j = json.loads(e.stdout)
                    vuelta = ["gdbus", "call", "--session", "-d", "org.mintmacos.Apariencia1", "-o", "/org/mintmacos/Apariencia1",
                              "-m", "org.mintmacos.Apariencia1.Poner", j["apariencia"], j["acento"], j["resaltado"]]
                except (ValueError, KeyError):
                    vuelta = None
            r = correr(cmd)
            if r.returncode == 0 and vuelta:
                dz.anotar(" ".join(shlex.quote(x) for x in vuelta))
            hechos.append((que, "hecho" if r.returncode == 0 else "falló: " + (r.stderr or r.stdout).strip()))
        elif acc[0] == "archivo":
            _, origen, destino = acc
            if os.path.exists(destino):
                respaldo = os.path.join(dz.dir, os.path.basename(destino) + ".antes")
                shutil.copy2(destino, respaldo)
                dz.anotar("cp -a %s %s" % (shlex.quote(respaldo), shlex.quote(destino)))
            else:
                dz.anotar("rm -f %s" % shlex.quote(destino))
            # La foto de la Mac viene en TIFF (jpegphoto o /Library/User Pictures/*.tif): ~/.face y
            # AccountsService quieren PNG o JPEG.
            import io
            from PIL import Image
            try:
                if origen == "jpegphoto":
                    im = Image.open(io.BytesIO(m["_jpegphoto"]))
                else:
                    src = os.path.join(datos, origen.lstrip("/"))
                    if not os.path.exists(src):
                        hechos.append((que, "falló: no está %s en el disco de datos" % origen))
                        continue
                    im = Image.open(src)
                im = im.convert("RGBA")
                im.thumbnail((512, 512))
                im.save(destino, "PNG")
            except (OSError, ValueError) as e:
                hechos.append((que, "falló: %s" % e))
                continue
            hechos.append((que, "hecho"))
        elif acc[0] == "fondo":
            src = os.path.join(datos, acc[1].replace("~", "Users/%s" % m["usuario"], 1).lstrip("/"))
            dest_dir = os.path.join(HOGAR, ".local/share/backgrounds/migrado")
            os.makedirs(dest_dir, exist_ok=True)
            dest = os.path.join(dest_dir, os.path.basename(acc[1]))
            if not os.path.exists(src):
                hechos.append((que, "falló: no encuentro la imagen en el disco"))
                continue
            shutil.copyfile(src, dest)
            antes = gs_get("org.cinnamon.desktop.background", "picture-uri")
            correr(["gsettings", "set", "org.cinnamon.desktop.background", "picture-uri", "'file://%s'" % dest])
            if antes:
                dz.anotar("gsettings set org.cinnamon.desktop.background picture-uri %s" % shlex.quote(antes))
            hechos.append((que, "hecho"))
    return hechos


def informe(m, p, hechos, ruta):
    l = ["# Migración de la configuración de la Mac", "",
         "- Usuario de la Mac: %s; macOS %s" % (m["usuario"], m.get("version")), ""]
    estado = dict(hechos or [])
    l.append("| Qué | Resultado | Nota |")
    l.append("|---|---|---|")
    for que, acc, nota in p:
        res = estado.get(que)
        if res is None and acc and hechos is None:
            res = "ya está" if acc[0] == "gs" and gs_get(acc[1], acc[2]) == acc[3] else "se haría"
        res = res or ("solo informe" if acc is None else "—")
        l.append("| %s | %s | %s |" % (que, res, nota))
    texto = "\n".join(l) + "\n"
    if ruta:
        with open(ruta, "w") as f:
            f.write(texto)
    return texto


def main():
    a = argparse.ArgumentParser()
    a.add_argument("--datos")
    a.add_argument("--sistema")
    a.add_argument("--usuario")
    a.add_argument("--aplicar", action="store_true")
    a.add_argument("--informe")
    a.add_argument("--deshacer", nargs="?", const="ultima")
    o = a.parse_args()
    if o.deshacer:
        d = o.deshacer
        if d == "ultima":
            corridas = sorted(x for x in os.listdir(MIGRACION)) if os.path.isdir(MIGRACION) else []
            if not corridas:
                print("no hay ninguna migración que deshacer")
                return 1
            d = os.path.join(MIGRACION, corridas[-1])
        print("deshaciendo %s" % d)
        return subprocess.run(["bash", os.path.join(d, "deshacer.sh")]).returncode
    if not (o.datos and o.sistema and o.usuario):
        a.error("hacen falta --datos, --sistema y --usuario")
    m = leer_mac(o.datos, o.sistema, o.usuario)
    p = plan(m)
    hechos = None
    if o.aplicar:
        dz = Deshacer()
        hechos = aplicar(m, p, dz, o.datos)
        print("vuelta atrás: %s (o migrar-config.sh --deshacer)" % dz.archivo)
    print(informe(m, p, hechos, o.informe))
    av = m["avatar"]
    if (av["jpegphoto"] or av["picture"]) and o.aplicar:
        print("Para la foto de la pantalla de entrada (pide root):\n  sudo install -m 644 ~/.face /var/lib/AccountsService/icons/%s"
              " && sudo sed -i 's|^Icon=.*|Icon=/var/lib/AccountsService/icons/%s|' /var/lib/AccountsService/users/%s"
              % (os.environ.get("USER"), os.environ.get("USER"), os.environ.get("USER")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
