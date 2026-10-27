/*
 * Energy Saver: el panel de Catalina para una Mac de escritorio (Screen Shot 2026-10-14 at 1.24.31 PM); port de settings/energia.py.
 *
 * Conectado de verdad: Computer sleep (sleep-inactive-ac-timeout + tipo suspend) y Display sleep (sleep-display-ac) de
 * org.cinnamon.settings-daemon.plugins.power. Restore Defaults vuelve a «Never» y 15 minutos. Sin equivalente aquí (en gris): Put
 * hard disks to sleep, Wake for network access, Start up automatically after a power failure, Enable Power Nap y Schedule….
 *
 * La escala de los sliders: Catalina rotula 1 min, 15 min, 1 hr, 3 hrs y Never; los pasos intermedios (de 5 en 5 minutos hasta la
 * hora y de 15 en 15 hasta las 3 horas) los puse siguiendo esas posiciones.
 */
namespace Preferencias {

    public class PanelEnergySaver : Panel {
        const string POWER = "org.cinnamon.settings-daemon.plugins.power";
        // Minutos de cada paso del slider; el último es «Never» (0 en gsettings).
        const int[] PASOS = { 1, 3, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90, 105, 120, 135, 150, 165, 180, 0 };
        const int PANTALLA_POR_DEFECTO = 4;      // 15 min (el equipo por defecto es Never)

        // MINT_ENERGIA_PRUEBA: no escribe en gsettings.
        bool prueba = Environment.get_variable ("MINT_ENERGIA_PRUEBA") != null;
        Settings? cfg = null;
        bool cargando = false;
        Gtk.Scale? s_computadora = null;
        Gtk.Scale? s_pantalla = null;

        public PanelEnergySaver () {
            id = "com.apple.preference.energysaver";
            nombre = "Energy Saver";
            palabras = "energy saver, computer sleep, display sleep, power, suspend, power nap, wake, schedule";
        }

        static string? rotulo_de (int i) {
            switch (i) {
            case 0: return "1 min";
            case 4: return "15 min";
            case 13: return "1 hr";
            case 21: return "3 hrs";
            case 23: return "Never";      // 22 y 23 son «Never»
            }
            return null;
        }

        /** El paso más cercano a los segundos de gsettings (0 es «Never»). */
        static int paso_de (int segundos) {
            if (segundos <= 0) {
                return PASOS.length;
            }
            double minutos = segundos / 60.0;
            int mejor = 0;
            double dist = double.MAX;
            for (int i = 0; i < PASOS.length - 1; i++) {
                double d = Math.fabs (PASOS[i] - minutos);
                if (d < dist) {
                    dist = d;
                    mejor = i;
                }
            }
            return mejor;
        }

        static Gtk.Widget gris_energia (Gtk.Widget w) {
            w.set_sensitive (false);
            w.set_tooltip_text ("Not available on this computer.");
            return w;
        }

        public override Gtk.Widget? construir () {
            cfg = abrir_settings (POWER);
            if (es_monterey ()) {
                return construir_monterey ();
            }
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 16, 16, 24, 24);

            var marco = new Gtk.Frame (null);
            marco.get_style_context ().add_class ("mp-sd-lista");
            var g = new Gtk.Grid ();
            g.column_spacing = 14;
            g.row_spacing = 14;
            margenes (g, 18, 18, 18, 18);
            marco.add (g);
            string[] titulos = { "Computer sleep:", "Display sleep:" };
            for (int fila = 0; fila < 2; fila++) {
                g.attach (etiqueta_fila (titulos[fila]), 0, fila, 1, 1);
                var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, PASOS.length, 1);
                esc.draw_value = false;
                esc.round_digits = 0;
                esc.set_size_request (500, -1);
                for (int i = 0; i <= PASOS.length; i++) {
                    esc.add_mark (i, Gtk.PositionType.BOTTOM, rotulo_de (i));
                }
                bool computadora = fila == 0;
                esc.value_changed.connect (() => cambio (computadora, (int) Math.rint (esc.get_value ())));
                if (computadora) {
                    s_computadora = esc;
                } else {
                    s_pantalla = esc;
                }
                g.attach (esc, 1, fila, 1, 1);
            }
            leer ();

