/*
 * Las piezas que se repiten en todas las pantallas del App Store: el ícono de una app, el botón GET (que se vuelve
 * el círculo de progreso mientras el motor trabaja), las capturas de la ficha y las filas de las listas.
 */
namespace Tienda {
    /** Del markup de AppStream (<p>, <ul>, <li>, <em>, <code>) al de Pango. */
    public string markup_a_pango (string origen) {
        var s = origen;
        try {
            s = new Regex ("\\s+").replace (s, -1, 0, " ");
            s = new Regex ("</p>\\s*").replace (s, -1, 0, "\n\n");
            s = new Regex ("</?(p|ul|ol)>\\s*").replace (s, -1, 0, "");
            s = new Regex ("<li>\\s*").replace (s, -1, 0, "•  ");
            s = new Regex ("\\s*</li>\\s*").replace (s, -1, 0, "\n");
            s = new Regex ("<(/?)em>").replace (s, -1, 0, "<\\1i>");
            s = new Regex ("<(/?)code>").replace (s, -1, 0, "<\\1tt>");
            s = new Regex ("<(?!/?(b|i|tt|u)>)[^>]*>").replace (s, -1, 0, "");
            s = new Regex ("&(?!(amp|lt|gt|quot|apos|#[0-9]+);)").replace (s, -1, 0, "&amp;");
        } catch (RegexError e) {
            return Markup.escape_text (origen);
        }
        return s.strip ();
    }

    public string tamano_texto (uint64 bytes) {
        return format_size (bytes, FormatSizeFlags.DEFAULT);
    }

    public class IconoApp : Gtk.Image {
        string url_pendiente = "";
        ulong enganche = 0;

        public IconoApp (Resumen r, int tam) {
            pixel_size = tam;
            set_from_icon_name ("application-x-executable", Gtk.IconSize.DIALOG);
            if (r.icono.has_prefix ("/")) {
                cargar (r.icono, tam);
            } else {
                if (r.icono_tema != "" && Gtk.IconTheme.get_default ().has_icon (r.icono_tema))
                    set_from_icon_name (r.icono_tema, Gtk.IconSize.DIALOG);
                if (r.icono != "") {
                    url_pendiente = r.icono;
                    enganche = Motor.instancia.icono_listo.connect ((url, ruta) => {
                        if (url == url_pendiente) cargar (ruta, tam);
                    });
                    destroy.connect (() => { if (enganche != 0) Motor.instancia.disconnect (enganche); });
                }
            }
            pixel_size = tam;
        }

        void cargar (string ruta, int tam) {
            try {
                set_from_pixbuf (new Gdk.Pixbuf.from_file_at_size (ruta, tam, tam));
            } catch (Error e) {
                // se queda el ícono genérico
            }
        }
    }

    /** GET / Open / Update, y mientras el motor trabaja, el círculo de progreso (un clic cancela). */
    public class BotonGet : Gtk.Stack {
        Resumen r;
        Gtk.Button boton;
        Gtk.DrawingArea anillo;
        string? trabajo = null;
        uint pct = 101;
        double giro = 0;
        uint reloj = 0;
        ulong h_progreso = 0;
        ulong h_terminado = 0;
        public signal void cambio ();

        public BotonGet (Resumen r) {
            this.r = r;
            homogeneous = false;
            valign = Gtk.Align.CENTER;
            boton = new Gtk.Button ();
            boton.get_style_context ().add_class ("tienda-get");
            boton.clicked.connect (al_pulsar);
            add_named (boton, "boton");

            anillo = new Gtk.DrawingArea ();
            anillo.set_size_request (28, 28);
            anillo.add_events (Gdk.EventMask.BUTTON_RELEASE_MASK);
            anillo.draw.connect (dibujar);
            anillo.button_release_event.connect (() => { cancelar (); return true; });
            anillo.tooltip_text = "Stop";
            add_named (anillo, "progreso");

            var m = Motor.instancia;
            h_progreso = m.progreso.connect ((t, p, etapa) => {
                if (t != trabajo && !(trabajo == null && m.trabajo_a_id.lookup (t) == r.id)) return;
                trabajo = t;
                pct = p;
                mostrar_progreso ();
            });
            h_terminado = m.terminado.connect (al_terminar);
            destroy.connect (() => {
                m.disconnect (h_progreso);
                m.disconnect (h_terminado);
                if (reloj != 0) Source.remove (reloj);
            });

            trabajo = m.id_a_trabajo.lookup (r.id);
            if (trabajo != null) {
                pct = m.trabajo_a_pct.lookup (trabajo);
                mostrar_progreso ();
            } else {
                reposo ();
            }
            show_all ();
            visible_child_name = trabajo != null ? "progreso" : "boton";
        }

        void reposo () {
            trabajo = null;
            if (r.actualizable) boton.label = "Update";
            else if (r.instalada) boton.label = "Open";
            else boton.label = "Get";
            visible_child_name = "boton";
            if (reloj != 0) { Source.remove (reloj); reloj = 0; }
        }

        void mostrar_progreso () {
            visible_child_name = "progreso";
            anillo.queue_draw ();
            if (pct > 100 && reloj == 0) {
                reloj = Timeout.add (60, () => {
                    giro += 0.35;
                    anillo.queue_draw ();
                    return true;
                });
            } else if (pct <= 100 && reloj != 0) {
                Source.remove (reloj);
                reloj = 0;
            }
        }

