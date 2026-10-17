/*
 * mac-forcequit: la ventana «Force Quit Applications» (⌥⌘⎋ y Apple ▸ Force Quit…). Reemplaza a forcekill.py.
 *   mac-forcequit            abre la ventana
 *   mac-forcequit --prueba   la abre y el botón no mata nada
 */
int main (string[] args) {
    bool prueba = false;
    foreach (var a in args[1:args.length]) {
        if (a == "--prueba") {
            prueba = true;
        }
    }
    Gtk.init (ref args);
    new MacForceQuit.Ventana (!prueba);
    Gtk.main ();
    return 0;
}