            int fila = 2;
            string[] textos = { "Put hard disks to sleep when possible", "Wake for network access",
                                "Start up automatically after a power failure" };
            bool[] activas = { false, true, true };
            for (int i = 0; i < 3; i++) {
                var c = new Gtk.CheckButton.with_label (textos[i]);
                c.active = activas[i];
                g.attach (gris_energia (c), 1, fila, 1, 1);
                fila++;
            }
            var nap = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            nap.pack_start (new Gtk.CheckButton.with_label ("Enable Power Nap"), false, false, 0);
            var d = new Gtk.Label ("While sleeping, your Mac can back up using Time Machine and periodically check for new email, calendar, and other iCloud updates");
            d.xalign = 0;
            d.set_line_wrap (true);
            d.set_max_width_chars (60);
            d.get_style_context ().add_class ("mp-sd-detalle");
            d.margin_start = 24;
            nap.pack_start (d, false, false, 0);
            g.attach (gris_energia (nap), 1, fila, 1, 1);
            fila++;
            var restaurar = new Gtk.Button.with_label ("Restore Defaults");
            restaurar.halign = Gtk.Align.END;
            restaurar.clicked.connect (() => restaurar_valores ());
            g.attach (restaurar, 1, fila, 1, 1);
            caja.pack_start (marco, false, false, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            pie.pack_end (gris_energia (new Gtk.Button.with_label ("Schedule…")), false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            cargando = false;
            return caja;
        }

        // ── Monterey (capturas 08-pref-...EnergySaverPrefPane--currentSource y --schedule): barra lateral Power / Schedule; Power = un solo
        //    deslizador «Turn display off after:» y cuatro casillas; Schedule, tal cual pero en gris (no hay programación de encendido aquí) ──
        Gtk.CheckButton? previene = null;

        Gtk.Widget construir_monterey () {
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            var lateral = new Gtk.ListBox ();
            lateral.selection_mode = Gtk.SelectionMode.SINGLE;
            lateral.set_size_request (150, -1);
            var pila = new Gtk.Stack ();

            // Power
            var power = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            margenes (power, 18, 18, 22, 22);
            var tit = new Gtk.Label ("Turn display off after:");
            tit.xalign = 0;
            power.pack_start (tit, false, false, 0);
            var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, PASOS.length, 1);
            esc.draw_value = false;
            esc.round_digits = 0;
            esc.set_size_request (430, -1);
            for (int i = 0; i <= PASOS.length; i++) {
                esc.add_mark (i, Gtk.PositionType.BOTTOM, rotulo_de (i));
            }
            esc.value_changed.connect (() => cambio (false, (int) Math.rint (esc.get_value ())));
            s_pantalla = esc;
            power.pack_start (esc, false, false, 8);
            // «Prevent your Mac from automatically sleeping when the display is off»: marcada = el equipo no se suspende nunca; desmarcada = se
            // suspende cuando se apaga la pantalla (el tiempo de la pantalla)
            previene = new Gtk.CheckButton.with_label ("Prevent your Mac from automatically sleeping when the display is off");
            previene.toggled.connect (() => {
                if (cargando || prueba || cfg == null) {
                    return;
                }
                cfg.set_int ("sleep-inactive-ac-timeout", previene.active ? 0 : int.max (60, cfg.get_int ("sleep-display-ac")));
                if (!previene.active) {
                    cfg.set_string ("sleep-inactive-ac-type", "suspend");
                }
            });
            power.pack_start (previene, false, false, 0);
            string[] textos = { "Wake for network access", "Start up automatically after a power failure", "Enable Power Nap" };
            foreach (var t in textos) {
                var c = new Gtk.CheckButton.with_label (t);
                c.active = true;
                power.pack_start (gris_energia (c), false, false, 0);
                if (t == "Enable Power Nap") {
                    var d = new Gtk.Label ("While sleeping, your Mac can back up using Time Machine and periodically check for new email, calendar, and other iCloud updates.");
                    d.xalign = 0;
                    d.set_line_wrap (true);
                    d.set_max_width_chars (60);
                    d.get_style_context ().add_class ("mp-sd-detalle");
                    d.margin_start = 24;
                    power.pack_start (d, false, false, 0);
                }
            }
            var restaurar = new Gtk.Button.with_label ("Restore Defaults");
            restaurar.halign = Gtk.Align.END;
            restaurar.valign = Gtk.Align.END;
            restaurar.clicked.connect (() => restaurar_valores ());
            power.pack_end (restaurar, false, false, 0);
            pila.add_named (power, "power");

            // Schedule: la programación de encendido y apagado no existe aquí; se dibuja en gris como la captura
            var horario = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            margenes (horario, 18, 18, 22, 22);
            var ayuda = new Gtk.Label ("Schedule specific times for your Mac to start up, shut down, sleep, or wake from sleep.");
            ayuda.xalign = 0;
            ayuda.set_line_wrap (true);
            ayuda.set_max_width_chars (60);
            horario.pack_start (ayuda, false, false, 0);
            for (int i = 0; i < 2; i++) {
                var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                f.pack_start (new Gtk.CheckButton.with_label (i == 0 ? "Start up or wake" : "Sleep"), false, false, 0);
                var dia = new Gtk.ComboBoxText ();
                dia.append ("d", "Every Day");
                dia.set_active (0);
                f.pack_start (dia, false, false, 0);
                f.pack_start (new Gtk.Label ("at"), false, false, 0);
                f.pack_start (new Gtk.Entry.with_buffer (new Gtk.EntryBuffer ("12:00 AM".data)), false, false, 0);
                horario.pack_start (gris_energia (f), false, false, 0);
            }
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            pie.pack_end (gris_energia (new Gtk.Button.with_label ("Apply")), false, false, 0);
            pie.pack_end (gris_energia (new Gtk.Button.with_label ("Restore Previous Settings")), false, false, 0);
            horario.pack_end (pie, false, false, 0);
            pila.add_named (horario, "schedule");

            foreach (var n in new string[] { "power", "schedule" }) {
                var fila = new Gtk.ListBoxRow ();
                fila.name = n;
                var l = new Gtk.Label (n == "power" ? "Power" : "Schedule");
                l.xalign = 0;
                l.margin = 8;
                fila.add (l);
                lateral.add (fila);
            }
            lateral.row_selected.connect ((r) => {
                if (r != null) {
                    pila.set_visible_child_name (r.name);
                }
            });
            caja.pack_start (lateral, false, false, 0);
            caja.pack_start (pila, true, true, 0);
            leer ();
            caja.show_all ();
            lateral.select_row (lateral.get_row_at_index (0));
            cargando = false;
            return caja;
        }

