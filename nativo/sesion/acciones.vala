/*
 * Lo que hace el diálogo de sesión cuando se confirma, igual que applets/applemenu@macos/applemenu.py:
 * apagar y reiniciar se piden al gestor de sesión con RequestShutdown y RequestReboot, que NO abren diálogo
 * (cinnamon-session-quit --reboot --no-prompt reenvía al gestor, que abre el suyo encima de este); si no contesta, systemctl
 * de plan B. Log Out: cinnamon-session-quit --logout --no-prompt, sin plan B (sin --no-prompt abre el diálogo del sistema).
 */
namespace Sesion {

    public class Preset : Object {
        public string titulo;
        public string cuenta;           // con {n} en lugar de los segundos
        public string accion;
        public bool reabrir_por_defecto;
        public string[] primario;
        public bool esperar_primario;
        public string[] alternos;       // líneas de comando, una por plan B
    }

    const string[] PETICION = { "gdbus", "call", "--session", "--dest", "org.gnome.SessionManager",
                                "--object-path", "/org/gnome/SessionManager", "--method" };

    string[] peticion (string metodo) {
        string[] c = {};
        foreach (var p in PETICION) {
            c += p;
        }
        c += "org.gnome.SessionManager." + metodo;
        return c;
    }

    public Preset? preset_de (string modo) {
        var p = new Preset ();
        switch (modo) {
        case "shutdown":
            p.titulo = "Are you sure you want to shut down your computer now?";
            p.cuenta = "If you do nothing, the computer will shut down automatically\nin {n} seconds.";
            p.accion = "Shut Down";
            p.reabrir_por_defecto = true;
            p.primario = peticion ("RequestShutdown");
            p.esperar_primario = true;
            p.alternos = { "systemctl poweroff", "shutdown -h now" };
            return p;
        case "restart":
            p.titulo = "Are you sure you want to restart your computer now?";
            p.cuenta = "If you do nothing, the computer will restart automatically\nin {n} seconds.";
            p.accion = "Restart";
            p.reabrir_por_defecto = true;
            p.primario = peticion ("RequestReboot");
            p.esperar_primario = true;
            p.alternos = { "systemctl reboot", "shutdown -r now" };
            return p;
        case "logoff":
            p.titulo = "Are you sure you want to quit all applications\nand log out now?";
            p.cuenta = "If you do nothing, you will be logged out automatically in\n{n} seconds.";
            p.accion = "Log Out";
            p.reabrir_por_defecto = false;
            p.primario = { "cinnamon-session-quit", "--logout", "--no-prompt" };
            p.esperar_primario = false;
            p.alternos = {};
            return p;
        }
        return null;
    }

    bool salio_bien (int estado) {
        try {
            return Process.check_wait_status (estado);
        } catch (Error e) {
            return false;
        }
    }

    /** Lanza el comando. Con esperar, espera y devuelve si salió bien (0): así un gestor de sesión que no contesta cae al plan B. */
    bool correr (string[] cmd, bool esperar) {
        try {
            if (esperar) {
                int estado;
                Process.spawn_sync (null, cmd, null, SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL
                                    | SpawnFlags.STDERR_TO_DEV_NULL, null, null, null, out estado);
                return salio_bien (estado);
            }
            Process.spawn_async (null, cmd, null, SpawnFlags.SEARCH_PATH, null, null);
            return true;
        } catch (Error e) {
            return false;
        }
    }

    public bool ejecutar_accion (string modo) {
        var p = preset_de (modo);
        if (p == null) {
            return false;
        }
        if (correr (p.primario, p.esperar_primario)) {
            return true;
        }
        foreach (var linea in p.alternos) {
            string[] c;
            try {
                Shell.parse_argv (linea, out c);
            } catch (Error e) {
                continue;
            }
            if (correr (c, false)) {
                return true;
            }
        }
        return false;
    }

    /** La cuenta temporal de LightDM se llama guest-XXXXXX. */
    public bool sesion_de_invitado () {
        var usuario = Environment.get_variable ("USER") ?? Environment.get_user_name ();
        return usuario.has_prefix ("guest-");
    }

