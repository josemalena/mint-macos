/*
 * mac-menu: el servicio org.mintmacos.Menu1 suelto (para las pruebas y por si no conviene dentro de mac-ventanas).
 * mac-ventanas --residente lo lleva dentro con las mismas fuentes.
 */
int main (string[] args) {
    Gtk.init (ref args);
    var loop = new MainLoop ();
    var servicio = new Menu.Servicio ();
    int salida = 0;
    Bus.own_name (BusType.SESSION, "org.mintmacos.Menu1", BusNameOwnerFlags.NONE,
        (con) => {
            try {
                con.register_object ("/org/mintmacos/Menu1", servicio);
                servicio.registrar (con);
            } catch (IOError e) {
                warning ("%s", e.message);
                salida = 1;
                loop.quit ();
            }
        },
        null,
        () => { warning ("org.mintmacos.Menu1 ya existe"); salida = 1; loop.quit (); });
    loop.run ();
    return salida;
}
