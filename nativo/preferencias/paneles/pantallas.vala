/*
 * Displays: el panel de Catalina con sus tres pestañas (Display, Color, Night Shift); port de settings/pantallas.py.
 *
 * Capturas: Screen Shot 2026-10-14 at 1.18.18 PM (Display), 1.18.21 PM (Color), 1.18.36 PM (Night Shift).
 *
 * Display: Rotation y Refresh Rate se aplican por el DisplayConfig de Cinnamon (org.cinnamon.Muffin.DisplayConfig, el mismo que usa
 * cinnamon-settings; ver pantallas-datos.vala) en dos tiempos, como en cualquier cambio de pantalla que puede dejarla en negro:
 * primero temporal, y si no se confirma en 15 segundos vuelve a lo anterior. «Scaled» se dibuja en gris: Catalina enseña ahí una lista
 * de resoluciones que aún no tenemos capturada. Color: los perfiles de colord (colormgr). Night Shift:
 * org.cinnamon.settings-daemon.plugins.color. Sin equivalente (en gris): AirPlay Display, «Show mirroring options», Open Profile,
 * Delete Profile y Calibrate…, y «Turn On Until Tomorrow».
 */
namespace Preferencias {

    public class PanelDisplays : Panel {
        // MINT_PANTALLAS_PRUEBA: no aplica cambios de pantalla ni escribe nada.
        bool prueba = Environment.get_variable ("MINT_PANTALLAS_PRUEBA") != null;
        bool cargando = false;
        EstadoPantallas? estado = null;
        MonitorFisico? monitor = null;
        MonitorLogico? logico = null;
        Gtk.ComboBoxText giro;
        Gtk.ComboBoxText frecuencia;
        Settings? noche = null;

        public PanelDisplays () {
            id = "com.apple.preference.displays";
            nombre = "Displays";
            palabras = "displays, display, resolution, rotation, refresh rate, night shift, color, profile, monitor, temperature";
        }

        static Gtk.Widget gris_pant (Gtk.Widget w, string? motivo = null) {
            w.set_sensitive (false);
            if (motivo != null) {
                w.set_tooltip_text (motivo);
            }
            return w;
        }

        // ── la página ────────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 12;
            var stack = new Gtk.Stack ();
            stack.add_titled (pagina_pantalla (), "display", "Display");
            stack.add_titled (pagina_color (), "color", "Color");
            stack.add_titled (pagina_noche (), "night", "Night Shift");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);

