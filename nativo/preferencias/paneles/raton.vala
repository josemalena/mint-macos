/*
 * Mouse y Trackpad: los dos paneles de Catalina (port de settings/raton.py).
 *
 * Mouse (Screen Shot 2026-10-14 at 1.24.21 PM): Scroll direction: Natural, Tracking speed, Scrolling speed, Double-Click speed,
 * Primary mouse button y Set Up Bluetooth Mouse…. Escriben en org.cinnamon.desktop.peripherals.mouse. Scrolling speed no tiene
 * equivalente en libinput: se dibuja en gris, como en una Mac sin esa función.
 *
 * Trackpad (1.24.14 PM): la Mac mini no trae trackpad y Catalina enseña «No trackpad found» con la búsqueda de uno por Bluetooth.
 * Eso es lo que sale aquí mientras no haya un touchpad; con uno conectado el panel lo sirve el módulo de Cinnamon (el System
 * Preferences de Python), porque no tenemos la captura de Catalina con trackpad (hay que pedírsela a José).
 */
namespace Preferencias {

    /** ¿Hay un touchpad o trackpad conectado? (los dispositivos de entrada que lista el kernel). */
    public bool hay_touchpad () {
        try {
            string texto;
            FileUtils.get_contents ("/proc/bus/input/devices", out texto);
            foreach (var l in texto.split ("\n")) {
                if (l.has_prefix ("N:")) {
                    var m = l.down ();
                    if (m.contains ("touchpad") || m.contains ("trackpad")) {
                        return true;
                    }
                }
            }
        } catch (Error e) {
        }
        return false;
    }

    public class PanelMouse : Panel {
        const string MOUSE = "org.cinnamon.desktop.peripherals.mouse";
        // Catalina pone diez marcas en Tracking y en Double-Click speed. Tracking va de -1 a 1 en libinput; Double-Click de lento
        // (900 ms) a rápido (250 ms).
        const int PASOS = 10;
        // MINT_RATON_PRUEBA: no escribe en gsettings.
        bool prueba = Environment.get_variable ("MINT_RATON_PRUEBA") != null;
        bool cargando = false;

        public PanelMouse () {
            id = "com.apple.preference.mouse";
            nombre = "Mouse";
            palabras = "mouse, pointer, tracking speed, scrolling, double-click, primary button, natural scroll, left handed";
        }

        static double velocidad (int i) {
            return -1.0 + 2.0 * i / (PASOS - 1);
        }

        static int doble_clic (int i) {
            return (int) (900 - i * (650.0 / (PASOS - 1)));
        }

        static int mas_cercano_vel (double v) {
            int mejor = 0;
            double dist = double.MAX;
            for (int i = 0; i < PASOS; i++) {
                double d = Math.fabs (velocidad (i) - v);
                if (d < dist) {
                    dist = d;
                    mejor = i;
                }
            }
            return mejor;
        }

        static int mas_cercano_dc (int v) {
            int mejor = 0;
            double dist = double.MAX;
            for (int i = 0; i < PASOS; i++) {
                double d = Math.fabs ((double) (doble_clic (i) - v));
                if (d < dist) {
                    dist = d;
                    mejor = i;
                }
            }
            return mejor;
        }

        static Gtk.Scale deslizador (int indice, string pie_izq, string pie_der, owned EscalaCambio al_cambiar) {
            var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, PASOS - 1, 1);
            esc.draw_value = false;
            esc.round_digits = 0;
            esc.set_value (indice);
            esc.set_size_request (150, -1);
            for (int i = 0; i < PASOS; i++) {
                esc.add_mark (i, Gtk.PositionType.BOTTOM, null);
            }
            esc.add_mark (0, Gtk.PositionType.BOTTOM, pie_izq);
            esc.add_mark (PASOS - 1, Gtk.PositionType.BOTTOM, pie_der);
            esc.value_changed.connect (() => al_cambiar ((int) Math.round (esc.get_value ())));
            return esc;
        }

        static void abrir_bluetooth () {
            foreach (var prog in new string[] { "blueman-manager", "blueberry" }) {
                if (Environment.find_program_in_path (prog) == null) {
                    continue;
                }
                try {
                    Process.spawn_async (null, { prog }, null,
                                         SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                         () => { Posix.setsid (); }, null);
                    return;
                } catch (Error e) {
                }
            }
        }

        public override Gtk.Widget? construir () {
            var cfg = abrir_settings (MOUSE);
            if (cfg == null) {
                var l = new Gtk.Label ("The mouse settings are not available.");
                l.show ();
                return l;
            }
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 22, 16, 24, 24);

