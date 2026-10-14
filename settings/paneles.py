"""Los paneles de System Preferences (Catalina) y qué módulo de Cinnamon sirve cada uno.

Los grupos y el orden son los de Catalina (NSPrefPaneGroups.xml, de la Mac); lo
que se pone en cada panel es lo que Cinnamon ya sabe hacer. Un panel sin ningún
módulo disponible no sale en la cuadrícula.

Una «clave de módulo» es la de cinnamon-settings: los módulos de python
(`cs_sound.py` → «sound»), los de Cinnamon Control Center («network», «color»,
«wacom») y los programas externos (por su comando: «blueman-manager»,
«pkexec mintsources»…). Los externos propios de mint-macos están en EXTERNOS.
"""

from dataclasses import dataclass, field


@dataclass
class Panel:
    id: str                       # el identificador de Catalina (com.apple.preference.sound)
    nombre: str                   # lo que se lee debajo del ícono
    modulos: list                 # claves de módulo; cada una es una pestaña si hay más de una
    pestanas: dict = field(default_factory=dict)   # clave → nombre de la pestaña
    abre: dict = field(default_factory=dict)       # clave → pestaña interna con que abre
    palabras: str = ""            # para el buscador
    icono_tema: str = "preferences-system"         # si Apple no trae el suelto


# Programas externos que mint-macos agrega a los de cinnamon-settings:
# clave → (etiqueta, ícono del tema, palabras del buscador)
EXTERNOS = {
    "plank --preferences": ("Dock", "preferences-desktop", "dock, plank, size, magnification, position, hide"),
    "mintupdate": ("Software Update", "mintupdate", "update, upgrade, packages, security, kernel"),
    "timeshift-gtk": ("Time Machine", "timeshift", "backup, snapshot, restore, timeshift"),
}

_GRUPOS_POR_TEMA = [
    ("personal", [
        Panel("com.apple.preference.general", "General",
              ["themes", "fonts", "effects", "default", "panel"],
              pestanas={"themes": "Appearance", "fonts": "Fonts", "effects": "Animations",
                        "default": "Default Apps", "panel": "Menu Bar"},
              palabras="appearance, dark, light, accent, theme, font, default browser, menu bar",
              icono_tema="preferences-system"),
        Panel("com.apple.preference.desktopscreeneffect", "Desktop & Screen Saver",
              ["backgrounds", "screensaver", "desktop"],
              pestanas={"backgrounds": "Desktop", "screensaver": "Screen Saver", "desktop": "Desktop Icons"},
              palabras="wallpaper, background, picture, screensaver, lock"),
        Panel("com.apple.preference.dock", "Dock", ["plank --preferences"],
              palabras="dock, size, magnification, position, minimize, hide"),
        Panel("com.apple.preference.expose", "Mission Control",
              ["workspaces", "hotcorner", "windows"],
              pestanas={"workspaces": "Spaces", "hotcorner": "Hot Corners", "windows": "Windows"},
              palabras="spaces, desktops, workspaces, hot corners, windows, tiling"),
        Panel("com.apple.preference.spotlight", "Spotlyte", [],
              palabras="spotlyte, spotlight, search, ulauncher, shortcut, menu bar, recent apps"),
        Panel("com.apple.Localization", "Language & Region", ["mintlocale"],
              palabras="language, region, locale, input method, formats"),
        Panel("com.apple.preference.security", "Security & Privacy", ["privacy"],
              palabras="privacy, security, recent files, history"),
        Panel("com.apple.preference.notifications", "Notifications", ["notifications"],
              palabras="notifications, alerts, banners, do not disturb"),
    ]),
    ("hardware", [
        Panel("com.apple.preference.displays", "Displays", ["display", "nightlight", "color"],
              pestanas={"display": "Displays", "nightlight": "Night Shift", "color": "Color"},
              palabras="display, monitor, resolution, arrangement, night shift, color profile"),
        Panel("com.apple.preference.energysaver", "Energy Saver", ["power"],
              palabras="power, battery, sleep, suspend, brightness, lid"),
        Panel("com.apple.preference.keyboard", "Keyboard", ["keyboard"],
              palabras="keyboard, shortcuts, layout, typing, repeat"),
        Panel("com.apple.preference.mouse", "Mouse", ["mouse"],
              abre={"mouse": "mouse"}, palabras="mouse, pointer, scroll, speed, click"),
        Panel("com.apple.preference.trackpad", "Trackpad", ["mouse", "gestures"],
              pestanas={"mouse": "Trackpad", "gestures": "Gestures"},
              abre={"mouse": "touchpad"}, palabras="trackpad, touchpad, tap, scroll, gestures, swipe, pinch"),
        Panel("com.apple.preference.printfax", "Printers & Scanners", ["system-config-printer"],
              palabras="printer, scanner, print"),
        Panel("com.apple.preference.sound", "Sound", ["sound"],
              palabras="sound, volume, output, input, microphone, speakers, alert"),
    ]),
    ("equipo", [
        Panel("com.apple.preference.startupdisk", "Startup Disk", [],
              palabras="startup disk, boot, grub, efi, restart, default os, macos"),
    ]),
    ("net", [
        Panel("com.apple.preferences.internetaccounts", "Internet Accounts", ["gnome-online-accounts-gtk"],
              palabras="accounts, google, microsoft, nextcloud, online",
              icono_tema="gnome-online-accounts"),
        Panel("com.apple.preferences.softwareupdate", "Software Update", ["mintupdate"],
              palabras="update, upgrade, packages, security"),
        Panel("com.apple.preference.network", "Network", ["network"],
              palabras="network, wifi, wireless, ethernet, vpn, proxy, internet"),
        Panel("com.apple.preferences.Bluetooth", "Bluetooth", ["blueman-manager", "blueberry"],
              palabras="bluetooth, devices, pair"),
        Panel("com.apple.preferences.extensions", "Extensions",
              ["applets", "desklets", "extensions", "actions"],
              pestanas={"applets": "Applets", "desklets": "Desklets", "extensions": "Extensions",
                        "actions": "Actions"},
              palabras="extensions, applets, desklets, actions, spices"),
    ]),
    ("system", [
        Panel("com.apple.preferences.users", "Users & Groups", ["user", "startup"],
              pestanas={"user": "Password", "startup": "Login Items"},
              palabras="users, account, password, login items, startup applications, groups"),
        Panel("com.apple.preference.datetime", "Date & Time", ["calendar"],
              palabras="date, time, clock, timezone, calendar, ntp, format"),
        Panel("com.apple.prefs.backup", "Time Machine", ["timeshift-gtk"],
              palabras="backup, snapshot, restore, timeshift"),
        Panel("com.apple.preference.universalaccess", "Accessibility", ["accessibility"],
              palabras="accessibility, zoom, voiceover, keyboard, mouse, contrast"),
    ]),
]

