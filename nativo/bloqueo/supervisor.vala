/*
 * El supervisor del bloqueo: no dibuja nada ni usa GTK. Lanza la pantalla (mac-bloqueo --pantalla) y, si esa se cae de cualquier
 * manera que no sea «la clave correcta» (salida 0), la vuelve a lanzar al instante: la pantalla nunca queda abierta por un fallo
 * (fail-closed). Si el supervisor mismo muere, queda el archivo «bloqueado» y el vigilante (--vigilar) lo relanza.
 */
namespace Bloqueo.Supervisor {
    string yo () {
        try {
            return FileUtils.read_link ("/proc/self/exe");
        } catch (FileError e) {
            return "mac-bloqueo";
        }
    }

    /** Devuelve 0 cuando se desbloqueó con la clave; 0 también si ya había un supervisor (ese se encarga). */
    public int bloquear () {
        int candado = Estado.tomar_candado ();
        if (candado < 0) {
            return 0;
        }
        Estado.marcar ();
        while (true) {
            int64 inicio = get_monotonic_time ();
            int estado = -1;
            try {
                var p = new Subprocess (SubprocessFlags.NONE, yo (), "--pantalla");
                p.wait ();
                estado = p.get_if_exited () ? p.get_exit_status () : -1;
            } catch (Error e) {
                critical ("no pude lanzar la pantalla de bloqueo: %s", e.message);
            }
            if (estado == 0) {
                Estado.borrar ();
                Posix.close (candado);
                return 0;
            }
            // Cayó (señal, error o salida rara): se vuelve a lanzar ya. Si cae en bucle muy rápido, un respiro para no quemar CPU.
            if (get_monotonic_time () - inicio < 150000) {
                Thread.usleep (150000);
            }
        }
    }

    /** El vigilante: si debe estar bloqueado y nadie sostiene el candado, relanza el supervisor. Para un servicio de usuario. */
    public int vigilar () {
        while (true) {
            if (Estado.bloqueado () && !Estado.supervisor_vivo ()) {
                try {
                    new Subprocess (SubprocessFlags.NONE, yo ());
                } catch (Error e) {
                    critical ("el vigilante no pudo relanzar el bloqueo: %s", e.message);
                }
            }
            Thread.usleep (300000);
        }
    }
}
