/*
 * mac-acerca [--pestana overview|displays|storage] [--texto]: About This Mac / About This PC.
 * Con --texto imprime lo que leyó del equipo (para las pruebas) y no abre ventana.
 */
public class Aplicacion : Gtk.Application {
    Acerca.Ventana? ventana = null;
    string pestana = "overview";

    public Aplicacion () {
        Object (application_id: "io.github.josemalena.MintMacosAcerca", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        for (int i = 1; i < args.length; i++) {
            if (args[i] == "--pestana" && i + 1 < args.length) pestana = args[++i];
            if (args[i] == "--texto") {
                cmd.print ("%s", Acerca.resumen ());
                return 0;
            }
        }
        abrir (pestana);
        return 0;
    }

    void abrir (string p) {
        if (ventana != null) {
            ventana.ir_a (p);
            return;
        }
        ventana = new Acerca.Ventana (p);
        add_window (ventana);
        ventana.destroy.connect (() => { ventana = null; });
    }
}

int main (string[] args) {
    Environment.set_prgname ("mac-acerca");
    return new Aplicacion ().run (args);
}
