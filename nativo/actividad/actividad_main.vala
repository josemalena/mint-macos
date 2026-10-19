/*
 * mac-actividad [--pestana cpu|memory|energy|disk|network|resources]: Activity Monitor. Una sola ventana; si ya está abierta
 * se trae al frente.
 */
public class Aplicacion : Gtk.Application {
    Actividad.Ventana? ventana = null;

    public Aplicacion () {
        Object (application_id: "io.github.josemalena.MintMacosActividad", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    protected override void startup () {
        base.startup ();
        set_menubar (Actividad.Menus.construir ());
        MacOS.agregar_accion_acerca (this, "Activity Monitor", null, null, "utilities-system-monitor");
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        string pestana = "cpu";
        for (int i = 1; i < args.length; i++) {
            if (args[i] == "--pestana" && i + 1 < args.length) pestana = args[++i];
        }
        if (ventana == null) {
            ventana = new Actividad.Ventana (this);
            add_window (ventana);
            ventana.destroy.connect (() => { ventana = null; });
        }
        ventana.ir_a (pestana);
        ventana.present ();
        return 0;
    }
}

int main (string[] args) {
    Environment.set_prgname ("mac-actividad");
    return new Aplicacion ().run (args);
}
