/*
 * La ventana «Force Quit Applications» de Catalina, con las medidas de la captura 15-force-quit-oscuro
 * (a 1x): cuerpo #2A2B2D de 337 × 285 bajo la barra de título, lista de 298 × 168 en (19, 60) con filas de 22 px,
 * fondo #1B1C1E, borde #555555 y selección #004ECA; botón de 84 × 21 en (233, 244). El texto cambia a «Relaunch»
 * con Finder (aquí Fynder). La barra de título con sus tres botones la pone el tema de ventanas.
 */
namespace MacForceQuit {
    const string CSS = """
window.fq-ventana { background-color: #2a2b2d; }
window.fq-ventana label { font-family: ".SF NS"; color: #e6e6e6; }
window.fq-ventana label.fq-texto { font-size: 12.4px; }
window.fq-ventana label.fq-pie { font-size: 9.6px; }
.fq-lista { background-color: #1b1c1e; border: 1px solid #555555; }
.fq-lista list, .fq-lista row { background-color: #1b1c1e; }
.fq-lista row { min-height: 22px; padding: 0 0 0 6px; border: none; }
.fq-lista row:selected, .fq-lista row:selected label { background-color: #004eca; color: #ffffff; }
window.fq-ventana .fq-lista label { font-size: 13px; }
button.fq-boton { background-image: linear-gradient(to bottom, #296ee7, #1453c7); background-color: #1659d4;
  border: 1px solid #252627; border-radius: 4px; padding: 0; min-height: 19px; min-width: 82px;
  box-shadow: none; text-shadow: none; }
window.fq-ventana button.fq-boton label { font-size: 13px; color: #ffffff; }
window.fq-ventana label.fq-colgada { color: #ff453a; }
button.fq-boton:disabled { background-image: none; background-color: #3a3b3d; border-color: #2f3031; }
button.fq-boton:disabled label { color: rgba(255, 255, 255, 0.35); }
""";

    // La Catalina clara (15-force-quit-claro): cuerpo #E9E9E9, lista blanca con borde #BDBDBD, texto #262626, selección #0058DD con texto blanco.
    const string CSS_CLARO = """
window.fq-ventana { background-color: #e9e9e9; }
window.fq-ventana label { color: #262626; }
.fq-lista { background-color: #ffffff; border: 1px solid #bdbdbd; }
.fq-lista list, .fq-lista row { background-color: #ffffff; }
.fq-lista row:selected, .fq-lista row:selected label { background-color: #0058dd; color: #ffffff; }
window.fq-ventana label.fq-colgada { color: #d70015; }
window.fq-ventana .fq-lista row:selected label.fq-colgada { color: #ffffff; }
button.fq-boton { background-image: linear-gradient(to bottom, #5c9bfd, #3a82fc); background-color: #498bfc; border: 1px solid #357efd; }
button.fq-boton:disabled { background-image: none; background-color: #d4d4d4; border-color: #c4c4c4; }
button.fq-boton:disabled label { color: rgba(0, 0, 0, 0.35); }
""";

    class Fila : Gtk.ListBoxRow {
        public App app;
        public Fila (App app) {
            this.app = app;
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            if (app.icono != null) {
                caja.pack_start (new Gtk.Image.from_pixbuf (app.icono), false, false, 0);
            } else {
                var vacio = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                vacio.set_size_request (16, 16);
                caja.pack_start (vacio, false, false, 0);
            }
            // loginwindow.strings: APP_NOT_RESPONDING_SUFFIX = « (not responding)»; la fila de una app colgada sale en rojo
            var l = new Gtk.Label (app.no_responde ? app.nombre + " (not responding)" : app.nombre);
            l.xalign = 0;
            l.ellipsize = Pango.EllipsizeMode.END;
            if (app.no_responde) {
                l.get_style_context ().add_class ("fq-colgada");
            }
            caja.pack_start (l, true, true, 0);
            add (caja);
        }
    }

    public class Ventana : Gtk.Window {
        Gtk.ListBox lista;
        Gtk.Label texto;
        Gtk.Button boton;
        Gtk.Label rotulo_boton;
        uint repintar = 0;
        bool sin_prueba;

