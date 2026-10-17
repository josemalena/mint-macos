/*
 * Las capas a pantalla completa que se ponen encima del escritorio: el cursor de cámara que resalta la ventana
 * bajo el ratón (Elegir) y el marco ajustable de «Capture Selected Portion» (Marco).
 */
namespace Captura {
    public delegate void ResolverVentana (string? wid);

    /** La ventana a pantalla completa deja pasar los clics sobre la barra (y la barra sigue arriba). */
    public void dejar_pasar_a_la_barra (Gtk.Window ventana, Gtk.Window barra, out Gdk.Rectangle hueco) {
        hueco = Gdk.Rectangle ();
        var gw = ventana.get_window ();
        var gb = barra.get_window ();
        if (gw == null || gb == null) return;
        var pant = ventana.get_screen ();
        var region = new Cairo.Region.rectangle (Cairo.RectangleInt () { x = 0, y = 0, width = pant.get_width (), height = pant.get_height () });
        Gdk.Rectangle r;
        gb.get_frame_extents (out r);
        region.subtract_rectangle (Cairo.RectangleInt () { x = r.x, y = r.y, width = r.width, height = r.height });
        gw.input_shape_combine_region (region, 0, 0);
        gb.raise ();
        hueco = r;
    }

    class VentanaVisible {
        public string wid;
        public int x;
        public int y;
        public int w;
        public int h;
    }

    /**
     * Cursor de cámara: al pasar sobre una ventana se resalta; un clic la elige.
     * Resuelve con el id de la ventana, o null si se cancela con Esc o con otro botón.
     */
    public class Elegir : Gtk.Window {
        ResolverVentana al_resolver;
        List<VentanaVisible> ventanas;
        VentanaVisible? sel = null;

        public Elegir (ResolverVentana al_resolver, Gtk.Window barra) {
            Object (type: Gtk.WindowType.POPUP);
            this.al_resolver = al_resolver;
            var scr = get_screen ();
            if (scr.get_rgba_visual () != null) set_visual (scr.get_rgba_visual ());
            set_app_paintable (true);
            set_decorated (false);
            set_keep_above (true);
            add_events (Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.KEY_PRESS_MASK);
            ventanas = listar ();       // antes de mostrarse: esta capa no sale en la lista
            move (0, 0);
            resize (scr.get_width (), scr.get_height ());
            show_all ();
            var gw = get_window ();
            gw.set_cursor (cursor_camara (get_display ()));
            gw.focus (Gdk.CURRENT_TIME);
            Gdk.Rectangle hueco;
            dejar_pasar_a_la_barra (this, barra, out hueco);
        }

        /** Ventanas visibles de arriba hacia abajo, con su marco; sin sombra propia (_GTK_FRAME_EXTENTS). */
        List<VentanaVisible> listar () {
            var salida = new List<VentanaVisible> ();
            var pila = get_screen ().get_window_stack ();
            pila.reverse ();
            foreach (var w in pila) {
                if (!w.is_visible () || (w.get_state () & Gdk.WindowState.ICONIFIED) != 0) continue;
                var tipo = w.get_type_hint ();
                if (tipo == Gdk.WindowTypeHint.DESKTOP || tipo == Gdk.WindowTypeHint.DOCK) continue;
                var x11 = w as Gdk.X11.Window;
                if (x11 == null) continue;
                Gdk.Rectangle r;
                w.get_frame_extents (out r);
                var ext = extensiones_gtk (w);
                var v = new VentanaVisible ();
                v.wid = ((ulong) x11.get_xid ()).to_string ();
                v.x = r.x + ext[0];
                v.y = r.y + ext[2];
                v.w = r.width - ext[0] - ext[1];
                v.h = r.height - ext[2] - ext[3];
                salida.append (v);
            }
            return salida;
        }

        public override bool motion_notify_event (Gdk.EventMotion e) {
            VentanaVisible? nuevo = null;
            foreach (var v in ventanas) {
                if (v.x <= e.x_root && e.x_root < v.x + v.w && v.y <= e.y_root && e.y_root < v.y + v.h) {
                    nuevo = v;
                    break;
                }
            }
            if (nuevo != sel) {
                sel = nuevo;
                queue_draw ();
            }
            return false;
        }

        public override bool draw (Cairo.Context cr) {
            cr.set_operator (Cairo.Operator.SOURCE);
            cr.set_source_rgba (0, 0, 0, 0.01);
            cr.paint ();
            if (sel != null) {
                cr.set_operator (Cairo.Operator.OVER);
                cr.set_source_rgba (0.25, 0.5, 0.95, 0.35);
                cr.rectangle (sel.x, sel.y, sel.w, sel.h);
                cr.fill ();
            }
            return true;
        }

        public override bool button_press_event (Gdk.EventButton e) {
            if (e.button == 1 && sel != null) {
                cerrar (sel.wid);
            } else if (e.button != 1) {
                cerrar (null);
            }
            return false;
        }

        public override bool key_press_event (Gdk.EventKey e) {
            if (e.keyval == Gdk.Key.Escape) cerrar (null);
            return false;
        }

        void cerrar (string? wid) {
            destroy ();
            al_resolver (wid);
        }
    }

    /**
     * Como en la Mac: un marco ya puesto, que se mueve arrastrando por dentro y se ajusta por los bordes y las
     * esquinas. El botón Capture toma lo que queda dentro.
     */
    public class Marco : Gtk.Window {
        const int AGARRE = 9;
        const int MINIMO = 40;

        int ancho;
        int alto;
        double[] rect;                       // x, y, w, h
        string? zona_arrastre = null;
        double ax;
        double ay;
        double[] r0 = {};
        Gdk.Rectangle hueco_barra;
        bool hay_hueco = false;

