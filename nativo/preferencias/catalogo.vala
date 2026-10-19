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
     * Los ids de los paneles que el perfil de la versión activa marca «ocultar» (perfiles/adaptaciones.json, lo aprobado por José:
     * Siri, Wallet, Touch ID, Sidecar, Family Sharing, Screen Time…). No salen en la cuadrícula ni en la búsqueda, ni en gris.
     * Sin perfil no se oculta nada.
     */
    static Json.Object? leer_json (string ruta) {
        try {
            var p = new Json.Parser ();
            p.load_from_file (ruta);
            var r = p.get_root ();
            return r != null && r.get_node_type () == Json.NodeType.OBJECT ? r.get_object () : null;
        } catch (Error e) {
            return null;
        }
    }

    /** apps/system-preferences.json del perfil de la versión de macOS activa (la de esta sesión, o la escogida, o Catalina); null si no hay. */
    static Json.Object? perfil_system_preferences () {
        string? version = null;
        foreach (var ruta in new string[] { Path.build_filename (Environment.get_user_runtime_dir (), "mint-macos", "macos.json"),
                                            Path.build_filename (Environment.get_user_config_dir (), "mint-macos", "macos.json") }) {
            var o = leer_json (ruta);
            if (o != null && o.has_member ("version")) {
                version = o.get_string_member ("version");
                break;
            }
        }
        return leer_json (Path.build_filename (Environment.get_user_data_dir (), "mint-macos", "macos", version ?? "catalina-10.15",
                                               "apps", "system-preferences.json"));
    }

    HashTable<string, bool> paneles_ocultos () {
        var ocultos = new HashTable<string, bool> (str_hash, str_equal);
        var perfil = perfil_system_preferences ();
        if (perfil == null || !perfil.has_member ("grupos")) {
            return ocultos;
        }
        foreach (var g in perfil.get_array_member ("grupos").get_elements ()) {
            var grupo = g.get_object ();
            if (!grupo.has_member ("paneles")) {
                continue;
            }
            foreach (var n in grupo.get_array_member ("paneles").get_elements ()) {
                var pn = n.get_object ();
                if (pn.has_member ("ocultar") && pn.get_boolean_member ("ocultar") && pn.has_member ("id")) {
                    ocultos[pn.get_string_member ("id")] = true;
                }
            }
        }
        return ocultos;
    }

    /**
     * Los grupos con los paneles que de verdad se pueden servir: el orden y los bloques de Catalina, y al final «Advanced»
     * (lo que Catalina no tiene, detrás de un solo botón que abre el cinnamon-settings de siempre).
     */
    List<GrupoPaneles> armar_paneles () {
        var grupos = new List<GrupoPaneles> ();
        GrupoPaneles? actual = null;
        var ocultos = paneles_ocultos ();
        foreach (var d in catalogo ()) {
            if (ocultos.contains (d.id)) {
                continue;
            }
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
        // Paneles de terceros, como macFUSE en Catalina: una fila aparte antes de «Advanced». Solaar solo si está instalado.
        if (Environment.find_program_in_path ("solaar") != null) {
            var terceros = new GrupoPaneles ();
            terceros.id = "terceros";
            terceros.paneles.append (new PanelSolaar ());
            grupos.append (terceros);
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
