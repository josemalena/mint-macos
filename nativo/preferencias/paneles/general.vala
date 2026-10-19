/*
 * General: el panel de Catalina (Screen Shot 2026-10-14 at 12.11.59 AM); port de settings/general.py.
 *
 * Conectado de verdad: Default web browser (xdg-settings), Show scroll bars (gtk-overlay-scrollbars) y Appearance, Accent color y
 * Highlight color, que van al servicio org.mintmacos.Apariencia1 (rust/apariencia/DBUS.md): Light, Dark y Auto cambian el tema
 * activo al instante. Los acentos salen del perfil de la versión de macOS activa (Estado ▸ acentos). Sin el servicio esos controles
 * quedan en gris. Con las claves que dice perfiles/adaptaciones.json: ocultar la barra de menús (panels-autohide del panel de arriba),
 * Click in the scroll bar to (Gtk/PrimaryButtonWarpsSlider en xsettings), font smoothing (antialiasing en xsettings y en gnome) y
 * Recent items (recent-items del applet del menú Apple). El resto (Sidebar icon size, las casillas de documentos y Handoff) no tiene
 * una clave que podamos escribir y comprobar aquí: se dibuja como en la captura, en gris, como en una Mac sin esa función.
 *
 * Las miniaturas de Light/Dark/Auto son arte de Apple y salen del disco de la Mac, no del repo
 * (~/.local/share/mint-macos/settings/apariencia/); sin ellas se ven los nombres solos.
 */
namespace Preferencias {

    /** Un círculo de color del selector de Accent color; el escogido lleva un aro. */
    public class PuntoAcento : Gtk.DrawingArea {
        public string clave;
        public string color;
        public bool marcado = false;
        public signal void escogido (string clave);

        public PuntoAcento (string clave, string color) {
            this.clave = clave;
            this.color = color;
            set_size_request (20, 20);
            add_events (Gdk.EventMask.BUTTON_PRESS_MASK);
            set_tooltip_text (clave);
            draw.connect (pintar);
            button_press_event.connect ((e) => {
                if (is_sensitive ()) escogido (this.clave);
                return true;
            });
        }