        public Marco (int[] r, Gtk.Window barra) {
            Object (type: Gtk.WindowType.POPUP);
            var scr = get_screen ();
            if (scr.get_rgba_visual () != null) set_visual (scr.get_rgba_visual ());
            set_app_paintable (true);
            set_decorated (false);
            set_keep_above (true);
            ancho = scr.get_width ();
            alto = scr.get_height ();
            rect = { r[0], r[1], r[2], r[3] };
            add_events (Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.POINTER_MOTION_MASK);
            move (0, 0);
            resize (ancho, alto);
            show_all ();
            dejar_pasar_a_la_barra (this, barra, out hueco_barra);
            hay_hueco = hueco_barra.width > 0;
        }

        public int[] get_rect () {
            return { (int) rect[0], (int) rect[1], (int) rect[2], (int) rect[3] };
        }

        string? zona (double px, double py) {
            double x = rect[0], y = rect[1], w = rect[2], h = rect[3];
            if (!(x - AGARRE <= px && px <= x + w + AGARRE && y - AGARRE <= py && py <= y + h + AGARRE)) return null;
            bool izq = Math.fabs (px - x) <= AGARRE, der = Math.fabs (px - (x + w)) <= AGARRE;
            bool arr = Math.fabs (py - y) <= AGARRE, aba = Math.fabs (py - (y + h)) <= AGARRE;
            var z = (arr ? "n" : aba ? "s" : "") + (izq ? "w" : der ? "e" : "");
            return z == "" ? "mover" : z;
        }

        void poner_cursor (string? z) {
            string nombre = "default";
            switch (z) {
            case "n": case "s": nombre = "ns-resize"; break;
            case "e": case "w": nombre = "ew-resize"; break;
            case "nw": case "se": nombre = "nwse-resize"; break;
            case "ne": case "sw": nombre = "nesw-resize"; break;
            case "mover": nombre = "move"; break;
            }
            var gw = get_window ();
            if (gw != null) gw.set_cursor (new Gdk.Cursor.from_name (get_display (), nombre));
        }

        public override bool draw (Cairo.Context cr) {
            double x = rect[0], y = rect[1], w = rect[2], h = rect[3];
            cr.set_operator (Cairo.Operator.SOURCE);
            cr.set_source_rgba (0, 0, 0, 0.25);
            cr.paint ();
            cr.set_source_rgba (0, 0, 0, 0.01);
            cr.rectangle (x, y, w, h);
            cr.fill ();
            if (hay_hueco) {          // la barra no se atenúa
                cr.set_source_rgba (0, 0, 0, 0);
                cr.rectangle (hueco_barra.x, hueco_barra.y, hueco_barra.width, hueco_barra.height);
                cr.fill ();
            }
            cr.set_operator (Cairo.Operator.OVER);
            cr.set_source_rgba (1, 1, 1, 0.95);
            cr.set_line_width (1);
            cr.rectangle (x + 0.5, y + 0.5, w, h);
            cr.stroke ();
            double[,] asas = { { x, y }, { x + w / 2, y }, { x + w, y }, { x, y + h / 2 }, { x + w, y + h / 2 },
                               { x, y + h }, { x + w / 2, y + h }, { x + w, y + h } };
            for (int i = 0; i < 8; i++) {
                cr.rectangle (asas[i, 0] - 3, asas[i, 1] - 3, 7, 7);
                cr.set_source_rgba (1, 1, 1, 1);
                cr.fill_preserve ();
                cr.set_source_rgba (0, 0, 0, 0.5);
                cr.stroke ();
            }
            cr.set_source_rgba (1, 1, 1, 1);
            cr.set_font_size (12);
            cr.move_to (x + w + 6, y + h + 16);
            cr.show_text ("%d×%d".printf ((int) w, (int) h));
            return true;
        }

        public override bool button_press_event (Gdk.EventButton e) {
            var z = zona (e.x_root, e.y_root);
            if (z != null && e.button == 1) {
                zona_arrastre = z;
                ax = e.x_root;
                ay = e.y_root;
                r0 = { rect[0], rect[1], rect[2], rect[3] };
            }
            return false;
        }

        public override bool motion_notify_event (Gdk.EventMotion e) {
            if (zona_arrastre == null) {
                poner_cursor (zona (e.x_root, e.y_root));
                return false;
            }
            double dx = e.x_root - ax, dy = e.y_root - ay;
            double x = r0[0], y = r0[1], w = r0[2], h = r0[3];
            var z = zona_arrastre;
            if (z == "mover") {
                x = Math.fmin (Math.fmax (0, x + dx), ancho - w);
                y = Math.fmin (Math.fmax (0, y + dy), alto - h);
            } else {
                if (z.contains ("w")) {
                    double nx = Math.fmin (Math.fmax (0, x + dx), x + w - MINIMO);
                    w = w + (x - nx);
                    x = nx;
                }
                if (z.contains ("e")) w = Math.fmin (Math.fmax (MINIMO, w + dx), ancho - x);
                if (z.contains ("n")) {
                    double ny = Math.fmin (Math.fmax (0, y + dy), y + h - MINIMO);
                    h = h + (y - ny);
                    y = ny;
                }
                if (z.contains ("s")) h = Math.fmin (Math.fmax (MINIMO, h + dy), alto - y);
            }
            rect = { x, y, w, h };
            queue_draw ();
            return false;
        }

        public override bool button_release_event (Gdk.EventButton e) {
            zona_arrastre = null;
            return false;
        }
    }
}