        void al_pulsar () {
            if (r.actualizable) {
                Motor.instancia.actualizar.begin ("apps", { r.id }, (o, res) => {
                    try { Motor.instancia.actualizar.end (res); } catch (Error e) { warning ("%s", e.message); }
                });
            } else if (r.instalada) {
                abrir_app (r);
            } else {
                Motor.instancia.instalar.begin (r.id, (o, res) => {
                    try { Motor.instancia.instalar.end (res); } catch (Error e) { warning ("%s", e.message); reposo (); }
                });
            }
        }

        void cancelar () {
            if (trabajo == null) return;
            Motor.instancia.cancelar.begin (trabajo, (o, res) => {
                try { Motor.instancia.cancelar.end (res); } catch (Error e) { warning ("%s", e.message); }
            });
        }

        void al_terminar (string t, string id, string tipo, bool ok, string codigo, string mensaje) {
            if (t != trabajo && id != r.id) return;
            if (ok) {
                if (tipo == "instalar") { r.instalada = true; }
                else if (tipo == "quitar") { r.instalada = false; r.actualizable = false; }
                else if (tipo == "actualizar") { r.actualizable = false; }
            }
            reposo ();
            cambio ();
        }

        bool dibujar (Cairo.Context cr) {
            double w = anillo.get_allocated_width ();
            double h = anillo.get_allocated_height ();
            double cx = w / 2, cy = h / 2, rad = double.min (w, h) / 2 - 2;
            cr.set_line_width (3);
            cr.set_source_rgba (0.5, 0.5, 0.55, 0.3);
            cr.arc (cx, cy, rad, 0, 2 * Math.PI);
            cr.stroke ();
            cr.set_source_rgb (0.04, 0.38, 1.0);
            if (pct <= 100) {
                cr.arc (cx, cy, rad, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * pct / 100.0);
            } else {
                cr.arc (cx, cy, rad, giro, giro + Math.PI / 2);
            }
            cr.stroke ();
            cr.rectangle (cx - 4, cy - 4, 8, 8);
            cr.fill ();
            return true;
        }
    }

    /** Abre la app: por su .desktop si hay, y si no (Flatpak) con `flatpak run`. */
    public void abrir_app (Resumen r) {
        string[] candidatos = { r.appstream_id + ".desktop", r.appstream_id };
        foreach (var c in candidatos) {
            var info = new DesktopAppInfo (c);
            if (info != null) {
                try {
                    info.launch (null, null);
                    return;
                } catch (Error e) {
                    warning ("%s", e.message);
                }
            }
        }
        if (r.origen == "flatpak") {
            try {
                Process.spawn_command_line_async ("flatpak run %s".printf (Shell.quote (r.appstream_id)));
            } catch (SpawnError e) {
                warning ("%s", e.message);
            }
        }
    }

    /** Una captura de la ficha: se baja con GIO (http/https por GVfs) y se escala a la altura pedida. */
    public class CapturaImagen : Gtk.Box {
        Gtk.Image imagen = new Gtk.Image ();
        Gtk.Spinner girando = new Gtk.Spinner ();

        public CapturaImagen (string url, int alto) {
            set_size_request (-1, alto);
            pack_start (girando, true, true, 0);
            girando.start ();
            pack_start (imagen, true, true, 0);
            bajar.begin (url, alto);
            show_all ();
        }

        async void bajar (string url, int alto) {
            try {
                var f = File.new_for_uri (url);
                uint8[] datos;
                yield f.load_contents_async (null, out datos, null);
                var flujo = new MemoryInputStream.from_data (datos);
                var pb = yield new Gdk.Pixbuf.from_stream_async (flujo, null);
                int ancho = (int) ((double) pb.width * alto / pb.height);
                imagen.set_from_pixbuf (pb.scale_simple (ancho, alto, Gdk.InterpType.BILINEAR));
            } catch (Error e) {
                // sin red o sin la imagen: queda el hueco, sin inventar otra
            }
            girando.stop ();
            girando.hide ();
        }
    }

    public Gtk.Label etiqueta (string texto, string clase, bool envolver = false) {
        var l = new Gtk.Label (texto);
        l.halign = Gtk.Align.START;
        l.xalign = 0;
        l.ellipsize = envolver ? Pango.EllipsizeMode.NONE : Pango.EllipsizeMode.END;
        l.wrap = envolver;
        l.get_style_context ().add_class (clase);
        return l;
    }

    /** Una fila de lista: [número] ícono, nombre y resumen, y el botón. Un clic fuera del botón abre la ficha. */
    public Gtk.Widget fila_app (Resumen r, int numero = 0) {
        var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
        caja.margin = 6;
        if (numero > 0) {
            var n = etiqueta ("%d".printf (numero), "tienda-numero");
            n.width_chars = 2;
            caja.pack_start (n, false, false, 0);
        }
        caja.pack_start (new IconoApp (r, 48), false, false, 0);
        var textos = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
        textos.valign = Gtk.Align.CENTER;
        textos.pack_start (etiqueta (r.nombre, "tienda-fila-nombre"), false, false, 0);
        if (r.resumen != "") textos.pack_start (etiqueta (r.resumen, "tienda-fila-resumen"), false, false, 0);
        caja.pack_start (textos, true, true, 0);
        caja.pack_end (new BotonGet (r), false, false, 0);
        var ev = new Gtk.EventBox ();
        ev.add (caja);
        ev.button_release_event.connect ((e) => {
            if (e.button == 1) Motor.instancia.abrir_ficha (r.id);
            return false;
        });
        ev.get_style_context ().add_class ("tienda-fila");
        return ev;
    }
}
