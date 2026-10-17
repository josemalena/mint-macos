/*
 * mac-forcequit: la ventana «Force Quit Applications» (⌥⌘⎋ y Apple ▸ Force Quit…). Reemplaza a forcekill.py.
 *   mac-forcequit            abre la ventana
 *   mac-forcequit --prueba   la abre y el botón no mata nada
 *   mac-forcequit --app-del-frente   fuerza la salida de la app del frente (⌥⇧⌘⎋), sin abrir ventana
 */
int main (string[] args) {
    bool prueba = false;
    bool al_frente = false;
    foreach (var a in args[1:args.length]) {
        if (a == "--prueba") {
            prueba = true;
        } else if (a == "--app-del-frente") {
            al_frente = true;
        }
    }
    Gtk.init (ref args);
    if (al_frente) {
        return MacForceQuit.app_del_frente ();
    }
    new MacForceQuit.Ventana (!prueba);
    Gtk.main ();
    return 0;
}
