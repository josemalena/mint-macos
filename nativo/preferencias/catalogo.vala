/*
 * Qué paneles hay, en qué grupo y en qué orden (los de Catalina, de settings/paneles.py). Cada panel que ya está en Vala se
 * registra en crear_panel; los demás salen del catálogo generado (catalogo-datos.vala) como PanelPython.
 */
namespace Preferencias {

    public class GrupoPaneles : Object {
        public string id;
        public List<Panel> paneles = new List<Panel> ();
    }

    /** El panel en Vala de ese identificador, o null si todavía lo sirve Python. */
    Panel? crear_panel (string ident) {
        switch (ident) {
        case "com.apple.preference.desktopscreeneffect": return new PanelDesktopScreenSaver ();
        case "com.apple.preference.security": return new PanelSecurity ();
        case "com.apple.preference.datetime": return new PanelDateTime ();
        case "com.apple.preference.displays": return new PanelDisplays ();
        case "com.apple.preference.screentime": return new PanelScreenTime ();
        case "com.apple.preference.keyboard": return new PanelKeyboard ();
        case "com.apple.preference.dock": return new PanelDock ();
        case "com.apple.preference.startupdisk": return new PanelStartupDisk ();
        case "com.apple.preference.expose": return new PanelMissionControl ();
        case "com.apple.preference.spotlight": return new PanelSpotlight ();
        case "com.apple.preference.sound": return new PanelSound ();
        case "com.apple.preference.network": return new PanelNetwork ();
        case "com.apple.preference.general": return new PanelGeneral ();
        case "com.apple.preference.printfax": return new PanelPrinters ();
        case "com.apple.preferences.users": return new PanelUsers ();
        case "com.apple.preferences.sharing": return new PanelSharing ();
        case "com.apple.preferences.Bluetooth": return new PanelBluetooth ();
        case "com.apple.preference.mouse": return new PanelMouse ();
        case "com.apple.preference.trackpad": return hay_touchpad () ? null : new PanelTrackpad ();   // con touchpad, el módulo de Cinnamon
        case "com.apple.Localization": return new PanelLanguage ();
        case "com.apple.preference.energysaver": return new PanelEnergySaver ();
        case "com.apple.preferences.softwareupdate": return new PanelSoftwareUpdate ();
        case "com.apple.preference.notifications": return new PanelNotifications ();
        case "com.apple.prefs.backup": return new PanelTimeMachine ();
        case "com.apple.preference.speech": return new PanelSiri ();
        case "com.apple.preferences.configurationprofiles": return new PanelProfiles ();
        case "com.apple.preference.digihub.discs": return new PanelDiscs ();
        }
        return null;
    }

    /**
     * Los grupos con los paneles que de verdad se pueden servir: el orden y los bloques de Catalina, y al final «Advanced»
     * (lo que Catalina no tiene, detrás de un solo botón que abre el cinnamon-settings de siempre).
     */
    List<GrupoPaneles> armar_paneles () {
        var grupos = new List<GrupoPaneles> ();
        GrupoPaneles? actual = null;
        foreach (var d in catalogo ()) {
            Panel? p = crear_panel (d.id);
            if (p == null) {
                var py = new PanelPython (d);
                if (!py.disponible ()) {
                    continue;
                }
                p = py;
            }
            p.grupo = d.grupo;
            if (actual == null || actual.id != d.grupo) {
                actual = new GrupoPaneles ();
                actual.id = d.grupo;
                grupos.append (actual);
            }
            actual.paneles.append (p);
        }
        var avanzado = new GrupoPaneles ();
        avanzado.id = "advanced";
        avanzado.paneles.append (new PanelAvanzado ());
        grupos.append (avanzado);
        return grupos;
    }

    // Cuando un panel se pide por el nombre de cinnamon-settings (cinnamon-settings sound, display…) se abre el panel que lo
    // contiene.
    string? alias_de (string nombre) {
        switch (nombre) {
        case "backgrounds": case "screensaver": return "desktopscreeneffect";
        case "themes": case "fonts": case "panel": case "effects": case "default": return "general";
        case "workspaces": case "hotcorner": case "windows": return "expose";
        case "display": case "nightlight": case "color": return "displays";
        case "power": return "energysaver";
        case "mouse": return "mouse";
        case "gestures": return "trackpad";
        case "sound": return "sound";
        case "network": return "network";
        case "notifications": return "notifications";
        case "privacy": return "security";
        case "keyboard": return "keyboard";
        case "calendar": return "datetime";
        case "user": case "startup": return "users";
        case "accessibility": return "universalaccess";
        case "applets": case "desklets": case "extensions": case "actions": return "extensions";
        }
        return null;
    }
}