        public Ventana (bool sin_prueba, int seleccionar_pid = 0) {
            Object (type: Gtk.WindowType.TOPLEVEL);
            this.sin_prueba = sin_prueba;
            title = "Force Quit Applications";
            resizable = false;
            window_position = Gtk.WindowPosition.CENTER;
            type_hint = Gdk.WindowTypeHint.NORMAL;
            skip_taskbar_hint = true;
            skip_pager_hint = true;
            get_style_context ().add_class ("fq-ventana");
            MacOS.aplicar_css_con_claro (CSS, CSS_CLARO);

            var fijo = new Gtk.Fixed ();
            fijo.set_size_request (337, 285);
            texto = new Gtk.Label ("");
            texto.xalign = 0;
            texto.yalign = 0;
            texto.wrap = true;
            texto.max_width_chars = 32;
            texto.set_size_request (300, 34);
            texto.get_style_context ().add_class ("fq-texto");
            fijo.put (texto, 19, 21);

            lista = new Gtk.ListBox ();
            lista.selection_mode = Gtk.SelectionMode.SINGLE;
            lista.can_focus = false;
            var marco = new Gtk.ScrolledWindow (null, null);
            marco.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            marco.set_size_request (298, 168);
            marco.get_style_context ().add_class ("fq-lista");
            marco.add (lista);
            fijo.put (marco, 19, 60);

            var pie = new Gtk.Label ("You can open this window by pressing Command-Option-Escape.");
            pie.xalign = 0;
            pie.yalign = 0;
            pie.wrap = true;
            pie.max_width_chars = 34;
            pie.set_size_request (200, 30);
            pie.get_style_context ().add_class ("fq-pie");
            fijo.put (pie, 19, 242);

            boton = new Gtk.Button ();
            boton.get_style_context ().add_class ("fq-boton");
            rotulo_boton = new Gtk.Label ("Force Quit");
            boton.add (rotulo_boton);
            boton.set_size_request (84, 21);
            boton.sensitive = false;
            boton.can_focus = false;
            fijo.put (boton, 233, 244);
            add (fijo);

            lista.row_selected.connect (al_escoger);
            lista.row_activated.connect (() => { forzar (); });
            boton.clicked.connect (forzar);
            // Sin foco en la lista (GTK le selecciona la primera fila): las flechas se manejan aquí.
            key_press_event.connect ((ev) => {
                switch (ev.keyval) {
                case Gdk.Key.Escape:
                    close ();
                    return true;
                case Gdk.Key.Down:
                    mover (1);
                    return true;
                case Gdk.Key.Up:
                    mover (-1);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    forzar ();
                    return true;
                }
                return false;
            });
            destroy.connect (() => {
                if (Gtk.main_level () > 0) {      // suelto: sale; dentro del residente no hay Gtk.main
                    Gtk.main_quit ();
                }
            });

            var pantalla = Wnck.Screen.get_default ();
            pantalla.window_opened.connect (() => { pedir_repintado (); });
            pantalla.window_closed.connect (() => { pedir_repintado (); });

            if (seleccionar_pid > 0) {
                marcar_colgado (seleccionar_pid);
            }
            poblar ();
            al_escoger (null);
            show_all ();
            lista.unselect_all ();
            set_focus (null);
            if (seleccionar_pid > 0) {
                seleccionar (seleccionar_pid);
            }
        }

        /** Marca como colgada y escoge la app dueña de ese pid (si ya hay una ventana abierta, la trae al frente). */
        public void seleccionar (int pid) {
            marcar_colgado (pid);
            poblar ();
            foreach (var h in lista.get_children ()) {
                var f = h as Fila;
                if (f == null) {
                    continue;
                }
                for (int i = 0; i < f.app.pids.length; i++) {
                    if (f.app.pids.index (i) == pid) {
                        lista.select_row (f);
                        break;
                    }
                }
            }
            present ();
        }

        void mover (int paso) {
            var actual = lista.get_selected_row ();
            int n = (actual == null) ? (paso > 0 ? 0 : -1) : actual.get_index () + paso;
            var f = lista.get_row_at_index (n);
            if (f != null) {
                lista.select_row (f);
            }
        }

        void pedir_repintado () {
            if (repintar != 0) {
                return;
            }
            repintar = Timeout.add (250, () => {
                repintar = 0;
                poblar ();
                return false;
            });
        }

        /** Vuelve a armar la lista y conserva la selección por la clase de la app. */
        void poblar () {
            string? escogida = null;
            var actual = lista.get_selected_row () as Fila;
            if (actual != null) {
                escogida = actual.app.clase;
            }
            foreach (var h in lista.get_children ()) {
                lista.remove (h);
            }
            Fila? volver = null;
            foreach (var app in recoger ()) {
                var f = new Fila (app);
                f.can_focus = false;
                lista.add (f);
                if (app.clase == escogida) {
                    volver = f;
                }
            }
            lista.show_all ();
            if (volver != null) {
                lista.select_row (volver);
            } else {
                al_escoger (null);
            }
        }

        void al_escoger (Gtk.ListBoxRow? fila) {
            var f = fila as Fila;
            bool fynder = f != null && f.app.es_fynder;
            string accion = fynder ? "Relaunch" : "Force Quit";
            texto.label = "If an app doesn’t respond for a while, select its name and click %s.".printf (accion);
            rotulo_boton.label = accion;
            boton.sensitive = f != null;
        }

        void forzar () {
            var f = lista.get_selected_row () as Fila;
            if (f == null) {
                return;
            }
            bool relanzar = f.app.es_fynder;
            int[] pids = {};
            for (int i = 0; i < f.app.pids.length; i++) {
                pids += f.app.pids.index (i);
            }
            if (!sin_prueba) {
                return;
            }
            foreach (int p in pids) {
                Posix.kill ((Posix.pid_t) p, Posix.Signal.TERM);
            }
            Timeout.add (1200, () => {
                foreach (int p in pids) {
                    Posix.kill ((Posix.pid_t) p, Posix.Signal.KILL);
                }
                if (relanzar) {
                    try {
                        Process.spawn_command_line_async (Environment.get_home_dir () + "/.local/bin/fynder");
                    } catch (Error e) {
                        warning ("no pude relanzar Fynder: %s", e.message);
                    }
                }
                return false;
            });
        }
    }
}
