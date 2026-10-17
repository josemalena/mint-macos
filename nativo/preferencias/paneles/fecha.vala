/*
 * Date & Time: el panel de Catalina con sus tres pestañas (Date & Time, Time Zone, Clock); port de settings/fecha.py.
 *
 * Capturas: Screen Shot 2026-10-14 at 1.22.06 PM, 1.22.09 PM y 1.22.14 PM.
 *
 * Date & Time y Time Zone usan timedatectl: cambiar la zona, el NTP o la hora pide la clave de administrador por polkit (timedated), que
 * es lo que hace el candado de abajo: pulsarlo pide la clave una vez y deja los controles listos. Clock escribe el formato del applet
 * calendar@cinnamon.org (el reloj de la barra de menús; lo lee también reloj@macos): los interruptores arman el formato strftime a
 * partir de las casillas de Catalina.
 * Sin equivalente (en gris): Analog, Flash the time separators, Show date and time in menu bar, Announce the time, Set time zone
 * automatically y el mapa de zonas horarias (arte de Apple que no sale del disco).
 */
namespace Preferencias {

    public class PanelDateTime : Panel {
        // MINT_FECHA_PRUEBA: no cambia la hora, la zona ni el reloj de la barra.
        bool prueba = Environment.get_variable ("MINT_FECHA_PRUEBA") != null;
        bool cargando = false;
        bool desbloqueado = false;
        uint tic = 0;
        GenericArray<Gtk.Widget> protegidos = new GenericArray<Gtk.Widget> ();
        Gtk.Button candado;
        Gtk.Label nota;
        Gtk.CheckButton auto_ntp;
        Gtk.Calendar calendario;
        Gtk.SpinButton hh;
        Gtk.SpinButton mm;
        Gtk.ComboBoxText pm;
        Gtk.DrawingArea reloj;
        Gtk.ComboBoxText ciudad;
        Gtk.Label abrev;
        HashTable<string, Gtk.CheckButton> opciones = new HashTable<string, Gtk.CheckButton> (str_hash, str_equal);

        public PanelDateTime () {
            id = "com.apple.preference.datetime";
            nombre = "Date & Time";
            palabras = "date, time, clock, time zone, timezone, ntp, 24-hour, menu bar, calendar, seconds, am pm";
        }

        /** (éxito, salida) de timedatectl. */
        static bool timedatectl (string[] args, out string texto) {
            string[] cmd = { "timedatectl" };
            foreach (var a in args) {
                cmd += a;
            }
            try {
                var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string? salida, error;
                p.communicate_utf8 (null, null, out salida, out error);
                texto = ((salida ?? "") != "" ? salida : (error ?? "")).strip ();
                return p.get_successful ();
            } catch (Error e) {
                texto = e.message;
                return false;
            }
        }

        static string td (string[] args) {
            string t;
            timedatectl (args, out t);
            return t;
        }

        /** Los JSON del applet calendar@cinnamon.org (uno por instancia). */
        static GenericArray<string> archivos_reloj () {
            var lista = new GenericArray<string> ();
            var dir = Path.build_filename (Environment.get_home_dir (), ".config", "cinnamon", "spices", "calendar@cinnamon.org");
            try {
                var d = Dir.open (dir);
                string? n;
                while ((n = d.read_name ()) != null) {
                    if (n.has_suffix (".json")) {
                        lista.add (Path.build_filename (dir, n));
                    }
                }
            } catch (Error e) {
            }
            return lista;
        }

        static Gtk.Widget gris_motivo (Gtk.Widget w, string? motivo = null) {
            w.set_sensitive (false);
            if (motivo != null) {
                w.set_tooltip_text (motivo);
            }
            return w;
        }

