// GENERADO por generar-catalogo.py de settings/paneles.py y settings/propios.py: no se edita a mano.
namespace Preferencias {
    public struct DatosPanel {
        public string grupo;
        public string id;
        public string nombre;
        public string palabras;
        public string icono_tema;
        public string requiere;
    }

    public DatosPanel[] catalogo () {
        DatosPanel[] a = {};
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.general", nombre = "General", palabras = "appearance, dark, light, accent color, highlight, scroll bars, default web browser, recent items, handoff, font smoothing", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.desktopscreeneffect", nombre = "Desktop & Screen Saver", palabras = "desktop, wallpaper, background, screen saver, screensaver, picture, start after, clock, hot corners", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.dock", nombre = "Dock", palabras = "dock, size, magnification, position, minimize, genie, hide, zoom, title bar", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.expose", nombre = "Mission Control", palabras = "spaces, desktops, workspaces, hot corners, windows, mission control, expose", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.speech", nombre = "Siri", palabras = "siri, voice, ask siri, hey siri, dictation", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.spotlight", nombre = "Spotlyte", palabras = "spotlyte, spotlight, search, ulauncher, shortcut, menu bar, recent apps", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.Localization", nombre = "Language & Region", palabras = "language, region, formats, first day of week, calendar, time format, temperature, preferred languages, currency", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.notifications", nombre = "Notifications", palabras = "notifications, alerts, banners, do not disturb, badges, notification center", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preferences.internetaccounts", nombre = "Internet Accounts", palabras = "accounts, google, microsoft, nextcloud, online", icono_tema = "gnome-online-accounts", requiere = "gnome-online-accounts-gtk" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preferences.users", nombre = "Users & Groups", palabras = "users, groups, account, password, login items, startup, login options, guest", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.universalaccess", nombre = "Accessibility", palabras = "accessibility, zoom, voiceover, keyboard, mouse, contrast", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.screentime", nombre = "Screen Time", palabras = "screen time, app usage, notifications, pickups, downtime, app limits, communication, always allowed, content privacy", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preferences.extensions", nombre = "Extensions", palabras = "extensions, applets, desklets, actions, spices", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque1", id = "com.apple.preference.security", nombre = "Security & Privacy", palabras = "security, privacy, password, firewall, filevault, lock, location services, gatekeeper", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preferences.softwareupdate", nombre = "Software Update", palabras = "software update, updates, upgrade, packages, security, automatically keep up to date", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.network", nombre = "Network", palabras = "network, ethernet, wi-fi, wifi, ip address, dns, router, vpn, proxy, dhcp, bluetooth pan", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preferences.Bluetooth", nombre = "Bluetooth", palabras = "bluetooth, devices, pair, connect, discoverable, keyboard, mouse, headphones, speaker", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.sound", nombre = "Sound", palabras = "sound, volume, output, input, microphone, speakers, balance, mute, alert, sound effects", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.printfax", nombre = "Printers & Scanners", palabras = "printers, scanners, print, printer, default printer, queue, sharing", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.keyboard", nombre = "Keyboard", palabras = "keyboard, key repeat, delay, shortcuts, modifier keys, caps lock, input sources, layout, text, dictation", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.trackpad", nombre = "Trackpad", palabras = "trackpad, touchpad, bluetooth trackpad, tap, scroll, gestures", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.mouse", nombre = "Mouse", palabras = "mouse, pointer, tracking speed, scrolling, double-click, primary button, natural scroll, left handed", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.displays", nombre = "Displays", palabras = "displays, display, resolution, rotation, refresh rate, night shift, color, profile, monitor, temperature", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.energysaver", nombre = "Energy Saver", palabras = "energy saver, computer sleep, display sleep, power, suspend, power nap, wake, schedule", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.datetime", nombre = "Date & Time", palabras = "date, time, clock, time zone, timezone, ntp, 24-hour, menu bar, calendar, seconds, am pm", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preferences.sharing", nombre = "Sharing", palabras = "sharing, remote login, ssh, file sharing, samba, printer sharing, screen sharing, computer name", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.prefs.backup", nombre = "Time Machine", palabras = "time machine, backup, back up, timeshift, snapshot, restore", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.startupdisk", nombre = "Startup Disk", palabras = "startup disk, boot, grub, efi, restart, default os, macos", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preferences.configurationprofiles", nombre = "Profiles", palabras = "profiles, configuration profiles, provisioning profiles, mdm", icono_tema = "preferences-system", requiere = "" };
        a += DatosPanel () { grupo = "bloque2", id = "com.apple.preference.digihub.discs", nombre = "CDs & DVDs", palabras = "cd, dvd, disc, insert, blank, music cd, picture cd, video dvd, eject", icono_tema = "preferences-system", requiere = "" };
        return a;
    }

    // Apple ID no sale en la cuadrícula: se abre desde la franja de arriba.
    public DatosPanel datos_apple_id () {
        return DatosPanel () { grupo = "oculto", id = "com.apple.preferences.AppleIDPrefPane", nombre = "Apple ID", palabras = "apple id, icloud, mail, calendar, sign in", icono_tema = "preferences-system", requiere = "" };
    }
}
