#!/usr/bin/env python3
"""Íconos de apps de macOS para sus equivalentes de Linux, sacados del disco
de la Mac (los .icns de cada .app y de cada panel de System Preferences).

    macos_apps.py <raíz del volumen de sistema de la Mac> <carpeta destino>

Los que vienen dentro de un Assets.car (Internet Accounts, Appearance) se
leen con car.py, que necesita liblzfse.

Escribe <nombre-de-ícono-de-Linux>.png (256 px) en la carpeta destino, que es
escalables/apps de Constanza. Nada de esto va al repo: se genera aquí.
Lo que no esté en el disco se salta con un aviso.
"""
import os
import plistlib
import sys

from PIL import Image

APPS = "System/Applications"
UTIL = "System/Applications/Utilities"
CORE = "System/Library/CoreServices/Applications"
PANES = "System/Library/PreferencePanes"

# Origen en la Mac → nombres de ícono que usan las apps de Linux.
EQUIVALENCIAS = {
    f"{UTIL}/Terminal.app": ["org.gnome.Terminal", "utilities-terminal", "org.gnome.Terminal.Preferences"],
    f"{APPS}/Calculator.app": ["org.gnome.Calculator"],
    f"{APPS}/TextEdit.app": ["accessories-text-editor", "org.x.editor"],
    f"{APPS}/Preview.app": ["xreader", "xviewer", "pix", "display-im6.q16"],
    f"{APPS}/Calendar.app": ["org.gnome.Evolution-alarm-notify"],
    "System/Library/CoreServices/Finder.app": ["org.gnome.Nautilus"],
    f"{CORE}/Archive Utility.app": ["org.gnome.FileRoller"],
    f"{UTIL}/Disk Utility.app": ["org.gnome.DiskUtility"],
    # Nuestro Activity Monitor (mac-actividad, Vala); GNOME System Monitor conserva su ícono original.
    f"{UTIL}/Activity Monitor.app": ["mac-activity-monitor"],
    f"{APPS}/Font Book.app": ["org.gnome.font-viewer", "cs-fonts"],
    f"{UTIL}/Screenshot.app": ["org.gnome.Screenshot"],
    f"{APPS}/Stickies.app": ["sticky"],
    f"{APPS}/Music.app": ["org.gnome.Rhythmbox3"],
    f"{APPS}/QuickTime Player.app": ["io.github.celluloid_player.Celluloid"],
    f"{APPS}/App Store.app": ["software-properties-mint", "mintinstall"],
    f"{UTIL}/Keychain Access.app": ["org.gnome.seahorse.Application"],
    f"{APPS}/Image Capture.app": ["org.gnome.SimpleScan"],
    f"{APPS}/Time Machine.app": ["mintbackup", "timeshift"],
    f"{UTIL}/System Information.app": ["mintreport"],
    f"{APPS}/System Preferences.app": ["cs-general"],
    # Paneles de System Preferences → Ajustes de Cinnamon
    f"{PANES}/SoftwareUpdate.prefPane": ["mintupdate"],
    f"{PANES}/Displays.prefPane": ["cs-display"],
    f"{PANES}/Sound.prefPane": ["cs-sound"],
    f"{PANES}/Keyboard.prefPane": ["cs-keyboard", "ibus"],
    f"{PANES}/Mouse.prefPane": ["cs-mouse"],
    f"{PANES}/Trackpad.prefPane": ["cs-gestures"],
    f"{PANES}/Network.prefPane": ["cs-network", "preferences-system-network", "nm-device-wireless"],
    f"{PANES}/DateAndTime.prefPane": ["cs-date-time"],
    f"{PANES}/Notifications.prefPane": ["cs-notifications"],
    f"{PANES}/UniversalAccessPref.prefPane": ["cs-universal-access"],
    f"{PANES}/Security.prefPane": ["cs-privacy", "gufw"],
    f"{PANES}/EnergySaver.prefPane": ["cs-power", "org.gnome.PowerStats"],
    f"{PANES}/Expose.prefPane": ["cs-overview", "cs-workspaces"],
    f"{PANES}/Accounts.prefPane": ["cs-user", "system-users", "lightdm-settings"],
    f"{PANES}/PrintAndScan.prefPane": ["printer"],
    f"{PANES}/Bluetooth.prefPane": ["blueman", "blueman-device"],
    f"{PANES}/Localization.prefPane": ["preferences-desktop-locale", "mintlocale-im"],
    f"{PANES}/InternetAccounts.prefPane": ["gnome-online-accounts-gtk"],
    f"{PANES}/DesktopScreenEffectsPref.prefPane": ["cs-backgrounds", "cs-desktop", "cs-screensaver"],
    f"{PANES}/Appearance.prefPane": ["cs-themes"],
    f"{PANES}/Extensions.prefPane": ["cs-extensions"],
}