    // «Reopen windows» es el guardado de sesión de Cinnamon.
    GLib.Settings? ajustes_de_sesion () {
        var fuente = SettingsSchemaSource.get_default ();
        if (fuente == null || fuente.lookup ("org.cinnamon.SessionManager", true) == null) {
            return null;
        }
        return new GLib.Settings ("org.cinnamon.SessionManager");
    }

    public bool reabrir_ventanas_actual () {
        var s = ajustes_de_sesion ();
        return s != null && s.get_boolean ("auto-save-session");
    }

    public void guardar_reabrir_ventanas (bool valor) {
        var s = ajustes_de_sesion ();
        if (s != null) {
            s.set_boolean ("auto-save-session", valor);
            GLib.Settings.sync ();
        }
    }

    /**
     * Los usuarios con otra sesión gráfica abierta además de esta: Type x11, wayland o mir, Class user, activa o en línea.
     * Las de ssh (Type tty) NO cuentan: aquí casi siempre hay alguna abierta y no hay fuente de Apple que diga que
     * cuenten como «otros usuarios conectados».
     */
    public string[] otras_sesiones () {
        string[] usuarios = {};
        if (Environment.get_variable ("MINT_APPLEMENU_OTRAS") == "1") {
            usuarios += "prueba";
            return usuarios;
        }
        var propia = Environment.get_variable ("XDG_SESSION_ID") ?? "";
        try {
            string salida;
            Process.spawn_command_line_sync ("loginctl list-sessions --no-legend", out salida, null, null);
            foreach (var linea in salida.split ("\n")) {
                var partes = linea.strip ().split (" ");
                string[] campos = {};
                foreach (var x in partes) {
                    if (x != "") {
                        campos += x;
                    }
                }
                if (campos.length < 3 || campos[0] == propia) {
                    continue;
                }
                string info;
                Process.spawn_command_line_sync ("loginctl show-session %s -p Type -p Class -p State -p Name"
                                                 .printf (Shell.quote (campos[0])), out info, null, null);
                string tipo = "", clase = "", estado = "", nombre = "";
                foreach (var l in info.split ("\n")) {
                    if (l.has_prefix ("Type=")) tipo = l.substring (5);
                    else if (l.has_prefix ("Class=")) clase = l.substring (6);
                    else if (l.has_prefix ("State=")) estado = l.substring (6);
                    else if (l.has_prefix ("Name=")) nombre = l.substring (5);
                }
                if ((tipo == "x11" || tipo == "wayland" || tipo == "mir") && clase == "user"
                    && (estado == "active" || estado == "online")) {
                    usuarios += nombre;
                }
            }
        } catch (Error e) {
            return {};
        }
        return usuarios;
    }

    /**
     * Reiniciar con otras sesiones gráficas: se pide a logind (systemctl reboot, interactivo), que exige la clave de
     * administrador por polkit y la pide al agente. «ok» si logind aceptó, «cancelado» si se negó la clave y «sin-agente» si
     * nadie pudo pedirla (entonces va la confirmación de siempre). MINT_APPLEMENU_REBOOT cambia el comando (las pruebas).
     */
    public string reiniciar_con_otras_sesiones () {
        var orden = Environment.get_variable ("MINT_APPLEMENU_REBOOT");
        string[] cmd;
        try {
            Shell.parse_argv (orden ?? "systemctl reboot", out cmd);
        } catch (Error e) {
            return "sin-agente";
        }
        try {
            string so, se;
            int estado;
            Process.spawn_sync (null, cmd, null, SpawnFlags.SEARCH_PATH, null, out so, out se, out estado);
            if (salio_bien (estado)) {
                return "ok";
            }
            var texto = ((se ?? "") + (so ?? "")).down ();
            if (texto.contains ("interactive authentication required") || texto.contains ("no authentication agent")
                || (texto.contains ("challenge") && texto.contains ("authentication"))) {
                return "sin-agente";
            }
            return "cancelado";
        } catch (Error e) {
            return "sin-agente";
        }
    }
}
