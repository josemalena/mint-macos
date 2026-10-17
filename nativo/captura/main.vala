/*
 * mac-captura-herramienta-vala: la barra de ⇧⌘5. Se abre, hace su captura y sale; pedirla estando abierta la
 * trae al frente (mismo id de aplicación D-Bus, un solo proceso a la vez).
 */
public class Aplicacion : Gtk.Application {
    Captura.Barra? barra = null;

    public Aplicacion () {
        Object (application_id: "io.github.josemalena.MintMacosCaptura", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void activate () {
        if (barra != null) {
            if (!barra.ocupada) barra.present ();
            return;
        }
        barra = new Captura.Barra (this);
        barra.destroy.connect (() => { barra = null; });
    }
}

int main (string[] args) {
    Environment.set_prgname ("mac-captura-herramienta");
    var app = new Aplicacion ();
    return app.run (args);
}