            var natural = new Gtk.CheckButton.with_label ("Scroll direction: Natural");
            natural.active = cfg.get_boolean ("natural-scroll");
            natural.toggled.connect (() => { if (!cargando && !prueba) cfg.set_boolean ("natural-scroll", natural.active); });
            natural.halign = Gtk.Align.CENTER;
            caja.pack_start (natural, false, false, 0);

            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            cuerpo.halign = Gtk.Align.CENTER;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 22);
            izq.margin_end = 30;

            var c1 = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            c1.pack_start (new Gtk.Label ("Tracking speed"), false, false, 0);
            c1.pack_start (deslizador (mas_cercano_vel (cfg.get_double ("speed")), "Slow", "Fast",
                                       (i) => { if (!cargando && !prueba) cfg.set_double ("speed", velocidad (i)); }), false, false, 0);
            izq.pack_start (c1, false, false, 0);
            var c2 = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            c2.pack_start (new Gtk.Label ("Scrolling speed"), false, false, 0);
            var scroll = deslizador (4, "Slow", "Fast", (i) => { });
            scroll.set_sensitive (false);
            scroll.set_tooltip_text ("Scrolling speed is not available on this computer.");
            c2.pack_start (scroll, false, false, 0);
            izq.pack_start (c2, false, false, 0);
            cuerpo.pack_start (izq, false, false, 0);
            cuerpo.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 22);
            der.margin_start = 30;
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            c.pack_start (new Gtk.Label ("Double-Click speed"), false, false, 0);
            c.pack_start (deslizador (mas_cercano_dc (cfg.get_int ("double-click")), "Slow", "Fast",
                                      (i) => { if (!cargando && !prueba) cfg.set_int ("double-click", doble_clic (i)); }), false, false, 0);
            der.pack_start (c, false, false, 0);
            var b = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var primario = new Gtk.Label ("Primary mouse button:");
            primario.xalign = 0;
            b.pack_start (primario, false, false, 0);
            var izquierdo = new Gtk.RadioButton.with_label_from_widget (null, "Left");
            var derecho = new Gtk.RadioButton.with_label_from_widget (izquierdo, "Right");
            if (cfg.get_boolean ("left-handed")) {
                derecho.active = true;
            } else {
                izquierdo.active = true;
            }
            derecho.toggled.connect (() => { if (!cargando && !prueba) cfg.set_boolean ("left-handed", derecho.active); });
            b.pack_start (izquierdo, false, false, 0);
            b.pack_start (derecho, false, false, 0);
            der.pack_start (b, false, false, 0);
            cuerpo.pack_start (der, false, false, 0);
            caja.pack_start (cuerpo, false, false, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var bt = new Gtk.Button.with_label ("Set Up Bluetooth Mouse…");
            bt.clicked.connect (() => abrir_bluetooth ());
            pie.pack_end (bt, false, false, 0);
            caja.pack_end (pie, false, false, 0);
            caja.set_size_request (-1, 300);        // el botón de Bluetooth queda abajo a la derecha, como en Catalina
            caja.show_all ();
            cargando = false;
            return caja;
        }
    }

    public class PanelTrackpad : Panel {
        public PanelTrackpad () {
            id = "com.apple.preference.trackpad";
            nombre = "Trackpad";
            palabras = "trackpad, touchpad, bluetooth trackpad, tap, scroll, gestures";
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 26);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 26, 20, 26, 26);
            caja.pack_start (imagen_icono_panel (id, 96), false, false, 0);
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            var t = new Gtk.Label ("Wait for a Bluetooth trackpad to be discovered.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.get_style_context ().add_class ("mp-titulo-negrita");
            der.pack_start (t, false, false, 0);
            var s = new Gtk.Label ("If your Bluetooth trackpad doesn’t appear, make sure it is turned on.");
            s.xalign = 0;
            s.set_line_wrap (true);
            s.set_max_width_chars (44);
            der.pack_start (s, false, false, 0);
            var n = new Gtk.Label ("No trackpad found");
            n.get_style_context ().add_class ("mp-titulo-negrita");
            n.margin_top = 30;
            n.margin_bottom = 30;
            der.pack_start (n, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var giro = new Gtk.Spinner ();
            giro.start ();
            pie.pack_start (giro, false, false, 0);
            pie.pack_start (new Gtk.Label ("Searching…"), false, false, 0);
            pie.pack_end (gris (new Gtk.Button.with_label ("Continue")), false, false, 0);
            der.pack_start (pie, false, false, 0);
            caja.pack_start (der, true, true, 0);
            caja.show_all ();
            return caja;
        }
    }
}
