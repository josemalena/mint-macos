/* mac-emojis-vala [--destino ID]: el selector de emojis, suelto. */
int main (string[] args) {
    Environment.set_prgname ("mac-emojis");
    Gtk.init (ref args);
    string destino = "";
    for (int i = 1; i + 1 < args.length; i++) {
        if (args[i] == "--destino") destino = args[i + 1];
    }
    if (destino == "") destino = Emojis.ventana_activa ();
    var s = new Emojis.Selector (destino, () => { Gtk.main_quit (); });
    s.show ();
    Gtk.main ();
    return 0;
}
