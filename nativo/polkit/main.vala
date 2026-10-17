/*
 * mac-polkit: el agente de polkit estilo Catalina en Vala (fase 1b). Se registra como agente de la sesión de
 * login de este proceso; si ya hay otro (el de Cinnamon) sale con 3 sin hacer nada, igual que agente.py.
 */
int main (string[] args) {
    Gtk.init (ref args);
    MacPolkit.VERBOSO = Environment.get_variable ("MINT_POLKIT_VERBOSO") != null;
    var agente = new MacPolkit.Agente ();
    void* registro = null;
    Polkit.Subject sujeto;
    try {
        sujeto = new Polkit.UnixSession.for_process_sync ((int) Posix.getpid (), null);
        registro = agente.register (PolkitAgent.RegisterFlags.NONE, sujeto, "/org/mintmacos/PolkitAgent", null);
    } catch (Error e) {
        stderr.printf ("No pude registrarme como agente de polkit: %s\n", e.message);
        return 3;
    }
    MacPolkit.log ("registrado como agente de la sesión " + ((Polkit.UnixSession) sujeto).get_session_id ());
    // SIGINT y SIGTERM: se da de baja antes de salir
    Unix.signal_add (Posix.Signal.INT, () => { PolkitAgent.Listener.unregister (registro); Gtk.main_quit (); return false; });
    Unix.signal_add (Posix.Signal.TERM, () => { PolkitAgent.Listener.unregister (registro); Gtk.main_quit (); return false; });
    Gtk.main ();
    return 0;
}
