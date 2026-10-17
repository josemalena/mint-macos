/*
 * mac-sesion: los diálogos de sesión de Catalina (Log Out, Restart, Shut Down y el aviso del invitado), en Vala + GTK3.
 * Reemplaza a «applemenu.py --mode …» con los mismos argumentos y la misma salida JSON:
 *     mac-sesion --mode restart [--seconds 60] [--print-json] [--prueba]
 * --prueba enseña el diálogo y no hace nada al confirmar ni al agotarse la cuenta (para medirlo).
 * La lógica está aquí para que la usen el binario suelto (main.vala) y el residente mac-ventanas.
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

    /** Quién recibe lo que el diálogo imprime: stdout/stderr en el binario suelto, el cliente en mac-ventanas. */
    public delegate void Salida (string texto);

    /**
     * Lo que hace mac-sesion con sus argumentos (args[0] es el nombre del programa). Devuelve el código de salida.
     * Las opciones son estáticas (OptionEntry lo pide): se reponen en cada llamada, porque el residente la usa muchas veces.
     */
    public int atender (string[] args_in, Salida salida, Salida error) {
        opcion_modo = null;
        opcion_segundos = 60;
        opcion_json = false;
        opcion_prueba = false;
        unowned string[] args = args_in;
        try {
            var ctx = new OptionContext ("");
            ctx.add_main_entries (OPCIONES, null);
            ctx.add_group (Gtk.get_option_group (true));
            ctx.parse (ref args);
        } catch (Error e) {
            error ("mac-sesion: %s\n".printf (e.message));
            return 2;
        }
        if (opcion_modo == null || !(opcion_modo in new string[] { "shutdown", "restart", "logoff", "guestlogout" })) {
            error ("mac-sesion: --mode debe ser shutdown, restart, logoff o guestlogout\n");
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
                salida ("{\"mode\": \"guestlogout\", \"confirmed\": %s, \"executed\": %s, \"prueba\": %s}\n".printf (
                        tf (resp == MacOS.Alerta.ACEPTAR), tf (ejecutado), tf (opcion_prueba)));
            }
            return 0;
        }

        // Reiniciar con otros usuarios conectados: Catalina no enseña la confirmación de siempre sino la clave de
        // administrador (el agente de polkit de mint-macos); si no hay agente, la confirmación de siempre.
        if (modo == "restart" && !opcion_prueba && otras_sesiones ().length > 0) {
            var resultado = reiniciar_con_otras_sesiones ();
            if (opcion_json) {
                salida ("{\"mode\": \"restart\", \"otras_sesiones\": true, \"resultado\": \"%s\"}\n".printf (resultado));
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
            salida ("{\"mode\": \"%s\", \"confirmed\": %s, \"reopen\": %s, \"executed\": %s, \"prueba\": %s, \"seconds\": %d}\n".printf (
                    modo, tf (resp == MacOS.Alerta.ACEPTAR), tf (reabrir), tf (ejecutado), tf (opcion_prueba),
                    opcion_segundos));
        }
        return 0;
    }
}
