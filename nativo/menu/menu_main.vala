/*
 * mac-menu: el servicio org.mintmacos.Menu1 suelto (para las pruebas y por si no conviene dentro de mac-ventanas).
 * mac-ventanas --residente lo lleva dentro con las mismas fuentes.
 */
int main (string[] args) {
    Gtk.init (ref args);
    var loop = new MainLoop ();
    int salida = 0;
    Menu.Anfitrion.iniciar (() => { salida = 1; loop.quit (); });
    loop.run ();
    return salida;
}