def icns_de(bundle):
    """El .icns del ícono de un .app o .prefPane, según su Info.plist."""
    with open(os.path.join(bundle, "Contents", "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    recursos = os.path.join(bundle, "Contents", "Resources")
    # CFBundleIconFile primero: en los paneles, NSPrefPaneIconFile suele ser
    # un PNG o TIFF chico de la rejilla de System Preferences.
    for clave in ("CFBundleIconFile", "NSPrefPaneIconFile"):
        nombre = info.get(clave) or ""
        for n in (nombre, nombre + ".icns"):
            if n.endswith(".icns") and os.path.isfile(os.path.join(recursos, n)):
                return os.path.join(recursos, n)
    # Desde Catalina algunos paneles lo traen dentro de Assets.car.
    car = os.path.join(recursos, "Assets.car")
    nombre = (info.get("CFBundleIconFile") or "").removesuffix(".icns")
    if nombre and os.path.isfile(car):
        return (car, nombre)
    if os.path.isfile(os.path.join(recursos, "AppIcon.icns")):
        return os.path.join(recursos, "AppIcon.icns")
    # Algunos no lo declaran: el único .icns que traigan.
    icns = sorted(x for x in os.listdir(recursos) if x.endswith(".icns"))
    return os.path.join(recursos, icns[0]) if len(icns) == 1 else None


def png_256(icns, destino):
    if isinstance(icns, tuple):  # (Assets.car, nombre del ícono)
        import car
        img = car.mayor(*icns)
        if img is None:
            raise RuntimeError(f"no se pudo abrir {icns[1]} en {icns[0]}")
        img.resize((256, 256), Image.LANCZOS).save(destino)
        return
    img = Image.open(icns)
    # El tamaño más grande que traiga el .icns, y de ahí a 256 px.
    mayor = max(img.info.get("sizes", [img.size]))
    if hasattr(img, "size") and mayor != img.size:
        img.size = mayor
        img.load()
    img.convert("RGBA").resize((256, 256), Image.LANCZOS).save(destino)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    mac, carpeta = sys.argv[1], sys.argv[2]
    os.makedirs(carpeta, exist_ok=True)
    hechos = 0
    for origen, nombres in EQUIVALENCIAS.items():
        bundle = os.path.join(mac, origen)
        icns = icns_de(bundle) if os.path.isdir(bundle) else None
        if not icns:
            print(f"  ⚠ sin ícono en la Mac: {origen}")
            continue
        primero = os.path.join(carpeta, nombres[0] + ".png")
        if isinstance(icns, tuple):
            try:  # antes de borrar nada: sin liblzfse se queda el de antes
                import car
                car.mayor(*icns)
            except Exception as e:
                print(f"  ⚠ {origen}: {e}")
                continue
        for n in nombres:
            for viejo in (n + ".svg", n + ".png"):
                p = os.path.join(carpeta, viejo)
                if os.path.lexists(p):
                    os.remove(p)
        png_256(icns, primero)
        for n in nombres[1:]:
            os.symlink(nombres[0] + ".png", os.path.join(carpeta, n + ".png"))
        hechos += len(nombres)
    print(f"  {hechos} íconos de apps de macOS")


if __name__ == "__main__":
    main()
