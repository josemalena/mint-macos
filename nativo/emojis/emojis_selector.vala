/*
 * Selector de emojis para ⌃⌘Espacio (puerto de capturas/emojis.py, mismo comportamiento): abre el selector de emojis de
 * GTK (categorías, búsqueda y recientes) junto al puntero. El emoji elegido se copia al portapapeles y se escribe en la
 * ventana que estaba al frente (xdotool type); si esa app no lo acepta escrito, queda en el portapapeles para ⌘V.
 * Esc o un clic afuera lo cierra sin hacer nada.
 * En X11 el selector de GTK se dibuja DENTRO de la ventana que lo abre: la ventana es del tamaño del selector y
 * transparente, y el selector cuelga de un GtkEntry invisible.
 */
namespace Emojis {
    const int ANCHO = 460;
    const int ALTO = 440;

    public delegate void Terminar ();

    public class Selector : Gtk.Window {
        string destino;
        string? elegido = null;
        bool abierto = false;
        bool terminado = false;
        Gtk.Entry entrada;
        Terminar al_terminar;

        public Selector (string destino, owned Terminar al_terminar) {
            Object (type: Gtk.WindowType.TOPLEVEL);
            this.destino = destino;
            this.al_terminar = (owned) al_terminar;
            decorated = false;
            skip_taskbar_hint = true;
            skip_pager_hint = true;
            set_keep_above (true);
            type_hint = Gdk.WindowTypeHint.UTILITY;
            set_default_size (ANCHO, ALTO);
            var visual = get_screen ().get_rgba_visual ();
            if (visual != null) set_visual (visual);
            MacOS.aplicar_css ("window.selector-emojis { background: transparent; }");
            get_style_context ().add_class ("selector-emojis");

            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            entrada = new Gtk.Entry ();
            entrada.opacity = 0.0;
            entrada.set_size_request (ANCHO, 1);
            entrada.changed.connect (al_elegir);
            caja.pack_start (entrada, false, false, 0);
            add (caja);

            // Junto al puntero, sin salirse de la pantalla.
            var display = Gdk.Display.get_default ();
            int x, y;
            display.get_default_seat ().get_pointer ().get_position (null, out x, out y);
            var mon = display.get_monitor_at_point (x, y).get_geometry ();
            x = int.min (int.max (mon.x, x - ANCHO / 2), mon.x + mon.width - ANCHO);
            y = int.min (int.max (mon.y, y), mon.y + mon.height - ALTO);
            move (x, y);
            key_press_event.connect ((e) => {
                if (e.keyval == Gdk.Key.Escape) terminar ();
                return false;
            });
            focus_out_event.connect (() => { if (elegido == null) terminar (); return false; });
            show_all ();
            Timeout.add (60, abrir);
        }

        bool abrir () {
            present_with_time (Gdk.CURRENT_TIME);
            entrada.grab_focus ();
            entrada.insert_emoji ();
            Timeout.add (150, vigilar);
            // Red de seguridad: si en 2 s el selector nunca tomó el foco, salir.
            Timeout.add (2000, () => { if (!abierto && elegido == null) terminar (); return false; });
            return false;
        }

        // Mientras el selector está abierto, el foco de la ventana está en su buscador; cuando se cierra (Esc o clic
        // afuera) vuelve a la entrada. Se vigila cada 150 ms: los eventos de foco no siempre llegan con el selector
        // dentro de la ventana.
        bool vigilar () {
            if (elegido != null || terminado) return false;
            var foco = get_focus ();
            if (foco != null && foco != entrada) {
                abierto = true;
            } else if (abierto) {
                terminar ();
                return false;
            }
            return true;
        }

        void al_elegir () {
            var texto = entrada.get_text ();
            if (texto == "" || elegido != null) return;
            elegido = texto;
            var portapapeles = Gtk.Clipboard.get (Gdk.SELECTION_CLIPBOARD);
            portapapeles.set_text (texto, -1);
            portapapeles.store ();
            hide ();
            Timeout.add (120, escribir);
        }

        bool escribir () {
            if (destino != "") {
                ejecutar ({ "xdotool", "windowactivate", "--sync", destino });
                ejecutar ({ "xdotool", "type", "--clearmodifiers", "--delay", "0", elegido });
            }
            // Que el portapapeles sobreviva un momento a la salida.
            Timeout.add (400, () => { terminar (); return false; });
            return false;
        }

        static void ejecutar (string[] cmd) {
            try {
                var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                p.wait ();
            } catch (Error e) {
                warning ("%s: %s", cmd[0], e.message);
            }
        }

        void terminar () {
            if (terminado) return;
            terminado = true;
            destroy ();
            al_terminar ();
        }
    }

    /** La ventana al frente (la que recibirá el emoji), antes de abrir el selector. */
    public string ventana_activa () {
        try {
            var p = new Subprocess.newv ({ "xdotool", "getactivewindow" }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            string s;
            p.communicate_utf8 (null, null, out s, null);
            return (s ?? "").strip ();
        } catch (Error e) {
            return "";
        }
    }
}
