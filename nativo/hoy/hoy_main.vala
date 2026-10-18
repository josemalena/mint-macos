/*
 * mac-hoy: el servicio org.mintmacos.Hoy1 suelto (pruebas). mac-ventanas --residente lo lleva dentro.
 */
int main (string[] args) {
    var loop = new MainLoop ();
    int salida = 0;
    Hoy.Anfitrion.iniciar (() => { salida = 1; loop.quit (); });
    loop.run ();
    return salida;
}
