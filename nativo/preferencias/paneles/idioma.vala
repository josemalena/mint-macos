/*
 * Language & Region: el panel de Catalina (Screen Shot 2026-10-14 at 12.13.52 AM General y 12.13.55 AM Apps); port de
 * settings/idioma.py.
 *
 * Lo que enseña es lo que el sistema tiene de verdad: el idioma de LANG (iso-codes), la región de LC_NUMERIC / LC_MONETARY (en esta
 * Mac mini el idioma es inglés y los formatos son de República Dominicana, como en Catalina), el primer día de la semana y el
 * ejemplo de fecha, hora, número y moneda con esos formatos. Cambiar el idioma o los formatos se hace con root
 * (/etc/default/locale), así que todos los controles van en gris; Keyboard Preferences… abre el panel Keyboard.
 * Advanced… (hojas General, Dates y Times: 12.14.01 a 12.14.07) y la hoja + no están hechas.
 * Sin equivalente (en gris): Calendar, Temperature y la pestaña Apps (el idioma por app).
 */
[CCode (cheader_filename = "monetary.h", cname = "strfmon")]
extern ssize_t strfmon (char* s, size_t max, string formato, ...);

namespace Preferencias {

    public class PanelLanguage : Panel {
        public PanelLanguage () {
            id = "com.apple.Localization";
            nombre = "Language & Region";
            palabras = "language, region, formats, first day of week, calendar, time format, temperature, preferred languages, currency";
        }