        // ── la página ────────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            cargando = true;
            protegidos = new GenericArray<Gtk.Widget> ();
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 12;
            var stack = new Gtk.Stack ();
            stack.add_titled (pagina_fecha (), "fecha", "Date & Time");
            stack.add_titled (pagina_zona (), "zona", "Time Zone");
            stack.add_titled (pagina_reloj (), "reloj", "Clock");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            candado = new Gtk.Button ();
            candado.set_relief (Gtk.ReliefStyle.NONE);
            candado.set_image (new Gtk.Image.from_icon_name ("changes-prevent-symbolic", Gtk.IconSize.LARGE_TOOLBAR));
            candado.clicked.connect (() => pedir_clave ());
            pie.pack_start (candado, false, false, 0);
            nota = new Gtk.Label ("Click the lock to make changes.");
            pie.pack_start (nota, false, false, 0);
            pie.margin_top = 6;
            pie.margin_bottom = 6;
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_FECHA_PESTANA");        // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            cargando = false;
            tic = Timeout.add_seconds (1, () => { reloj.queue_draw (); return true; });
            caja.destroy.connect (() => {
                if (tic != 0) {
                    Source.remove (tic);
                    tic = 0;
                }
            });
            return caja;
        }

        // ── el candado: la clave de administrador por polkit (la misma acción de timedated) ─────────
        void pedir_clave () {
            if (desbloqueado) {
                return;
            }
            if (prueba) {
                abrir_candado ();
                return;
            }
            // Poner el NTP como está hace que polkit pida la clave y la recuerde unos minutos.
            var actual = td ({ "show", "-p", "NTP", "--value" });
            string msg;
            if (timedatectl ({ "set-ntp", actual == "yes" ? "true" : "false" }, out msg)) {
                abrir_candado ();
            }
        }

        void abrir_candado () {
            desbloqueado = true;
            candado.set_image (new Gtk.Image.from_icon_name ("changes-allow-symbolic", Gtk.IconSize.LARGE_TOOLBAR));
            nota.set_text ("Click the lock to prevent further changes.");
            for (int i = 0; i < protegidos.length; i++) {
                protegidos[i].set_sensitive (true);
            }
            ajustar_manual ();
        }