            var pie = new Gtk.Grid ();
            pie.column_spacing = 10;
            pie.row_spacing = 8;
            pie.margin_top = 6;
            pie.attach (etiqueta_fila ("AirPlay Display:"), 0, 0, 1, 1);
            var air = new Gtk.ComboBoxText ();
            air.append ("off", "Off");
            air.set_active (0);
            pie.attach (gris_pant (air, "AirPlay displays are not available on this computer."), 1, 0, 1, 1);
            var espejo = new Gtk.CheckButton.with_label ("Show mirroring options in the menu bar when available");
            espejo.active = true;
            pie.attach (gris (espejo), 0, 1, 2, 1);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_PANTALLAS_PESTANA");      // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            cargando = false;
            return caja;
        }

        // ── Display ──────────────────────────────────────────────────────
        Gtk.Widget pagina_pantalla () {
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            margenes (pagina, 24, 24, 24, 24);
            var vista = new Gtk.DrawingArea ();
            vista.set_size_request (210, 130);
            vista.draw.connect ((cr) => {
                double ancho = 210, alto = 118;
                var g = new Cairo.Pattern.linear (0, 0, ancho, alto);
                g.add_color_stop_rgb (0, 0.07, 0.07, 0.07);
                g.add_color_stop_rgb (0.5, 0.17, 0.17, 0.17);
                g.add_color_stop_rgb (1, 0.1, 0.1, 0.1);
                cr.set_source (g);
                cr.rectangle (0, 0, ancho, alto);
                cr.fill ();
                cr.set_source_rgb (0.75, 0.75, 0.75);
                cr.rectangle (ancho / 2 - 30, alto, 60, 5);
                cr.fill ();
                return false;
            });
            pagina.pack_start (vista, false, false, 0);

            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 10;
            estado = estado_actual ();
            monitor = null;
            logico = null;
            if (estado != null) {
                estado.monitor_actual (out monitor, out logico);
            }

            g.attach (etiqueta_fila ("Resolution:"), 0, 0, 1, 1);
            var res = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var por_defecto = new Gtk.RadioButton.with_label_from_widget (null, "Default for display");
            var escalada = new Gtk.RadioButton.with_label_from_widget (por_defecto, "Scaled");
            por_defecto.active = true;
            gris_pant (escalada, "The list of scaled resolutions is not available yet.");
            res.pack_start (por_defecto, false, false, 0);
            res.pack_start (escalada, false, false, 0);
            g.attach (res, 1, 0, 1, 1);

            g.attach (etiqueta_fila ("Rotation:"), 0, 1, 1, 1);
            giro = new Gtk.ComboBoxText ();
            string[] giros = { "Standard", "90°", "180°", "270°" };
            for (int i = 0; i < 4; i++) {
                giro.append (i.to_string (), giros[i]);
            }
            giro.set_active_id (logico != null ? ((int) logico.giro).to_string () : "0");
            g.attach (giro, 1, 1, 1, 1);

            g.attach (etiqueta_fila ("Refresh Rate:"), 0, 2, 1, 1);
            frecuencia = new Gtk.ComboBoxText ();
            var actual = monitor != null ? monitor.modo_actual () : null;
            if (actual != null) {
                foreach (var modo in monitor.modos) {
                    if (modo.ancho == actual.ancho && modo.alto == actual.alto && !modo.entrelazado) {
                        frecuencia.append (modo.ident, "%.2f Hertz".printf (modo.hertz));
                    }
                }
                frecuencia.set_active_id (actual.ident);
            }
            g.attach (frecuencia, 1, 2, 1, 1);
            if (monitor == null) {
                gris_pant (giro, "Cinnamon did not report any display.");
                gris_pant (frecuencia, "Cinnamon did not report any display.");
            }
            giro.changed.connect (() => cambiar ());
            frecuencia.changed.connect (() => cambiar ());
            pagina.pack_start (g, false, false, 0);
            return pagina;
        }

        /** Aplica el giro y la frecuencia elegidos, con vuelta atrás si no se confirma. */
        void cambiar () {
            if (cargando || estado == null || logico == null || monitor == null) {
                return;
            }
            var conector = monitor.conector;
            var antes = estado.configuracion ();
            var nuevo = estado.configuracion (conector, int.parse (giro.get_active_id () ?? "0"), frecuencia.get_active_id ());
            if (prueba) {
                stderr.printf ("[prueba] aplicaría %s\n", nuevo.print (false));
                return;
            }
            try {
                aplicar_pantallas (estado.serie, nuevo, 1);               // temporal
            } catch (Error e) {
                aviso ("Could not change the display: %s".printf (e.message));
                refrescar ();
                return;
            }
            if (confirmar ()) {
                var ahora = estado_actual ();
                if (ahora != null) {
                    try {
                        aplicar_pantallas (ahora.serie, nuevo, 2);          // persistente
                    } catch (Error e) {
                    }
                }
            } else {
                var ahora = estado_actual ();
                if (ahora != null) {
                    try {
                        aplicar_pantallas (ahora.serie, antes, 1);          // vuelta a lo de antes
                    } catch (Error e) {
                    }
                }
            }
            refrescar ();
        }

        void refrescar () {
            estado = estado_actual ();
            if (estado != null) {
                estado.monitor_actual (out monitor, out logico);
            }
            cargando = true;
            if (logico != null) {
                giro.set_active_id (((int) logico.giro).to_string ());
            }
            var actual = monitor != null ? monitor.modo_actual () : null;
            if (actual != null) {
                frecuencia.set_active_id (actual.ident);
            }
            cargando = false;
        }

        /** ¿Se queda este cambio? Sin respuesta en 15 s se devuelve lo anterior. */
        bool confirmar () {
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s",
                                           "Do you want to keep these display settings?");
            d.add_button ("Revert", Gtk.ResponseType.CANCEL);
            d.add_button ("Keep", Gtk.ResponseType.OK);
            d.set_default_response (Gtk.ResponseType.CANCEL);
            int resto = 15;
            d.format_secondary_text ("Reverting in 15 seconds.");
            uint t = Timeout.add_seconds (1, () => {
                resto--;
                d.format_secondary_text ("Reverting in %d seconds.", resto);
                if (resto <= 0) {
                    d.response (Gtk.ResponseType.CANCEL);
                    return false;
                }
                return true;
            });
            var r = d.run ();
            if (resto > 0) {
                Source.remove (t);
            }
            d.destroy ();
            return r == Gtk.ResponseType.OK;
        }

        void aviso (string texto) {
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.OK, "%s", texto);
            d.run ();
            d.destroy ();
        }

        // ── Color ────────────────────────────────────────────────────────
        static string colormgr (string[] args) {
            string[] cmd = { "colormgr" };
            foreach (var a in args) {
                cmd += a;
            }
            try {
                var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                return p.get_successful () ? (salida ?? "") : "";
            } catch (Error e) {
                return "";
            }
        }

        class Perfil {
            public string titulo;
            public string ruta;
        }

        Gtk.Widget pagina_color () {
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            margenes (pagina, 18, 18, 24, 24);
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var dp = new Gtk.Label ("Display profile:");
            dp.xalign = 0;
            izq.pack_start (dp, false, false, 0);
            var lista = new Gtk.ListStore (2, typeof (string), typeof (string));
            var perfiles = new GenericArray<Perfil> ();
            try {
                var re_ruta = new Regex ("^Object Path:\\s+(\\S+)", RegexCompileFlags.MULTILINE);
                var re_titulo = new Regex ("^Title:\\s+(.+)$", RegexCompileFlags.MULTILINE);
                foreach (var bloque in colormgr ({ "get-profiles" }).split ("\n\n")) {
                    MatchInfo mr, mt;
                    bool hay_ruta = re_ruta.match (bloque, 0, out mr);
                    bool hay_titulo = re_titulo.match (bloque, 0, out mt);
                    if (hay_ruta && hay_titulo) {
                        var p = new Perfil ();
                        p.titulo = mt.fetch (1).strip ();
                        p.ruta = mr.fetch (1);
                        perfiles.add (p);
                    }
                }
            } catch (Error e) {
            }
            perfiles.sort ((a, b) => strcmp (a.titulo.down (), b.titulo.down ()));
            for (int i = 0; i < perfiles.length; i++) {
                Gtk.TreeIter it;
                lista.append (out it);
                lista.set (it, 0, perfiles[i].titulo, 1, perfiles[i].ruta, -1);
            }
            var arbol = new Gtk.TreeView.with_model (lista);
            arbol.headers_visible = false;
            arbol.append_column (new Gtk.TreeViewColumn.with_attributes ("", new Gtk.CellRendererText (), "text", 0, null));
            var pant = new Gtk.ScrolledWindow (null, null);
            pant.set_size_request (300, 220);
            pant.add (arbol);
            var marco = marco_lista ();
            marco.add (pant);
            izq.pack_start (marco, true, true, 0);
            var solo = new Gtk.CheckButton.with_label ("Show profiles for this display only");
            gris_pant (solo, "All the installed profiles are shown.");
            izq.pack_start (solo, false, false, 0);
            pagina.pack_start (izq, false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            der.margin_top = 26;
            foreach (var texto in new string[] { "Open Profile", "Delete Profile", "Calibrate…" }) {
                der.pack_start (gris_pant (new Gtk.Button.with_label (texto), "Not available on this computer."), false, false, 0);
            }
            pagina.pack_start (der, false, false, 0);
            // Elegir un perfil lo hace el predeterminado de la pantalla (colormgr).
            var dispositivo = dispositivo_color ();
            arbol.get_selection ().changed.connect (() => perfil_elegido (arbol.get_selection (), dispositivo));
            return pagina;
        }

        string? dispositivo_color () {
            try {
                var re = new Regex ("^Object Path:\\s+(\\S+)", RegexCompileFlags.MULTILINE);
                foreach (var bloque in colormgr ({ "get-devices-by-kind", "display" }).split ("\n\n")) {
                    MatchInfo m;
                    if (re.match (bloque, 0, out m)) {
                        return m.fetch (1);
                    }
                }
            } catch (Error e) {
            }
            return null;
        }

        void perfil_elegido (Gtk.TreeSelection sel, string? dispositivo) {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!sel.get_selected (out modelo, out it) || dispositivo == null || cargando || prueba) {
                return;
            }
            string perfil;
            modelo.get (it, 1, out perfil, -1);
            colormgr ({ "device-add-profile", dispositivo, perfil });
            colormgr ({ "device-make-profile-default", dispositivo, perfil });
        }

        // ── Night Shift ──────────────────────────────────────────────────
        int[] calidos () {
            int[] v = {};
            for (int k = 4700; k > 1600; k -= 300) {
                v += k;
            }
            return v;       // «Less Warm» a «More Warm», en kelvin
        }

        Gtk.Widget pagina_noche () {
            noche = abrir_settings ("org.cinnamon.settings-daemon.plugins.color");
            var cfg = noche;
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            pagina.margin_top = 24;
            pagina.margin_start = 24;
            pagina.margin_end = 24;
            var t = new Gtk.Label ("Night Shift automatically shifts the colors of your display to the warmer end of the color spectrum after dark. This may help you get a better night’s sleep.");
            t.set_line_wrap (true);
            t.set_max_width_chars (70);
            t.justify = Gtk.Justification.CENTER;
            pagina.pack_start (t, false, false, 0);

            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 12;
            g.halign = Gtk.Align.CENTER;
            g.attach (etiqueta_fila ("Schedule:"), 0, 0, 1, 1);
            var horario = new Gtk.ComboBoxText ();
            horario.append ("off", "Off");
            horario.append ("manual", "Custom");
            horario.append ("auto", "Sunset to Sunrise");
            string modo_inicial = "off";
            if (cfg != null && cfg.get_boolean ("night-light-enabled")) {
                modo_inicial = cfg.get_string ("night-light-schedule-mode") == "auto" ? "auto" : "manual";
            }
            horario.set_active_id (modo_inicial);
            horario.halign = Gtk.Align.START;
            g.attach (horario, 1, 0, 3, 1);

            g.attach (etiqueta_fila ("From:"), 0, 1, 1, 1);
            var desde = hora_selector ("night-light-schedule-from");
            g.attach (desde, 1, 1, 1, 1);
            g.attach (etiqueta_fila ("to:"), 2, 1, 1, 1);
            var hasta = hora_selector ("night-light-schedule-to");
            g.attach (hasta, 3, 1, 1, 1);
            g.attach (etiqueta_fila ("Manual:"), 0, 2, 1, 1);
            var manual = new Gtk.CheckButton.with_label ("Turn On Until Tomorrow");
            g.attach (gris_pant (manual, "Use the schedule to turn Night Shift on."), 1, 2, 3, 1);

            g.attach (etiqueta_fila ("Color Temperature:"), 0, 3, 1, 1);
            var tabla = calidos ();
            uint actual_k = cfg != null ? cfg.get_uint ("night-light-temperature") : 4700;
            int indice = 0;
            double mejor = double.MAX;
            for (int i = 0; i < tabla.length; i++) {
                double d = Math.fabs ((double) tabla[i] - (double) actual_k);
                if (d < mejor) {
                    mejor = d;
                    indice = i;
                }
            }
            var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, tabla.length - 1, 1);
            esc.draw_value = false;
            esc.round_digits = 0;
            esc.set_value (indice);
            esc.set_size_request (210, -1);
            esc.add_mark (0, Gtk.PositionType.BOTTOM, "Less Warm");
            esc.add_mark (tabla.length - 1, Gtk.PositionType.BOTTOM, "More Warm");
            esc.value_changed.connect (() => escribir (() => cfg.set_uint ("night-light-temperature", (uint) tabla[(int) Math.round (esc.get_value ())])));
            g.attach (esc, 1, 3, 3, 1);
            pagina.pack_start (g, false, false, 0);

            horario.changed.connect (() => {
                var modo = horario.get_active_id ();
                desde.set_sensitive (modo == "manual");
                hasta.set_sensitive (modo == "manual");
                if (modo == "off") {
                    escribir (() => cfg.set_boolean ("night-light-enabled", false));
                } else {
                    escribir (() => {
                        cfg.set_string ("night-light-schedule-mode", modo);
                        cfg.set_boolean ("night-light-enabled", true);
                    });
                }
            });
            desde.set_sensitive (horario.get_active_id () == "manual");
            hasta.set_sensitive (horario.get_active_id () == "manual");
            return pagina;
        }

        void escribir (Hacer hacer) {
            if (cargando || prueba || noche == null) {
                return;
            }
            hacer ();
        }

        /** Un selector de hora en 12 h (7:00 PM), guardada como horas decimales en gsettings. */
        Gtk.Widget hora_selector (string clave) {
            double valor = noche != null ? noche.get_double (clave) : 0;
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            var h = new Gtk.SpinButton.with_range (1, 12, 1);
            var m = new Gtk.SpinButton.with_range (0, 59, 1);
            m.numeric = true;
            m.output.connect (() => { m.set_text ("%02d".printf ((int) m.get_value ())); return true; });
            var ampm = new Gtk.ComboBoxText ();
            ampm.append ("AM", "AM");
            ampm.append ("PM", "PM");
            int h24 = ((int) valor) % 24;
            h.set_value (h24 % 12 != 0 ? h24 % 12 : 12);
            m.set_value (Math.round ((valor - (int) valor) * 60));
            ampm.set_active_id (h24 >= 12 ? "PM" : "AM");
            Hacer guardar = () => {
                int hora = (int) h.get_value () % 12 + (ampm.get_active_id () == "PM" ? 12 : 0);
                escribir (() => noche.set_double (clave, hora + (int) m.get_value () / 60.0));
            };
            h.value_changed.connect (() => guardar ());
            m.value_changed.connect (() => guardar ());
            ampm.changed.connect (() => guardar ());
            caja.pack_start (h, false, false, 0);
            caja.pack_start (m, false, false, 0);
            caja.pack_start (ampm, false, false, 0);
            return caja;
        }
    }
}
