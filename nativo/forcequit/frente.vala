/*
 * ⌥⇧⌘⎋: fuerza la salida de la app del frente, como en la Mac. Es lo mismo que «Force Quit <app>» del menú Apple con
 * Shift apretado (antes, applets/applemenu@macos/forzar-app-del-frente.py). Nunca toca el escritorio ni el panel: si al
 * frente está uno de esos, o no hay ventana activa, no hace nada.
 */
namespace MacForceQuit {
    public int app_del_frente () {
        var pantalla = Wnck.Screen.get_default ();
        pantalla.force_update ();
        var ventana = pantalla.get_active_window ();
        if (ventana == null) {
            return 0;
        }
        var tipo = ventana.get_window_type ();
        if (tipo == Wnck.WindowType.DESKTOP || tipo == Wnck.WindowType.DOCK) {
            return 0;
        }
        int pid = ventana.get_pid ();
        if (pid <= 1) {
            return 0;
        }
        Posix.kill ((Posix.pid_t) pid, Posix.Signal.KILL);
        return 0;
    }
}
