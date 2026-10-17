/*
 * mac-launchpad-vala: el Launchpad de Catalina, residente (se arma oculto con la sesión y el atajo lo muestra o lo
 * esconde por D-Bus). Mismo id de aplicación que el de Python: solo uno de los dos puede ser el residente.
 *
 *   mac-launchpad-vala              abre (o esconde, si ya está abierto); si no hay proceso, lo arma
 *   mac-launchpad-vala --residente  se arma oculto y espera el atajo
 *   mac-launchpad-vala --lista      lo que mostraría, sin abrir nada
 *   mac-launchpad-vala --png ARCHIVO [--pagina N] [--consulta TEXTO] [--carpeta]   un cuadro a PNG (pruebas; sin D-Bus)
 */
public class Aplicacion : Gtk.Application {
    public Launchpad.Ventana? ventana = null;
    public bool solo_armar = false;

    public Aplicacion () {
        Object (application_id: "io.github.josemalena.MintMacosLaunchpad", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void startup () {
        base.startup ();
        hold ();                       // residente: sigue vivo con la ventana oculta
    }

    protected override void activate () {
        // Pedirlo estando abierto lo esconde (F4 abre y cierra); si no existe, se arma.
        if (ventana == null) {
            ventana = new Launchpad.Ventana (this);
            ventana.precalentar ();
            if (solo_armar) {          // --residente: arranca con la sesión, sin enseñarse
                solo_armar = false;
                return;
            }
            ventana.mostrar ();
            return;
        }
        if (ventana.get_visible ()) {
            ventana.ocultar ();
        } else {
            ventana.mostrar ();
        }
    }
}

int main (string[] args) {
    bool lista = false, residente = false, carpeta = false;
    string? png = null;
    string consulta = "";
    int pagina = 0;
    for (int i = 1; i < args.length; i++) {
        switch (args[i]) {
        case "--lista": lista = true; break;
        case "--residente": residente = true; break;
        case "--carpeta": carpeta = true; break;
        case "--png": png = args[++i]; break;
        case "--consulta": consulta = args[++i]; break;
        case "--pagina": pagina = int.parse (args[++i]); break;
        }
    }
    if (lista || png != null) {
        // Sin Gtk.Application: no toca el bus de sesión.
        Gtk.init (ref args);
        var v = new Launchpad.Ventana (null, 1920, 1200);
        if (lista) {
            v.lista_a_texto ();
            return 0;
        }
        return v.a_png (png, pagina, consulta, carpeta) ? 0 : 1;
    }
    Environment.set_prgname ("mac-launchpad");
    var app = new Aplicacion ();
    app.solo_armar = residente;
    string[] limpio = { args[0] };
    return app.run (limpio);
}