# Catalina dibuja solo tres bloques (con «Advanced» al final): los paneles
# personales con las cuentas, los usuarios y la accesibilidad; luego el equipo y
# la red; el último es lo de terceros, aquí «Advanced». El orden es el de la
# captura de System Preferences (12.07.52).
_ORDEN = [
    ["general", "desktopscreeneffect", "dock", "expose", "spotlight", "Localization", "notifications",
     "internetaccounts", "users", "universalaccess", "extensions", "security"],
    ["softwareupdate", "network", "Bluetooth", "sound", "printfax", "keyboard", "trackpad", "mouse",
     "displays", "energysaver", "datetime", "backup", "startupdisk"],
]
_TODOS = {p.id.rsplit(".", 1)[1]: p for _, ps in _GRUPOS_POR_TEMA for p in ps}
GRUPOS = [("bloque%d" % (i + 1), [_TODOS[k] for k in orden if k in _TODOS]) for i, orden in enumerate(_ORDEN)]

# Lo que Catalina no tiene (Disks, Firewall, Fingerprints…) ya no sale en la
# cuadrícula: queda detrás de un solo botón, «Advanced», que abre el
# cinnamon-settings de Mint (PanelAvanzado, en preferencias.py).

# Cuando un panel se pide por el nombre de cinnamon-settings (cinnamon-settings
# sound, cinnamon-settings display…) se abre el panel que lo contiene.
ALIAS = {
    "backgrounds": "desktopscreeneffect", "screensaver": "desktopscreeneffect",
    "themes": "general", "fonts": "general", "panel": "general", "effects": "general",
    "default": "general",
    "workspaces": "expose", "hotcorner": "expose", "windows": "expose",
    "display": "displays", "nightlight": "displays", "color": "displays",
    "power": "energysaver", "mouse": "mouse", "gestures": "trackpad",
    "sound": "sound", "network": "network", "notifications": "notifications",
    "privacy": "security", "keyboard": "keyboard", "calendar": "datetime",
    "user": "users", "startup": "users", "accessibility": "universalaccess",
    "applets": "extensions", "desklets": "extensions", "extensions": "extensions",
    "actions": "extensions",
}
