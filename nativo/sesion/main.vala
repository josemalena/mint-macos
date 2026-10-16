/*
 * mac-sesion: los diálogos de sesión de Catalina (Log Out, Restart, Shut Down y el aviso del invitado), en Vala + GTK3.
 * Reemplaza a «applemenu.py --mode …» con los mismos argumentos y la misma salida JSON:
 *     mac-sesion --mode restart [--seconds 60] [--print-json] [--prueba]
 * --prueba enseña el diálogo y no hace nada al confirmar ni al agotarse la cuenta (para medirlo).
 * Force Quit no está aquí: sigue en Python.
 */
namespace Sesion {

    string? opcion_modo = null;
    int opcion_segundos = 60;
    bool opcion_json = false;
    bool opcion_prueba = false;

    const OptionEntry[] OPCIONES = {
        { "mode", 0, 0, OptionArg.STRING, ref opcion_modo, "shutdown, restart, logoff o guestlogout", "MODE" },
        { "seconds", 0, 0, OptionArg.INT, ref opcion_segundos, "Segundos de la cuenta regresiva (60)", "N" },
        { "print-json", 0, 0, OptionArg.NONE, ref opcion_json, "Imprime el resultado en JSON", null },
        { "prueba", 0, 0, OptionArg.NONE, ref opcion_prueba, "No ejecuta nada", null },
        { null }
    };

    string tf (bool b) {
        return b ? "true" : "false";
    }

    int main (string[] args) {
        try {
            var ctx = new OptionContext ("");
            ctx.add_main_entries (OPCIONES, null);
            ctx.add_group (Gtk.get_option_group (true));
            ctx.parse (ref args);
        } catch (Error e) {
            stderr.printf ("mac-sesion: %s\n", e.message);
            return 2;
        }
        if (opcion_modo == null || !(opcion_modo in new string[] { "shutdown", "restart", "logoff", "guestlogout" })) {
            stderr.printf ("mac-sesion: --mode debe ser shutdown, restart, logoff o guestlogout\n");
            return 2;
        }
        var modo = opcion_modo;

        // En una sesión de invitado, Log Out borra la cuenta: antes va el aviso de Catalina.
        if (modo == "guestlogout" || (modo == "logoff" && sesion_de_invitado ())) {
            MacOS.aplicar_estilo_invitado ();
            var aviso = new AlertaInvitado ();
            int resp = aviso.ejecutar ();
            bool ejecutado = false;
            if (resp == MacOS.Alerta.ACEPTAR && !opcion_prueba) {
                ejecutado = ejecutar_accion ("logoff");
            }
            if (opcion_json) {
                print ("{\"mode\": \"guestlogout\", \"confirmed\": %s, \"executed\": %s, \"prueba\": %s}\n",
                       tf (resp == MacOS.Alerta.ACEPTAR), tf (ejecutado), tf (opcion_prueba));
            }
            return 0;
        }

        // Reiniciar con otros usuarios conectados: Catalina no enseña la confirmación de siempre sino la clave de
        // administrador (el agente de polkit de mint-macos); si no hay agente, la confirmación de siempre.
        if (modo == "restart" && !opcion_prueba && otras_sesiones ().length > 0) {
            var resultado = reiniciar_con_otras_sesiones ();
            if (opcion_json) {
                print ("{\"mode\": \"restart\", \"otras_sesiones\": true, \"resultado\": \"%s\"}\n", resultado);
            }
            if (resultado != "sin-agente") {
                return 0;
            }
        }

        MacOS.aplicar_estilo_alerta ();
        var dlg = new AlertaConfirmar (modo, opcion_segundos, reabrir_ventanas_actual ());
        int resp = dlg.ejecutar ();
        bool reabrir = dlg.reabrir.active;
        dlg.destroy ();

        bool ejecutado = false;
        if (resp == MacOS.Alerta.ACEPTAR && !opcion_prueba) {
            guardar_reabrir_ventanas (reabrir);
            ejecutado = ejecutar_accion (modo);
        }
        if (opcion_json) {
            print ("{\"mode\": \"%s\", \"confirmed\": %s, \"reopen\": %s, \"executed\": %s, \"prueba\": %s, \"seconds\": %d}\n",
                   modo, tf (resp == MacOS.Alerta.ACEPTAR), tf (reabrir), tf (ejecutado), tf (opcion_prueba),
                   opcion_segundos);
        }
        return 0;
    }
}