        /** El nombre de un código de iso-codes (iso_639-3 por alpha_2, iso_3166-1 por alpha_2), o el código si no se halla. */
        static string nombre_iso (string archivo, string tabla, string codigo) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (Path.build_filename ("/usr/share/iso-codes/json", archivo));
                var lista = parser.get_root ().get_object ().get_array_member (tabla);
                for (uint i = 0; i < lista.get_length (); i++) {
                    var x = lista.get_object_element (i);
                    if (x.has_member ("alpha_2") && x.get_string_member ("alpha_2") == codigo) {
                        return x.get_string_member ("name");
                    }
                }
            } catch (Error e) {
            }
            return codigo;
        }

        static Gtk.Widget gris_idioma (Gtk.Widget w, string motivo = "Changing the language or the formats needs the administrator.") {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 14, 14, 14, 14);
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            cab.pack_start (imagen_icono_panel (id, 48), false, false, 0);
            var t = new Gtk.Label ("Language & Region preferences control the language you see in menus and dialogs, and the formats of dates, times, and currencies.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (70);
            cab.pack_start (t, true, true, 0);
            caja.pack_start (cab, false, false, 0);

            var stack = new Gtk.Stack ();
            stack.add_titled (general (), "general", "General");
            stack.add_titled (apps (), "apps", "Apps");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var teclado = new Gtk.Button.with_label ("Keyboard Preferences…");
            teclado.clicked.connect (() => {
                try {
                    Process.spawn_async (null, { Path.build_filename (Environment.get_home_dir (), ".local", "bin", "mac-settings"), "keyboard" },
                                         null, SpawnFlags.SEARCH_PATH, () => { Posix.setsid (); }, null);
                } catch (Error e) {
                }
            });
            var avanzado = new Gtk.Button.with_label ("Advanced…");
            gris_idioma (avanzado, "This sheet is not available yet.");
            pie.pack_end (avanzado, false, false, 0);
            pie.pack_end (teclado, false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            return caja;
        }

        Gtk.Widget general () {
            var lang = Environment.get_variable ("LANG") ?? "en_US.UTF-8";
            lang = lang.split (".")[0];
            var idioma = nombre_iso ("iso_639-3.json", "639-3", lang.split ("_")[0]);
            // La región es la de LC_NUMERIC (es_DO.UTF-8 → DO); si es «C», la de LANG.
            var numerico = Intl.setlocale (LocaleCategory.NUMERIC, null) ?? "C";
            string region_lang = lang;
            if (numerico != "C" && numerico != "POSIX" && numerico != "") {
                region_lang = numerico.split (".")[0].split ("@")[0];
            }
            var partes = region_lang.split ("_");
            var pais = nombre_iso ("iso_3166-1.json", "3166-1", partes[partes.length - 1]);
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            pagina.margin = 16;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var pref = new Gtk.Label ("Preferred languages:");
            pref.xalign = 0;
            izq.pack_start (pref, false, false, 0);
            var lista = new Gtk.ListBox ();
            lista.set_size_request (200, 220);
            var fila = new Gtk.ListBoxRow ();
            var v = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            v.margin = 6;
            var nom = new Gtk.Label (idioma);
            nom.xalign = 0;
            v.pack_start (nom, false, false, 0);
            var s = new Gtk.Label ("%s — Primary".printf (idioma));
            s.xalign = 0;
            s.get_style_context ().add_class ("mp-sd-detalle");
            v.pack_start (s, false, false, 0);
            fila.add (v);
            lista.add (fila);
            var m = marco_lista ();
            m.add (gris_idioma (lista));
            izq.pack_start (m, true, true, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var tx in new string[] { "+", "−" }) {
                botones.pack_start (gris_idioma (new Gtk.Button.with_label (tx)), false, false, 0);
            }
            izq.pack_start (botones, false, false, 0);
            pagina.pack_start (izq, false, false, 0);

            var der = new Gtk.Grid ();
            der.column_spacing = 10;
            der.row_spacing = 10;
            der.valign = Gtk.Align.START;
            string[] dias = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
            var ifz = new Settings ("org.cinnamon.desktop.interface");
            int primero = ifz.get_int ("first-day-of-week");
            var dia = (primero >= 1 && primero <= 7 && primero != 7) ? dias[primero - 1] : "Sunday";
            combo (der, "Region:", pais, 0);
            combo (der, "First day of week:", dia, 1);
            combo (der, "Calendar:", "Gregorian", 2);
            der.attach (etiqueta_fila ("Time format:"), 0, 3, 1, 1);
            var h24 = new Gtk.CheckButton.with_label ("24-Hour Time");
            h24.active = ifz.get_boolean ("clock-use-24h");
            der.attach (gris_idioma (h24, "Use the Clock tab of Date & Time for the clock in the menu bar."), 1, 3, 1, 1);
            combo (der, "Temperature:", "°C — Celsius", 4);
            var ahora = Time.local (time_t ());
            var moneda = new char[128];
            strfmon (moneda, 128, "%n", 45678.9);
            string[] ejemplo = { ahora.format ("%A, %B %-d, %Y at %-I:%M:%S %p %Z"),
                                 ahora.format ("%x, %-I:%M %p"),
                                 "%s    %s".printf ("%'.2f".printf (12345.67), (string) moneda) };
            for (int i = 0; i < 3; i++) {
                var l = new Gtk.Label (ejemplo[i]);
                l.xalign = 0;
                l.get_style_context ().add_class ("mp-sd-detalle");
                l.margin_top = i == 0 ? 14 : 0;
                der.attach (l, 0, 5 + i, 2, 1);
            }
            pagina.pack_start (der, true, true, 0);
            return pagina;
        }

        void combo (Gtk.Grid der, string titulo, string texto, int fila) {
            der.attach (etiqueta_fila (titulo), 0, fila, 1, 1);
            var c = new Gtk.ComboBoxText ();
            c.append ("v", texto);
            c.set_active (0);
            der.attach (gris_idioma (c), 1, fila, 1, 1);
        }

        Gtk.Widget apps () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            pagina.margin = 16;
            var t = new Gtk.Label ("Customize language settings for the apps below:");
            t.xalign = 0;
            pagina.pack_start (t, false, false, 0);
            var m = marco_lista ();
            m.set_size_request (-1, 230);
            pagina.pack_start (gris_idioma (m, "The language per app is not available on this computer."), true, true, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var tx in new string[] { "+", "−" }) {
                botones.pack_start (gris_idioma (new Gtk.Button.with_label (tx)), false, false, 0);
            }
            pagina.pack_start (botones, false, false, 0);
            return pagina;
        }
    }
}