        void leer () {
            bool previo = cargando;
            cargando = true;
            if (cfg != null) {
                if (s_computadora != null) {
                    s_computadora.set_value (paso_de (cfg.get_int ("sleep-inactive-ac-timeout")));
                }
                s_pantalla.set_value (paso_de (cfg.get_int ("sleep-display-ac")));
                if (previene != null) {
                    previene.active = cfg.get_int ("sleep-inactive-ac-timeout") == 0;
                }
            }
            cargando = previo;
        }

        void cambio (bool computadora, int indice) {
            if (cargando || prueba || cfg == null) {
                return;
            }
            int segundos = PASOS[int.min (indice, PASOS.length - 1)] * 60;
            if (computadora) {
                cfg.set_int ("sleep-inactive-ac-timeout", segundos);
                if (segundos != 0) {
                    cfg.set_string ("sleep-inactive-ac-type", "suspend");
                }
            } else {
                cfg.set_int ("sleep-display-ac", segundos);
            }
        }

        void restaurar_valores () {
            if (prueba || cfg == null) {
                return;
            }
            cfg.set_int ("sleep-inactive-ac-timeout", 0);
            cfg.set_int ("sleep-display-ac", PASOS[PANTALLA_POR_DEFECTO] * 60);
            leer ();
        }
    }
}
