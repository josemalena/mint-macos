/*
 * mac-forcequit: la ventana «Force Quit Applications» (⌥⌘⎋ y Apple ▸ Force Quit…). Reemplaza a forcekill.py.
 *   mac-forcequit            abre la ventana
 *   mac-forcequit --prueba   la abre y el botón no mata nada
 *   mac-forcequit --seleccionar PID  la abre con la app de ese pid escogida y marcada «(not responding)»
 *   mac-forcequit --app-del-frente   fuerza la salida de la app del frente (⌥⇧⌘⎋), sin abrir ventana
 * Es de instancia única: si ya hay una ventana (un aviso repetido de que una app no contesta), la trae al frente y
 * escoge esa app, sin abrir otra.
 */
class ForceQuitApp : Gtk.Application {
    MacForceQuit.Ventana? ventana = null;

    public ForceQuitApp () {
        Object (application_id: "io.github.josemalena.MintMacosForceQuit", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        bool prueba = false;
        bool al_frente = false;
        int seleccionar = 0;
        for (int i = 1; i < args.length; i++) {
            var a = args[i];
            if (a == "--seleccionar" && i + 1 < args.length) {
                seleccionar = int.parse (args[++i]);
            } else if (a == "--prueba") {
                prueba = true;
            } else if (a == "--app-del-frente") {
                al_frente = true;
            }
        }
        if (al_frente) {
            return MacForceQuit.app_del_frente ();
        }
        if (ventana != null) {
            if (seleccionar > 0) {
                ventana.seleccionar (seleccionar);
            } else {
                ventana.present ();
            }
            return 0;
        }
        ventana = new MacForceQuit.Ventana (!prueba, seleccionar);
        add_window (ventana);
        ventana.destroy.connect (() => { ventana = null; });
        return 0;
    }
}

int main (string[] args) {
    return new ForceQuitApp ().run (args);
}