        bool pintar (Cairo.Context cr) {
            double c = 10.0;
            var rgba = Gdk.RGBA ();
            if (!rgba.parse (color)) rgba.parse ("#8c8c8c");
            if (marcado) {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.9);
                cr.set_line_width (1.5);
                cr.arc (c, c, 9.0, 0, 6.2832);
                cr.stroke ();
            }
            cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, is_sensitive () ? 1.0 : 0.4);
            cr.arc (c, c, 6.5, 0, 6.2832);
            cr.fill ();
            return false;
        }
    }

    public class PanelGeneral : Panel {
        // MINT_GENERAL_PRUEBA: no escribe en gsettings ni en xdg-settings.
        bool prueba = Environment.get_variable ("MINT_GENERAL_PRUEBA") != null;
        bool cargando = false;
        Settings? cfg = null;
        HashTable<string, Gdk.Pixbuf?> miniaturas = new HashTable<string, Gdk.Pixbuf?> (str_hash, str_equal);
        HashTable<string, Gtk.RadioButton> radios = new HashTable<string, Gtk.RadioButton> (str_hash, str_equal);
        GenericArray<Gtk.DrawingArea> areas = new GenericArray<Gtk.DrawingArea> ();
        Gtk.ComboBoxText navegador;
        GenericArray<PuntoAcento> puntos_acento = new GenericArray<PuntoAcento> ();
        Gtk.ComboBoxText? resaltado_c = null;

        public PanelGeneral () {
            id = "com.apple.preference.general";
            nombre = "General";
            palabras = "appearance, dark, light, accent color, highlight, scroll bars, default web browser, recent items, handoff, font smoothing";
        }

        static Gtk.Widget linea () {
            var s = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            s.margin_top = 8;
            s.margin_bottom = 8;
            return s;
        }

        /** Corre mint-macos-version y devuelve su salida, o null si el comando no está. */
        static string? correr_version (string arg) {
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE, "mint-macos-version", arg);
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                return p.get_exit_status () == 0 ? salida : null;
            } catch (Error e) {
                return null;
            }
        }

        /** «macOS version:» con las versiones que tienen perfil en esta máquina (mint-macos-version --lista). Sin el comando, no sale. */
        int version_de_macos (Gtk.Grid g, int fila) {
            var lista = correr_version ("--lista");
            if (lista == null) return fila;
            string? escogida = null;
            // sin argumentos imprime «activa: …» y «escogida: …»
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE, "mint-macos-version");
                string? o;
                p.communicate_utf8 (null, null, out o, null);
                foreach (var l in (o ?? "").split ("\n")) {
                    if (l.has_prefix ("escogida:")) escogida = l.substring (9).strip ();
                }
            } catch (Error e) {
            }
            var combo = new Gtk.ComboBoxText ();
            foreach (var l in lista.split ("\n")) {
                var t = l.strip ();
                if (t == "") continue;
                // «id   nombre  (falta: …)»
                var partes = t.split (" ", 2);
                var id = partes[0];
                var nombre = partes.length > 1 ? partes[1].strip () : id;
                var faltas = nombre.index_of ("  (falta");
                if (faltas > 0) nombre = nombre.substring (0, faltas).strip ();
                combo.append (id, nombre);
            }
            if (escogida != null) combo.set_active_id (escogida);
            if (combo.get_active () < 0) combo.set_active (0);
            g.attach (etiqueta_fila ("macOS version:"), 0, fila, 1, 1);
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            caja.pack_start (combo, false, false, 0);
            var nota = new Gtk.Label ("Takes effect the next time you log in.");
            nota.xalign = 0;
            nota.get_style_context ().add_class ("mp-sd-detalle");
            caja.pack_start (nota, false, false, 0);
            g.attach (caja, 1, fila, 2, 1);
            combo.changed.connect (() => {
                var id = combo.get_active_id ();
                if (id == null || prueba) return;
                correr_version_con ("--poner", id);
            });
            return fila + 1;
        }

        static void correr_version_con (string a, string b) {
            try {
                new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE, "mint-macos-version", a, b);
            } catch (Error e) {
                warning ("mint-macos-version: %s", e.message);
            }
        }

        // ── Appearance: el servicio de Infra ─────────────────────────────
        static string? hex_de_acento (string nombre) {
            switch (nombre) {
            case "Blue": return "#007AFF";
            case "Purple": return "#953D96";
            case "Pink": return "#F74F9E";
            case "Red": return "#E0383E";
            case "Orange": return "#F7821B";
            case "Yellow": return "#FFC600";
            case "Green": return "#62BA46";
            case "Graphite": return "#8C8C8C";
            }
            return null;
        }

        /** Estado() del servicio, o null si no contesta (se activa solo; 3 s de plazo). */
        static VariantDict? estado_apariencia (out string[] acentos) {
            acentos = {};
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                var r = bus.call_sync ("org.mintmacos.Apariencia1", "/org/mintmacos/Apariencia1", "org.mintmacos.Apariencia1", "Estado",
                                       null, new VariantType ("(a{sv})"), DBusCallFlags.NONE, 3000, null);
                var d = new VariantDict (r.get_child_value (0));
                var a = d.lookup_value ("acentos", new VariantType ("as"));
                if (a != null) acentos = a.dup_strv ();
                return d;
            } catch (GLib.Error e) {
                return null;
            }
        }

        // ── Menu bar: esconder el panel de arriba ─────────────────────────
        /** El número del panel de arriba de Cinnamon («1:0:top» → «1»), o null. */
        static string? panel_de_arriba (Settings cin) {
            foreach (var e in cin.get_strv ("panels-enabled")) {
                var p = e.split (":");
                if (p.length >= 3 && p[2] == "top") return p[0];
            }
            return null;
        }

        static bool panel_oculto (Settings cin, string panel) {
            foreach (var e in cin.get_strv ("panels-autohide")) {
                if (e.has_prefix (panel + ":")) return e.substring (panel.length + 1) == "true";
            }
            return false;
        }

        void poner_panel_oculto (Settings cin, string panel, bool si) {
            if (cargando || prueba) return;
            string[] lista = {};
            bool visto = false;
            foreach (var e in cin.get_strv ("panels-autohide")) {
                if (e.has_prefix (panel + ":")) {
                    lista += "%s:%s".printf (panel, si ? "true" : "false");
                    visto = true;
                } else {
                    lista += e;
                }
            }
            if (!visto) lista += "%s:%s".printf (panel, si ? "true" : "false");
            cin.set_strv ("panels-autohide", lista);
            Settings.sync ();
        }

        // ── Click in the scroll bar to: xsettings overrides ───────────────
        const string CLAVE_SALTO = "Gtk/PrimaryButtonWarpsSlider";

        static int salto_actual (Settings xs) {
            var d = new VariantDict (xs.get_value ("overrides"));
            var v = d.lookup_value (CLAVE_SALTO, null);
            if (v == null) return 0;
            if (v.is_of_type (VariantType.INT32)) return v.get_int32 ();
            if (v.is_of_type (VariantType.BOOLEAN)) return v.get_boolean () ? 1 : 0;
            return 0;
        }

        void poner_salto (Settings xs, int n) {
            if (cargando || prueba) return;
            // Se mezcla con las demás entradas de overrides: no se pisan.
            var d = new VariantDict (xs.get_value ("overrides"));
            d.insert_value (CLAVE_SALTO, new Variant.int32 (n));
            xs.set_value ("overrides", d.end ());
            Settings.sync ();
        }

        // ── Use font smoothing ────────────────────────────────────────────
        void poner_suavizado (bool si) {
            if (cargando || prueba) return;
            var valor = si ? "grayscale" : "none";
            // Las dos a la vez: la primera la leen las apps de X por XSETTINGS, la segunda GTK 4 y libadwaita.
            var xs = abrir_settings ("org.cinnamon.settings-daemon.plugins.xsettings");
            if (xs != null) xs.set_string ("antialiasing", valor);
            var gn = abrir_settings ("org.gnome.desktop.interface");
            if (gn != null) gn.set_string ("font-antialiasing", valor);
            Settings.sync ();
        }

        // ── Recent items: el ajuste del applet del menú Apple ─────────────
        const int[] RECIENTES_VALORES = { 0, 5, 10, 15, 20, 30, 50 };

        static string[] archivos_applet_recientes () {
            string[] res = {};
            var dir = Path.build_filename (Environment.get_user_config_dir (), "cinnamon", "spices", "applemenu@macos");
            try {
                var d = Dir.open (dir);
                string? n;
                while ((n = d.read_name ()) != null) {
                    if (n.has_suffix (".json")) res += Path.build_filename (dir, n);
                }
            } catch (FileError e) {
            }
            return res;
        }

        static int recientes_actual () {
            foreach (var f in archivos_applet_recientes ()) {
                try {
                    var p = new Json.Parser ();
                    p.load_from_file (f);
                    var o = p.get_root ().get_object ();
                    if (o.has_member ("recent-items")) {
                        var r = o.get_object_member ("recent-items");
                        if (r.has_member ("value")) return (int) r.get_int_member ("value");
                    }
                } catch (GLib.Error e) {
                }
            }
            return 10;
        }

        void poner_recientes (int n) {
            if (cargando || prueba) return;
            foreach (var f in archivos_applet_recientes ()) {
                try {
                    var p = new Json.Parser ();
                    p.load_from_file (f);
                    var o = p.get_root ().get_object ();
                    Json.Object r;
                    if (o.has_member ("recent-items")) {
                        r = o.get_object_member ("recent-items");
                    } else {
                        r = new Json.Object ();
                        r.set_string_member ("type", "generic");
                        r.set_int_member ("default", 10);
                        o.set_object_member ("recent-items", r);
                    }
                    r.set_int_member ("value", n);
                    var g = new Json.Generator ();
                    g.pretty = true;
                    g.indent = 4;
                    g.root = p.get_root ();
                    g.to_file (f);
                } catch (GLib.Error e) {
                    warning ("recent-items: %s", e.message);
                }
            }
        }

        static string texto_de (VariantDict d, string clave, string defecto) {
            var v = d.lookup_value (clave, VariantType.STRING);
            return v != null ? v.get_string () : defecto;
        }

        void poner_apariencia (string apariencia, string acento, string resaltado) {
            if (cargando || prueba) return;
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                bus.call.begin ("org.mintmacos.Apariencia1", "/org/mintmacos/Apariencia1", "org.mintmacos.Apariencia1", "Poner",
                                new Variant ("(sss)", apariencia, acento, resaltado), new VariantType ("(b)"), DBusCallFlags.NONE, 10000, null,
                                (o, res) => {
                    try {
                        bus.call.end (res);
                    } catch (GLib.Error e) {
                        warning ("Apariencia1.Poner: %s", e.message);
                    }
                });
            } catch (GLib.Error e) {
                warning ("Apariencia1: %s", e.message);
            }
        }

        static Gtk.Widget gris_motivo (Gtk.Widget w, string? motivo) {
            w.set_sensitive (false);
            if (motivo != null) {
                w.set_tooltip_text (motivo);
            }
            return w;
        }

        public override Gtk.Widget? construir () {
            cargando = true;
            string[] acentos;
            var est = estado_apariencia (out acentos);
            string apariencia_actual = "dark";
            string acento_actual = "";
            string resaltado_actual = "acento";
            if (est != null) {
                apariencia_actual = texto_de (est, "apariencia", "dark");
                acento_actual = texto_de (est, "acento", "");
                resaltado_actual = texto_de (est, "resaltado", "acento");
            }
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 18;
            caja.margin_bottom = 18;
            var g = new Gtk.Grid ();
            g.column_spacing = 12;
            g.row_spacing = 10;
            g.halign = Gtk.Align.CENTER;
            int fila = 0;

            // Appearance: Light / Dark / Auto
            g.attach (etiqueta_fila ("Appearance:"), 0, fila, 1, 1);
            var opciones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            Gtk.RadioButton? grupo = null;
            string[] claves = { "light", "dark", "auto" };
            string[] textos = { "Light", "Dark", "Auto" };
            for (int i = 0; i < 3; i++) {
                var clave = claves[i];
                var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
                var ruta = Path.build_filename (Environment.get_home_dir (), ".local", "share", "mint-macos", "settings", "apariencia", clave + ".png");
                Gdk.Pixbuf? miniatura = null;
                if (FileUtils.test (ruta, FileTest.EXISTS)) {
                    try {
                        miniatura = new Gdk.Pixbuf.from_file_at_scale (ruta, 68, 45, true);
                    } catch (Error e) {
                        miniatura = null;
                    }
                }
                var area = new Gtk.DrawingArea ();
                area.set_size_request (72, 49);
                area.halign = Gtk.Align.CENTER;
                miniaturas[clave] = miniatura;
                area.draw.connect ((cr) => pintar_miniatura (area, cr, clave));
                areas.add (area);
                c.pack_start (area, false, false, 0);
                var r = new Gtk.RadioButton.with_label_from_widget (grupo, textos[i]);
                if (grupo == null) {
                    grupo = r;
                }
                r.active = clave == apariencia_actual;
                radios[clave] = r;
                r.toggled.connect (() => {
                    for (int k = 0; k < areas.length; k++) {
                        areas[k].queue_draw ();
                    }
                    if (r.active) {
                        poner_apariencia (clave, "", "");
                    }
                });
                if (est == null) {
                    gris_motivo (r, "The appearance service is not available on this computer.");
                }
                c.pack_start (r, false, false, 0);
                opciones.pack_start (c, false, false, 0);
            }
            g.attach (opciones, 1, fila, 2, 1);
            fila++;

            // La versión de macOS que imitan todas las piezas (perfiles/ESQUEMA.md): una sola, global. Es un ajuste de mint-macos, no de
            // macOS: el texto es propio. Cambiarla no reinicia nada; vale al volver a entrar.
            fila = version_de_macos (g, fila);

            // Accent color y Highlight color: los acentos son los de la versión de macOS activa.
            g.attach (etiqueta_fila ("Accent color:"), 0, fila, 1, 1);
            var puntos = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            foreach (var nombre_acento in acentos) {
                var pt = new PuntoAcento (nombre_acento, hex_de_acento (nombre_acento) ?? "#8C8C8C");
                pt.marcado = nombre_acento == acento_actual;
                pt.escogido.connect ((k) => {
                    for (int j = 0; j < puntos_acento.length; j++) {
                        puntos_acento[j].marcado = puntos_acento[j].clave == k;
                        puntos_acento[j].queue_draw ();
                    }
                    poner_apariencia ("", k, "");
                });
                puntos_acento.add (pt);
                puntos.pack_start (pt, false, false, 0);
            }
            if (est == null || acentos.length == 0) {
                gris_motivo (puntos, "The appearance service is not available on this computer.");
                g.attach (puntos, 1, fila, 2, 1);
            } else {
                g.attach (puntos, 1, fila, 2, 1);
            }
            fila++;
            g.attach (etiqueta_fila ("Highlight color:"), 0, fila, 1, 1);
            var c1 = new Gtk.ComboBoxText ();
            resaltado_c = c1;
            c1.append ("acento", "Accent Color");
            foreach (var nombre_acento in acentos) {
                c1.append (hex_de_acento (nombre_acento) ?? "#8C8C8C", nombre_acento);
            }
            if (!c1.set_active_id (resaltado_actual)) {
                if (resaltado_actual.has_prefix ("#") && resaltado_actual.length == 7) {
                    c1.append (resaltado_actual, "Other");
                }
                if (!c1.set_active_id (resaltado_actual)) c1.set_active (0);
            }
            c1.changed.connect (() => {
                var v = c1.get_active_id ();
                if (v != null) poner_apariencia ("", "", v);
            });
            if (est == null) {
                gris_motivo (c1, "The appearance service is not available on this computer.");
            }
            g.attach (c1, 1, fila, 2, 1);
            fila++;
            g.attach (etiqueta_fila ("Sidebar icon size:"), 0, fila, 1, 1);
            var c2 = new Gtk.ComboBoxText ();
            c2.append ("s", "Small");
            c2.append ("m", "Medium");
            c2.append ("l", "Large");
            c2.set_active (1);
            g.attach (gris (c2), 1, fila, 2, 1);
            fila++;
            var ocultar = new Gtk.CheckButton.with_label ("Automatically hide and show the menu bar");
            var cin = abrir_settings ("org.cinnamon");
            var arriba = cin != null ? panel_de_arriba (cin) : null;
            if (cin != null && arriba != null) {
                ocultar.active = panel_oculto (cin, arriba);
                ocultar.toggled.connect (() => poner_panel_oculto (cin, arriba, ocultar.active));
                g.attach (ocultar, 1, fila, 2, 1);
            } else {
                g.attach (gris (ocultar), 1, fila, 2, 1);
            }
            fila++;

            g.attach (linea (), 0, fila, 3, 1);
            fila++;

            // Show scroll bars (la tercera opción, «Always», es la barra clásica de GTK)
            cfg = abrir_settings ("org.cinnamon.desktop.interface");
            bool overlay = cfg != null && cfg.get_boolean ("gtk-overlay-scrollbars");
            g.attach (etiqueta_fila ("Show scroll bars:"), 0, fila, 1, 1);
            var barras = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var auto = new Gtk.RadioButton.with_label_from_widget (null, "Automatically based on mouse or trackpad");
            var scroll = new Gtk.RadioButton.with_label_from_widget (auto, "When scrolling");
            var siempre = new Gtk.RadioButton.with_label_from_widget (auto, "Always");
            gris_motivo (auto, "GTK cannot tell a mouse from a trackpad here.");
            if (overlay) {
                scroll.active = true;
            } else {
                siempre.active = true;
            }
            scroll.toggled.connect (() => poner_overlay (scroll.active));
            barras.pack_start (auto, false, false, 0);
            barras.pack_start (scroll, false, false, 0);
            barras.pack_start (siempre, false, false, 0);
            g.attach (barras, 1, fila, 2, 1);
            fila++;
            g.attach (etiqueta_fila ("Click in the scroll bar to:"), 0, fila, 1, 1);
            var clic = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var r1 = new Gtk.RadioButton.with_label_from_widget (null, "Jump to the next page");
            var r2 = new Gtk.RadioButton.with_label_from_widget (r1, "Jump to the spot that’s clicked");
            clic.pack_start (r1, false, false, 0);
            clic.pack_start (r2, false, false, 0);
            var xs = abrir_settings ("org.cinnamon.settings-daemon.plugins.xsettings");
            if (xs != null) {
                if (salto_actual (xs) == 1) r2.active = true;
                r2.toggled.connect (() => poner_salto (xs, r2.active ? 1 : 0));
                g.attach (clic, 1, fila, 2, 1);
            } else {
                g.attach (gris_motivo (clic, "This is decided by each app on this computer."), 1, fila, 2, 1);
            }
            fila++;

            g.attach (linea (), 0, fila, 3, 1);
            fila++;

            // Default web browser
            g.attach (etiqueta_fila ("Default web browser:"), 0, fila, 1, 1);
            navegador = new Gtk.ComboBoxText ();
            var actual = navegador_actual ();
            bool encontrado = false;
            foreach (var app in navegadores ()) {
                navegador.append (app.get_id (), app.get_display_name ());
                if (app.get_id () == actual) {
                    navegador.set_active_id (actual);
                    encontrado = true;
                }
            }
            if (!encontrado && actual != "") {
                var info = new DesktopAppInfo (actual);
                navegador.append (actual, info != null ? info.get_display_name () : actual);
                navegador.set_active_id (actual);
            }
            navegador.changed.connect (() => poner_navegador (navegador.get_active_id ()));
            navegador.halign = Gtk.Align.START;
            g.attach (navegador, 1, fila, 2, 1);
            fila++;

            g.attach (linea (), 0, fila, 3, 1);
            fila++;

            // Lo de los documentos, Recent items, Handoff y font smoothing: sin equivalente aquí, en gris.
            string[] docs = { "Ask to keep changes when closing documents", "Close windows when quitting an app" };
            bool[] docs_on = { false, true };
            for (int i = 0; i < 2; i++) {
                var c = new Gtk.CheckButton.with_label (docs[i]);
                c.active = docs_on[i];
                g.attach (gris_motivo (c, "Each app decides this on this computer."), 1, fila, 2, 1);
                fila++;
                if (i == 1) {
                    // El texto de ayuda que el nib trae debajo de «Close windows when quitting an app» (11 pt).
                    var ayuda = new Gtk.Label ("When selected, open documents and windows will not be restored when you re-open an app.");
                    ayuda.xalign = 0;
                    ayuda.set_line_wrap (true);
                    ayuda.set_max_width_chars (52);
                    ayuda.get_style_context ().add_class ("mp-sd-detalle");
                    g.attach (ayuda, 1, fila, 2, 1);
                    fila++;
                }
            }
            g.attach (etiqueta_fila ("Recent items:"), 0, fila, 1, 1);
            var rec = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var spin = new Gtk.SpinButton.with_range (0, 50, 5);
            spin.set_value (recientes_actual ());
            // Solo los valores de la Mac (None, 5, 10, 15, 20, 30, 50), y 0 se lee «None».
            spin.output.connect (() => {
                if (spin.get_value_as_int () == 0) {
                    spin.set_text ("None");
                    return true;
                }
                return false;
            });
            spin.input.connect ((out nuevo) => {
                nuevo = spin.text == "None" ? 0.0 : double.parse (spin.text);
                return 1;
            });
            int previo = spin.get_value_as_int ();
            spin.value_changed.connect (() => {
                int v = spin.get_value_as_int ();
                int ajustado = v;
                if (v > previo) {
                    foreach (var o in RECIENTES_VALORES) { if (o >= v) { ajustado = o; break; } }
                    if (ajustado < v) ajustado = RECIENTES_VALORES[RECIENTES_VALORES.length - 1];
                } else {
                    for (int i = RECIENTES_VALORES.length - 1; i >= 0; i--) { if (RECIENTES_VALORES[i] <= v) { ajustado = RECIENTES_VALORES[i]; break; } }
                }
                previo = ajustado;
                if (ajustado != v) {
                    spin.set_value (ajustado);
                    return;
                }
                poner_recientes (ajustado);
            });
            rec.pack_start (spin, false, false, 0);
            rec.pack_start (new Gtk.Label ("Documents, Apps, and Servers"), false, false, 0);
            if (archivos_applet_recientes ().length > 0) {
                g.attach (rec, 1, fila, 2, 1);
            } else {
                g.attach (gris_motivo (rec, "The Apple menu is not set up on this computer."), 1, fila, 2, 1);
            }
            fila++;
            // Handoff es de Apple: en gris (perfiles/adaptaciones.json aún no lo oculta). El suavizado de fuentes sí tiene claves.
            var handoff = new Gtk.CheckButton.with_label ("Allow Handoff between this Mac and your iCloud devices");
            handoff.active = true;
            g.attach (gris (handoff), 1, fila, 2, 1);
            fila++;
            var suavizado = new Gtk.CheckButton.with_label ("Use font smoothing when available");
            var xs_f = abrir_settings ("org.cinnamon.settings-daemon.plugins.xsettings");
            if (xs_f != null) {
                suavizado.active = xs_f.get_string ("antialiasing") != "none";
                suavizado.toggled.connect (() => poner_suavizado (suavizado.active));
                g.attach (suavizado, 1, fila, 2, 1);
            } else {
                suavizado.active = true;
                g.attach (gris (suavizado), 1, fila, 2, 1);
            }
            fila++;

            caja.pack_start (g, false, false, 0);
            caja.show_all ();
            cargando = false;
            return caja;
        }

        /** La miniatura de Appearance con las esquinas redondeadas y, si es la escogida, el aro azul. */
        bool pintar_miniatura (Gtk.DrawingArea area, Cairo.Context cr, string clave) {
            var pb = miniaturas[clave];
            int ancho = area.get_allocated_width (), alto = area.get_allocated_height ();
            double radio = 6;
            cr.new_sub_path ();
            cr.arc (ancho - radio - 2, radio + 2, radio, -1.5708, 0);
            cr.arc (ancho - radio - 2, alto - radio - 2, radio, 0, 1.5708);
            cr.arc (radio + 2, alto - radio - 2, radio, 1.5708, 3.1416);
            cr.arc (radio + 2, radio + 2, radio, 3.1416, 4.7124);
            cr.close_path ();
            if (pb != null) {
                cr.save ();
                cr.clip_preserve ();
                Gdk.cairo_set_source_pixbuf (cr, pb, (ancho - pb.get_width ()) / 2.0, (alto - pb.get_height ()) / 2.0);
                cr.paint ();
                cr.restore ();
            }
            var r = radios[clave];
            if (r != null && r.active) {
                cr.set_source_rgb (0.0, 0.48, 1.0);
                cr.set_line_width (2);
                cr.stroke ();
            } else {
                cr.new_path ();
            }
            return false;
        }

        // ── scroll bars ──────────────────────────────────────────────────
        void poner_overlay (bool si) {
            if (cargando || prueba || cfg == null) {
                return;
            }
            cfg.set_boolean ("gtk-overlay-scrollbars", si);
        }

        // ── Default web browser ──────────────────────────────────────────
        static GenericArray<AppInfo> navegadores () {
            var vistos = new HashTable<string, bool> (str_hash, str_equal);
            var lista = new GenericArray<AppInfo> ();
            foreach (var app in AppInfo.get_all_for_type ("x-scheme-handler/https")) {
                if (!vistos.contains (app.get_id ()) && app.should_show ()) {
                    vistos[app.get_id ()] = true;
                    lista.add (app);
                }
            }
            lista.sort ((a, b) => strcmp (a.get_display_name ().down (), b.get_display_name ().down ()));
            return lista;
        }

        static string navegador_actual () {
            return salida_de ({ "xdg-settings", "get", "default-web-browser" });
        }

        void poner_navegador (string? ident) {
            if (cargando || prueba || ident == null || ident == "") {
                return;
            }
            try {
                var p = new Subprocess (SubprocessFlags.NONE, "xdg-settings", "set", "default-web-browser", ident);
                p.wait ();
            } catch (Error e) {
            }
        }
    }
}
