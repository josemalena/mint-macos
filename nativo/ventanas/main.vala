/*
 * mac-ventanas: el residente de las ventanas chicas (el equivalente de loginwindow en macOS). Un solo proceso con GTK ya
 * cargado que arranca oculto con la sesión y abre al instante:
 *
 *   mac-ventanas --residente                         se arma oculto y espera (autostart)
 *   mac-ventanas sesion --mode logoff|restart|shutdown|guestlogout [--seconds N] [--print-json] [--prueba]
 *   mac-ventanas forcequit [--prueba]                «Force Quit Applications» (⌥⌘⎋)
 *   mac-ventanas app-del-frente                      fuerza la salida de la app activa (⌥⇧⌘⎋)
 *   mac-ventanas captura                             la barra de ⇧⌘5
 *   mac-ventanas emojis [--destino ID]               el selector de emojis (⌃⌘Espacio)
 *   mac-ventanas acerca [--pestana overview|displays|storage]   About This Mac / About This PC
 *
 * Cada orden es una línea de comandos de GApplication: si ya hay un residente, el cliente se la manda y espera su
 * resultado (lo que imprime y el código de salida llegan al cliente, así el JSON de «sesion» sigue siendo el de siempre);
 * si no lo hay, este mismo proceso se arma, hace la acción y sale cuando se cierra la última ventana (el modo «en frío»,
 * que es también la vuelta atrás). Ni apaga ni cierra sesión por su cuenta: lo hacen los comandos de mac-sesion.
 */
public class Ventanas : Gtk.Application {
    Captura.Barra? barra = null;
    MacForceQuit.Ventana? forcequit = null;
    Acerca.Ventana? acerca = null;
    Emojis.Selector? emojis = null;
    bool residente = false;

    public Ventanas () {
        Object (application_id: "io.github.josemalena.MintMacosVentanas", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        if (args.length < 2) {
            cmd.printerr ("uso: mac-ventanas --residente | sesion … | forcequit [--prueba] | app-del-frente | captura | acerca | emojis\n");
            return 2;
        }
        switch (args[1]) {
        case "--residente":
            if (!residente) {
                residente = true;
                hold ();                    // sigue vivo sin ventanas
                Idle.add (precalentar);
            }
            return 0;
        case "sesion":
            string[] resto = { "mac-ventanas" };
            for (int i = 2; i < args.length; i++) {
                resto += args[i];
            }
            return Sesion.atender (resto, (t) => { cmd.print ("%s", t); }, (t) => { cmd.printerr ("%s", t); });
        case "forcequit":
            bool prueba = false;
            for (int i = 2; i < args.length; i++) {
                if (args[i] == "--prueba") {
                    prueba = true;
                }
            }
            abrir_forcequit (!prueba);
            return 0;
        case "app-del-frente":
            return MacForceQuit.app_del_frente ();
        case "captura":
            abrir_captura ();
            return 0;
        case "emojis":
            string destino = "";
            for (int i = 2; i + 1 < args.length; i++) {
                if (args[i] == "--destino") destino = args[i + 1];
            }
            abrir_emojis (destino);
            return 0;
        case "acerca":
            string pestana = "overview";
            for (int i = 2; i + 1 < args.length; i++) {
                if (args[i] == "--pestana") pestana = args[i + 1];
            }
            abrir_acerca (pestana);
            return 0;
        default:
            cmd.printerr ("mac-ventanas: no conozco «%s»\n", args[1]);
            return 2;
        }
    }

    void abrir_forcequit (bool matar) {
        if (forcequit != null) {
            forcequit.present ();
            return;
        }
        forcequit = new MacForceQuit.Ventana (matar);
        add_window (forcequit);
        forcequit.destroy.connect (() => { forcequit = null; });
    }

    void abrir_emojis (string destino) {
        if (emojis != null) return;        // ya hay uno abierto
        emojis = new Emojis.Selector (destino, () => { emojis = null; });
        add_window (emojis);
    }

    void abrir_acerca (string pestana) {
        if (acerca != null) {
            acerca.ir_a (pestana);
            return;
        }
        acerca = new Acerca.Ventana (pestana);
        add_window (acerca);
        acerca.destroy.connect (() => { acerca = null; });
    }

    void abrir_captura () {
        if (barra != null) {
            if (!barra.ocupada) {
                barra.present ();
            }
            return;
        }
        barra = new Captura.Barra (this);
        barra.destroy.connect (() => { barra = null; });
    }

    /** Deja listo lo que tarda en la primera vez: el CSS, las fuentes, los íconos y las listas que consulta la barra. */
    bool precalentar () {
        MacOS.aplicar_estilo_alerta ();
        Captura.micros ();
        Captura.escritorio ();
        var v = new MacForceQuit.Ventana (false);       // sin mostrarla: arma la lista de apps y sus íconos
        v.destroy ();
        return false;
    }
}

int main (string[] args) {
    Environment.set_prgname ("mac-ventanas");
    return new Ventanas ().run (args);
}