        // ── Date & Time ──────────────────────────────────────────────────
        Gtk.Widget pagina_fecha () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            margenes (pagina, 18, 18, 24, 24);

            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            fila.halign = Gtk.Align.CENTER;
            auto_ntp = new Gtk.CheckButton.with_label ("Set date and time automatically:");
            auto_ntp.active = td ({ "show", "-p", "NTP", "--value" }) == "yes";
            auto_ntp.set_sensitive (false);
            auto_ntp.toggled.connect (() => poner_ntp (auto_ntp.active));
            protegidos.add (auto_ntp);
            fila.pack_start (auto_ntp, false, false, 0);
            var servidor = new Gtk.ComboBoxText ();
            var estado = td ({ "timesync-status" });
            string servidor_txt = "systemd-timesyncd";
            var m = new Regex ("Server:\\s+(\\S+)");
            MatchInfo mi;
            if (m.match (estado, 0, out mi)) {
                servidor_txt = mi.fetch (1);
            }
            servidor.append ("s", servidor_txt);
            servidor.set_active (0);
            fila.pack_start (gris_motivo (servidor, "The server is set in /etc/systemd/timesyncd.conf."), false, false, 0);
            pagina.pack_start (fila, false, false, 0);

            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 40);
            cuerpo.halign = Gtk.Align.CENTER;
            calendario = new Gtk.Calendar ();
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            izq.pack_start (calendario, false, false, 0);
            cuerpo.pack_start (izq, false, false, 0);
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var hora = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            hh = new Gtk.SpinButton.with_range (1, 12, 1);
            mm = new Gtk.SpinButton.with_range (0, 59, 1);
            mm.output.connect (() => { mm.set_text ("%02d".printf ((int) mm.get_value ())); return true; });
            pm = new Gtk.ComboBoxText ();
            pm.append ("AM", "AM");
            pm.append ("PM", "PM");
            hora.pack_start (hh, false, false, 0);
            hora.pack_start (mm, false, false, 0);
            hora.pack_start (pm, false, false, 0);
            der.pack_start (hora, false, false, 0);
            reloj = new Gtk.DrawingArea ();
            reloj.set_size_request (130, 130);
            reloj.draw.connect ((cr) => pintar_reloj (cr));
            der.pack_start (reloj, false, false, 0);
            cuerpo.pack_start (der, false, false, 0);
            pagina.pack_start (cuerpo, false, false, 0);
            calendario.set_sensitive (false);
            hh.set_sensitive (false);
            mm.set_sensitive (false);
            pm.set_sensitive (false);
            poner_hora_actual ();
            hh.value_changed.connect (() => fijar_hora ());
            mm.value_changed.connect (() => fijar_hora ());
            pm.changed.connect (() => fijar_hora ());
            calendario.day_selected.connect (() => fijar_hora ());

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            pie.halign = Gtk.Align.CENTER;
            pie.pack_start (new Gtk.Label ("To set date and time formats, use Language & Region preferences."), false, false, 0);
            var b = new Gtk.Button.with_label ("Open Language & Region…");
            b.clicked.connect (() => {
                try {
                    Process.spawn_async (null, { Path.build_filename (Environment.get_home_dir (), ".local", "bin", "mac-settings"), "Localization" },
                                         null, SpawnFlags.SEARCH_PATH, () => { Posix.setsid (); }, null);
                } catch (Error e) {
                }
            });
            pie.pack_start (b, false, false, 0);
            pagina.pack_end (pie, false, false, 0);
            return pagina;
        }

        void poner_hora_actual () {
            var ahora = Time.local (time_t ());
            bool previo = cargando;
            cargando = true;
            calendario.select_month (ahora.month, ahora.year + 1900);
            calendario.select_day (ahora.day);
            hh.set_value (ahora.hour % 12 != 0 ? ahora.hour % 12 : 12);
            mm.set_value (ahora.minute);
            pm.set_active_id (ahora.hour >= 12 ? "PM" : "AM");
            cargando = previo;
        }

        /** La fecha y la hora a mano solo se pueden tocar con la clave y sin NTP. */
        void ajustar_manual () {
            bool manual = desbloqueado && !auto_ntp.active;
            calendario.set_sensitive (manual);
            hh.set_sensitive (manual);
            mm.set_sensitive (manual);
            pm.set_sensitive (manual);
        }

        void poner_ntp (bool si) {
            if (cargando) {
                return;
            }
            if (!prueba) {
                string m;
                if (!timedatectl ({ "set-ntp", si ? "true" : "false" }, out m)) {
                    cargando = true;
                    auto_ntp.active = !si;
                    cargando = false;
                }
            }
            ajustar_manual ();
        }

        void fijar_hora () {
            if (cargando || prueba || !desbloqueado || auto_ntp.active) {
                return;
            }
            uint a, m, d;
            calendario.get_date (out a, out m, out d);
            int h = (int) hh.get_value () % 12 + (pm.get_active_id () == "PM" ? 12 : 0);
            string msg;
            timedatectl ({ "set-time", "%04u-%02u-%02u %02d:%02d:00".printf (a, m + 1, d, h, (int) mm.get_value ()) }, out msg);
        }

        bool pintar_reloj (Cairo.Context cr) {
            int ancho = reloj.get_allocated_width ();
            int alto = reloj.get_allocated_height ();
            double cx = ancho / 2.0, cy = alto / 2.0, r = double.min (ancho, alto) / 2.0 - 3;
            cr.arc (cx, cy, r, 0, 2 * Math.PI);
            cr.set_source_rgb (0.95, 0.95, 0.95);
            cr.fill_preserve ();
            cr.set_source_rgb (0.5, 0.5, 0.52);
            cr.set_line_width (3);
            cr.stroke ();
            cr.set_source_rgb (0.1, 0.1, 0.1);
            cr.select_font_face ("sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (r * 0.17);
            for (int n = 1; n <= 12; n++) {
                double ang = n * Math.PI / 6;
                var texto = n.to_string ();
                Cairo.TextExtents ext;
                cr.text_extents (texto, out ext);
                cr.move_to (cx + Math.sin (ang) * r * 0.78 - ext.width / 2 - ext.x_bearing,
                            cy - Math.cos (ang) * r * 0.78 - ext.height / 2 - ext.y_bearing);
                cr.show_text (texto);
            }
            var t = Time.local (time_t ());
            double[] angs = { ((t.hour % 12) + t.minute / 60.0) * Math.PI / 6, (t.minute + t.second / 60.0) * Math.PI / 30, t.second * Math.PI / 30 };
            double[] largos = { 0.5, 0.75, 0.82 };
            double[] grosores = { 4, 3, 1.2 };
            for (int i = 0; i < 3; i++) {
                if (i < 2) {
                    cr.set_source_rgb (0.1, 0.1, 0.1);
                } else {
                    cr.set_source_rgb (0.85, 0.1, 0.1);
                }
                cr.set_line_width (grosores[i]);
                cr.move_to (cx, cy);
                cr.line_to (cx + Math.sin (angs[i]) * r * largos[i], cy - Math.cos (angs[i]) * r * largos[i]);
                cr.stroke ();
            }
            return false;
        }

        // ── Time Zone ────────────────────────────────────────────────────
        Gtk.Widget pagina_zona () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            margenes (pagina, 18, 18, 24, 24);
            pagina.pack_start (new Gtk.Label ("To select a time zone, choose a city from the Closest City menu."), false, false, 0);
            var auto = new Gtk.CheckButton.with_label ("Set time zone automatically using current location");
            auto.active = true;
            auto.halign = Gtk.Align.CENTER;
            pagina.pack_start (gris_motivo (auto, "The time zone cannot be set from your location on this computer."), false, false, 0);
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 10;
            g.halign = Gtk.Align.CENTER;
            g.margin_top = 30;
            var actual = td ({ "show", "-p", "Timezone", "--value" });
            g.attach (etiqueta_fila ("Time Zone:"), 0, 0, 1, 1);
            abrev = new Gtk.Label (null);
            abrev.xalign = 0;
            g.attach (abrev, 1, 0, 1, 1);
            g.attach (etiqueta_fila ("Closest City:"), 0, 1, 1, 1);
            ciudad = new Gtk.ComboBoxText ();
            foreach (var z in td ({ "list-timezones" }).split ("\n")) {
                if (z != "") {
                    ciudad.append (z, z.replace ("_", " "));
                }
            }
            ciudad.set_active_id (actual);
            ciudad.set_sensitive (false);
            protegidos.add (ciudad);
            ciudad.changed.connect (() => poner_zona (ciudad.get_active_id ()));
            g.attach (ciudad, 1, 1, 1, 1);
            abrev.set_text (Time.local (time_t ()).format ("%Z"));
            pagina.pack_start (g, false, false, 0);
            return pagina;
        }

        void poner_zona (string? zona) {
            if (cargando || prueba || zona == null || zona == "") {
                return;
            }
            string m;
            timedatectl ({ "set-timezone", zona }, out m);
            abrev.set_text (Time.local (time_t ()).format ("%Z"));
        }

        // ── Clock ────────────────────────────────────────────────────────
        Gtk.Widget pagina_reloj () {
            var formato = formato_actual ();
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            pagina.margin_top = 18;
            pagina.margin_start = 60;
            pagina.margin_bottom = 18;
            var menu = new Gtk.CheckButton.with_label ("Show date and time in menu bar");
            menu.active = true;
            pagina.pack_start (gris_motivo (menu, "The clock lives in the Cinnamon panel."), false, false, 0);

            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 6;
            g.margin_start = 20;
            g.attach (etiqueta_fila ("Time options:"), 0, 0, 1, 1);
            var tipo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var digital = new Gtk.RadioButton.with_label_from_widget (null, "Digital");
            var analogico = new Gtk.RadioButton.with_label_from_widget (digital, "Analog");
            tipo.pack_start (digital, false, false, 0);
            tipo.pack_start (gris_motivo (analogico, "The panel clock is digital on this computer."), false, false, 0);
            g.attach (tipo, 1, 0, 1, 1);
            string[] claves = { "seconds", "flash", "h24", "ampm" };
            string[] textos = { "Display the time with seconds", "Flash the time separators", "Use a 24-hour clock", "Show AM/PM" };
            bool[] activos = { formato.contains ("%S"), false, formato.contains ("%H") || formato.contains ("%k"),
                               formato.contains ("%p") || formato.contains ("%P") };
            for (int i = 0; i < 4; i++) {
                var c = new Gtk.CheckButton.with_label (textos[i]);
                c.active = activos[i];
                if (claves[i] == "flash") {
                    gris_motivo (c, "Not available on this computer.");
                } else {
                    c.toggled.connect (() => guardar_formato ());
                }
                opciones[claves[i]] = c;
                g.attach (c, 1, 1 + i, 1, 1);
            }
            g.attach (etiqueta_fila ("Date options:"), 0, 6, 1, 1);
            string[] claves2 = { "week", "date" };
            string[] textos2 = { "Show the day of the week", "Show date" };
            bool[] activos2 = { formato.contains ("%a") || formato.contains ("%A"),
                                formato.contains ("%b") || formato.contains ("%d") || formato.contains ("%-d") || formato.contains ("%e") };
            for (int i = 0; i < 2; i++) {
                var c = new Gtk.CheckButton.with_label (textos2[i]);
                c.active = activos2[i];
                c.toggled.connect (() => guardar_formato ());
                opciones[claves2[i]] = c;
                g.attach (c, 1, 6 + i, 1, 1);
            }
            pagina.pack_start (g, false, false, 0);

            var voz = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var c = new Gtk.CheckButton.with_label ("Announce the time:");
            voz.pack_start (gris_motivo (c, "Not available on this computer."), false, false, 0);
            var combo = new Gtk.ComboBoxText ();
            combo.append ("h", "On the hour");
            combo.set_active (0);
            voz.pack_start (gris (combo), false, false, 0);
            voz.pack_start (gris (new Gtk.Button.with_label ("Customize Voice…")), false, false, 0);
            voz.margin_top = 24;
            voz.margin_bottom = 24;
            pagina.pack_start (voz, false, false, 0);
            sincronizar_reloj ();
            return pagina;
        }

        /** AM/PM solo tiene sentido con el reloj de 12 horas. */
        void sincronizar_reloj () {
            opciones["ampm"].set_sensitive (!opciones["h24"].active);
        }

        static string formato_actual () {
            var archivos = archivos_reloj ();
            for (int i = 0; i < archivos.length; i++) {
                var ruta = archivos[i];
                try {
                    var p = new Json.Parser ();
                    p.load_from_file (ruta);
                    var d = p.get_root ().get_object ();
                    if (d.has_member ("use-custom-format") && d.get_object_member ("use-custom-format").get_boolean_member ("value")) {
                        return d.has_member ("custom-format") ? d.get_object_member ("custom-format").get_string_member ("value") : "";
                    }
                } catch (Error e) {
                    continue;
                }
            }
            return "%a %b %-d %-I:%M %p";
        }

        string armar_formato () {
            string[] partes = {};
            if (opciones["week"].active) {
                partes += "%a";
            }
            if (opciones["date"].active) {
                partes += "%b %-d";
            }
            string hora;
            if (opciones["h24"].active) {
                hora = "%H:%M" + (opciones["seconds"].active ? ":%S" : "");
            } else {
                hora = "%-I:%M" + (opciones["seconds"].active ? ":%S" : "") + (opciones["ampm"].active ? " %p" : "");
            }
            partes += hora;
            return string.joinv (" ", partes);
        }

        void guardar_formato () {
            sincronizar_reloj ();
            if (cargando || prueba) {
                return;
            }
            var nuevo = armar_formato ();
            var archivos = archivos_reloj ();
            for (int i = 0; i < archivos.length; i++) {
                var ruta = archivos[i];
                try {
                    var p = new Json.Parser ();
                    p.load_from_file (ruta);
                    var raiz = p.get_root ();
                    var d = raiz.get_object ();
                    d.get_object_member ("custom-format").set_string_member ("value", nuevo);
                    d.get_object_member ("use-custom-format").set_boolean_member ("value", true);
                    FileUtils.set_contents (ruta + ".tmp", json_a_texto (raiz, false));
                    FileUtils.rename (ruta + ".tmp", ruta);
                } catch (Error e) {
                    continue;
                }
            }
        }
    }
}
