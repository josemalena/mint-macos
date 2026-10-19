/*
 * mac-tienda [--seccion discover|create|work|play|develop|categories|updates] [--buscar TEXTO] [--ficha ID]:
 * el App Store. Una sola ventana; si ya está abierta, la vuelve a poner al frente en lo que se le pide.
 */
public class Aplicacion : Gtk.Application {
    Tienda.Ventana? ventana = null;

    public Aplicacion () {
        Object (application_id: "io.github.josemalena.MintMacosTienda", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
    }

    protected override void startup () {
        base.startup ();
        set_menubar (Tienda.Menus.construir ());
    }

    public override int command_line (ApplicationCommandLine cmd) {
        var args = cmd.get_arguments ();
        string seccion = "discover";
        string buscar = "";
        string ficha = "";
        for (int i = 1; i < args.length; i++) {
            if (args[i] == "--seccion" && i + 1 < args.length) seccion = args[++i];
            else if (args[i] == "--buscar" && i + 1 < args.length) buscar = args[++i];
            else if (args[i] == "--ficha" && i + 1 < args.length) ficha = args[++i];
        }
        if (ventana == null) {
            ventana = new Tienda.Ventana (this);
            add_window (ventana);
            ventana.destroy.connect (() => { ventana = null; });
        }
        if (ficha != "") ventana.abrir_ficha (ficha);
        else if (buscar != "") ventana.buscar (buscar);
        else ventana.ir_a_seccion (seccion);
        ventana.present ();
        return 0;
    }
}

int main (string[] args) {
    Environment.set_prgname ("mac-tienda");
    return new Aplicacion ().run (args);
}
