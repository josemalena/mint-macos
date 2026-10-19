/*
 * Keyboard: el panel de Catalina con sus cinco pestañas (Keyboard, Text, Shortcuts, Input Sources, Dictation) y la hoja de Modifier Keys
 * (port de settings/teclado.py).
 *
 * El diseño sale de las capturas de Catalina: Screen Shot 2026-10-14 at 12.13.25 AM (Shortcuts), 12.13.29 (Keyboard), 12.13.34 (Text),
 * 12.13.39 (Input Sources), 12.13.42 (Dictation) y 1.14.37 PM (Modifier Keys).
 *
 * Lo que Linux sabe hacer se conecta de verdad: Key Repeat y Delay Until Repeat (org.cinnamon.desktop.peripherals.keyboard), el atajo de
 * Spotlyte, las distribuciones (org.gnome.libgnomekbd.keyboard) y Modifier Keys (keyd, por un ayudante de root con polkit, como Startup
 * Disk). Lo que no tiene equivalente (Text, Dictation, el visor de emojis) se dibuja como en la captura pero en gris, como en una Mac sin
 * esa función.
 */
namespace Preferencias {

    // ── el teclado dibujado de Input Sources ────────────────────────────────
    // Medido en la captura de Catalina (08-pref-com.apple.preference.keyboard--InputSources): cuerpo #424242, teclas con letra #6d6d6d con la
    // letra #e8e8e8, teclas sin nombre #525252 (fila de arriba y modificadoras), paso de 20 px y tecla de 15. Las letras salen del teclado
    // real de cada distribución (Gdk.Keymap), no de una tabla.
    class DibujoTeclado : Gtk.DrawingArea {
        int grupo = 0;

        public DibujoTeclado () {
            set_size_request (300, 120);
        }

        public void poner (int g) {
            grupo = g;
            queue_draw ();
        }

        static string muerta (string nombre) {
            switch (nombre) {
            case "dead_acute": return "´";
            case "dead_grave": return "`";
            case "dead_diaeresis": return "¨";
            case "dead_circumflex": return "^";
            case "dead_tilde": return "~";
            }
            return "";
        }

        /** Lo que escribe la tecla (sin Shift) en el grupo de distribución dado, o «». */
        string letra (int codigo) {
            var mapa = Gdk.Keymap.get_for_display (Gdk.Display.get_default ());
            uint valor;
            int efectivo, nivel;
            Gdk.ModifierType consumidos;
            // El símbolo de la tecla en ese grupo, nivel 0 (sin Shift ni AltGr).
            if (!mapa.translate_keyboard_state (codigo, 0, grupo, out valor, out efectivo, out nivel, out consumidos) || valor == 0) {
                return "";
            }
            var nombre = Gdk.keyval_name (valor) ?? "";
            var m = muerta (nombre);
            if (m != "") {
                return m;
            }
            var c = Gdk.keyval_to_unicode (valor);
            return c != 0 ? ((unichar) c).to_string () : "";
        }

        void caja (Cairo.Context cr, double x, double y, double ancho_t, double alto_t, double gris, double r = 2.5) {
            cr.new_sub_path ();
            cr.arc (x + ancho_t - r, y + r, r, -1.5708, 0);
            cr.arc (x + ancho_t - r, y + alto_t - r, r, 0, 1.5708);
            cr.arc (x + r, y + alto_t - r, r, 1.5708, 3.1416);
            cr.arc (x + r, y + r, r, 3.1416, 4.7124);
            cr.close_path ();
            cr.set_source_rgb (gris / 255.0, gris / 255.0, gris / 255.0);
            cr.fill ();
        }

        public override bool draw (Cairo.Context cr) {
            int ancho = get_allocated_width ();
            double ox = (ancho - 289) / 2.0, oy = 6, ancho_c = 289, alto_c = 111;
            caja (cr, ox, oy, ancho_c, alto_c, 66, 4);
            for (int i = 0; i < 14; i++) {                                         // la fila de arriba, sin nombres
                caja (cr, ox + 4 + i * 20.2, oy + 4, 18, 7.5, 82, 2);
            }
            // (x del primer paso, [códigos de tecla]) por fila; la fila 0 de la captura son diez teclas sin nombre
            double[] x0s = { 3.75, 31.75, 37.75, 47.75 };
            int[,] codigos = {
                { 49, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21 },
                { 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 51 },
                { 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 0, 0 },
                { 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0, 0, 0 }
            };
            int[] cuantos = { 13, 13, 11, 10 };
            for (int fila = 0; fila < 4; fila++) {
                double y = oy + 15.5 + fila * 19.5;
                for (int i = 0; i < cuantos[fila]; i++) {
                    double x = ox + x0s[fila] + i * 20;
                    caja (cr, x, y, 15, 14, 109);
                    var l = letra (codigos[fila, i]);
                    if (l != "") {
                        cr.set_source_rgb (232 / 255.0, 232 / 255.0, 232 / 255.0);
                        cr.select_font_face (".SF NS", Cairo.FontSlant.NORMAL, Cairo.FontWeight.BOLD);
                        cr.set_font_size (9.5);
                        Cairo.TextExtents e;
                        cr.text_extents (l, out e);
                        cr.move_to (x + 7.5 - e.width / 2 - e.x_bearing, y + 7 - e.height / 2 - e.y_bearing);
                        cr.show_text (l);
                    }
                }
            }
            // las teclas de los bordes y la barra de abajo, sin nombre
            double[,] bordes = { { 3.75, 15.5, 15 }, { 221.8, 15.5, 25 }, { 3.75, 35, 25 }, { 3.75, 54.5, 30 }, { 240.5, 54.5, 41 },
                                 { 3.75, 74, 40 }, { 250, 74, 31 }, { 3.75, 93.5, 15 }, { 23, 93.5, 15 }, { 43, 93.5, 15 },
                                 { 62, 93.5, 23 }, { 86, 93.5, 97 }, { 186, 93.5, 20 }, { 211, 93.5, 15 } };
            for (int i = 0; i < 14; i++) {
                caja (cr, ox + bordes[i, 0], oy + bordes[i, 1] - 0.5, bordes[i, 2], 14.5, 82);
            }
            return false;
        }
    }

    /** Una fila de la lista de atajos: o un atajo (4 datos) o un grupo (con su estado). */
    class FilaAtajo {
        public string titulo;
        public string? atajo;
        public int marcada;          // 1 sí, 0 no, 2 sin casilla
        public int nivel;
        public bool grupo;
        public int estado;           // del grupo: 1, 0 o -1 (mixto); 2 sin casilla
        public FilaAtajo.atajo_fila (string t, string a, int m, int n) {
            titulo = t;
            atajo = a;
            marcada = m;
            nivel = n;
            grupo = false;
            estado = 2;
        }
        public FilaAtajo.grupo_fila (string t, int e, int n) {
            titulo = t;
            atajo = null;
            marcada = 2;
            nivel = n;
            grupo = true;
            estado = e;
        }
    }

    /** Un atajo de App Shortcuts: «con este atajo, activa el comando de menú con este nombre en esa app». */
    class AtajoApp : Object {
        public string app = "*";         // «*» (All Applications) o el id del .desktop
        public string nombre_app = "All Applications";
        public string titulo = "";
        public string atajo = "";        // «⇧⌘P»: ⌘ es Ctrl con keyd

        public static string ruta () {
            return Environment.get_variable ("MINT_ATAJOS_APPS")
                ?? Path.build_filename (Environment.get_user_config_dir (), "mint-macos", "atajos-apps.json");
        }

        public static GenericArray<AtajoApp> cargar () {
            var lista = new GenericArray<AtajoApp> ();
            try {
                var p = new Json.Parser ();
                p.load_from_file (ruta ());
                var raiz = p.get_root ().get_object ();
                if (!raiz.has_member ("atajos")) return lista;
                foreach (var e in raiz.get_array_member ("atajos").get_elements ()) {
                    var o = e.get_object ();
                    var a = new AtajoApp ();
                    a.app = o.get_string_member ("app");
                    a.nombre_app = o.has_member ("nombre") ? o.get_string_member ("nombre") : a.app;
                    a.titulo = o.get_string_member ("titulo");
                    a.atajo = o.get_string_member ("atajo");
                    lista.add (a);
                }
            } catch (GLib.Error e) {
            }
            return lista;
        }

        public static void guardar (GenericArray<AtajoApp> lista) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("version").add_int_value (1);
            b.set_member_name ("atajos").begin_array ();
            for (int i = 0; i < lista.length; i++) {
                b.begin_object ();
                b.set_member_name ("app").add_string_value (lista[i].app);
                b.set_member_name ("nombre").add_string_value (lista[i].nombre_app);
                b.set_member_name ("titulo").add_string_value (lista[i].titulo);
                b.set_member_name ("atajo").add_string_value (lista[i].atajo);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            var g = new Json.Generator ();
            g.root = b.get_root ();
            g.pretty = true;
            try {
                DirUtils.create_with_parents (Path.get_dirname (ruta ()), 0755);
                FileUtils.set_contents (ruta (), g.to_data (null));
            } catch (GLib.Error e) {
                warning ("atajos-apps: %s", e.message);
            }
        }
    }

    class FilaUsuario : Gtk.ListBoxRow {
        public AtajoApp atajo;
        public FilaUsuario (AtajoApp a) {
            atajo = a;
        }
    }

    class FilaCategoria : Gtk.ListBoxRow {
        public string nombre_cat = "";
    }

    public class PanelKeyboard : Panel {
        // Los pasos de los dos sliders son los de Catalina, en milisegundos (KeyRepeat 120, 90, 60, 30, 12, 6, 2 y InitialKeyRepeat 120, 94, 68, 35, 25,
        // 15, por 15 ms).
        const int[] INTERVALOS = { 1800, 1350, 900, 450, 180, 90, 30 };        // Key Repeat: de «Slow» a «Fast»
        const int[] RETARDOS = { 1800, 1410, 1020, 525, 375, 225 };            // Delay Until Repeat: de «Long» a «Short»
        // Modifier Keys: las teclas que se pueden reasignar y lo que puede hacer cada una.
        const string[] TECLAS = { "capslock", "control", "option", "command" };
        const string[] TECLAS_TXT = { "Caps Lock (⇪) Key:", "Control (⌃) Key:", "Option (⌥) Key:", "Command (⌘) Key:" };
        const string[] ACCIONES = { "capslock", "control", "option", "command", "escape", "none" };
        const string[] ACCIONES_TXT = { "⇪ Caps Lock", "⌃ Control", "⌥ Option", "⌘ Command", "⎋ Escape", "No Action" };
        const string AYUDANTE = "/usr/libexec/mint-macos/modifier-keys";
        const string CONF_KEYD = "/etc/keyd/default.conf";
        const string BLOQUE_INICIO = "# >>> mint-macos modifier-keys (lo escribe System Preferences; no lo edites a mano)";
        const string BLOQUE_FIN = "# <<< mint-macos modifier-keys";
        // Para probar sin tocar el sistema: MINT_TECLADO_PRUEBA=1 no escribe en keyd ni en gsettings.
        bool prueba = Environment.get_variable ("MINT_TECLADO_PRUEBA") != null;
        bool cargando = false;

        public PanelKeyboard () {
            id = "com.apple.preference.keyboard";
            nombre = "Keyboard";
            palabras = "keyboard, key repeat, delay, shortcuts, modifier keys, caps lock, input sources, layout, text, dictation";
        }

        /** Un slider de Catalina: una marca por paso y, debajo, los extremos («Slow … Fast»). */
        static Gtk.Scale escala_pasos (int pasos, int indice, string pie_izq, string pie_der, owned EscalaCambio al_cambiar,
                                       bool con_apagado = false, string? pie_segundo = null) {
            int n = pasos + (con_apagado ? 1 : 0);
            var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, n - 1, 1);
            esc.draw_value = false;
            esc.round_digits = 0;
            esc.set_value (indice);
            esc.set_size_request (150, -1);
            for (int i = 0; i < n; i++) {
                esc.add_mark (i, Gtk.PositionType.BOTTOM, null);
            }
            if (pie_segundo != null) {
                esc.add_mark (1, Gtk.PositionType.BOTTOM, pie_segundo);
            }
            esc.add_mark (0, Gtk.PositionType.BOTTOM, pie_izq);
            esc.add_mark (n - 1, Gtk.PositionType.BOTTOM, pie_der);
            esc.value_changed.connect (() => al_cambiar ((int) Math.rint (esc.get_value ())));
            return esc;
        }

        static Gtk.Widget gris_k (Gtk.Widget w, string? motivo = null) {
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
            var stack = new Gtk.Stack ();
            stack.add_titled (pagina_teclado (), "keyboard", "Keyboard");
            stack.add_titled (pagina_texto (), "text", "Text");
            stack.add_titled (pagina_atajos (), "shortcuts", "Shortcuts");
            stack.add_titled (pagina_fuentes (), "sources", "Input Sources");
            stack.add_titled (pagina_dictado (), "dictation", "Dictation");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var bt = new Gtk.Button.with_label ("Set Up Bluetooth Keyboard…");
            bt.clicked.connect (() => bluetooth ());
            pie.pack_end (bt, false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_TECLADO_PESTANA");      // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            if (Environment.get_variable ("MINT_TECLADO_HOJA") != null) {         // idem: abre la hoja de Modifier Keys
                Timeout.add (4000, () => { hoja_modificadoras (); return false; });
            }
            cargando = false;
            return caja;
        }

        /** Emparejar un teclado: la ventana de Bluetooth (blueman), que busca dispositivos nuevos. */
        void bluetooth () {
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

        // ── Keyboard ─────────────────────────────────────────────────────
        static int mas_cercano (int[] pasos, uint valor) {
            int mejor = 0;
            double dist = double.MAX;
            for (int i = 0; i < pasos.length; i++) {
                double d = Math.fabs ((double) pasos[i] - (double) valor);
                if (d < dist) {
                    dist = d;
                    mejor = i;
                }
            }
            return mejor;
        }

        Gtk.Widget pagina_teclado () {
            var cfg = abrir_settings ("org.cinnamon.desktop.peripherals.keyboard");
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            pagina.margin_top = 22;
            pagina.margin_start = 24;
            pagina.margin_end = 24;

            var sliders = new Gtk.Grid ();
            sliders.column_spacing = 40;
            sliders.row_spacing = 4;
            sliders.halign = Gtk.Align.CENTER;
            // Key Repeat: 0 es «Off» y de 1 a 7 los intervalos de más lento a más rápido.
            bool repite = cfg != null && cfg.get_boolean ("repeat");
            int pos_repeticion = (!repite || cfg == null) ? 0 : 1 + mas_cercano (INTERVALOS, cfg.get_uint ("repeat-interval"));
            int pos_retardo = cfg != null ? RETARDOS.length - 1 - mas_cercano (RETARDOS, cfg.get_uint ("delay")) : 0;
            var s1 = escala_pasos (INTERVALOS.length, pos_repeticion, "Off", "Fast", (i) => {
                if (cargando || prueba || cfg == null) {
                    return;
                }
                cfg.set_boolean ("repeat", i > 0);
                if (i > 0) {
                    cfg.set_uint ("repeat-interval", (uint) INTERVALOS[i - 1]);
                }
            }, true, "Slow");
            var s2 = escala_pasos (RETARDOS.length, pos_retardo, "Long", "Short", (i) => {
                if (cargando || prueba || cfg == null) {
                    return;
                }
                cfg.set_uint ("delay", (uint) RETARDOS[RETARDOS.length - 1 - i]);
            });
            sliders.attach (new Gtk.Label ("Key Repeat"), 0, 0, 1, 1);
            sliders.attach (s1, 0, 1, 1, 1);
            sliders.attach (new Gtk.Label ("Delay Until Repeat"), 1, 0, 1, 1);
            sliders.attach (s2, 1, 1, 1, 1);
            pagina.pack_start (sliders, false, false, 0);

            var visores = new Gtk.CheckButton.with_label ("Show keyboard and emoji viewers in menu bar");
            gris_k (visores, "There is no keyboard or emoji viewer to show on this computer.");
            visores.margin_top = 6;
            visores.margin_bottom = 6;
            pagina.pack_start (visores, false, false, 0);

            pagina.pack_start (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), true, true, 0);
            var mod = new Gtk.Button.with_label ("Modifier Keys…");
            mod.clicked.connect (() => hoja_modificadoras ());
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            fila.pack_end (mod, false, false, 0);
            fila.margin_top = 14;
            fila.margin_bottom = 14;
            pagina.pack_start (fila, false, false, 0);
            return pagina;
        }

        // ── Text: sin equivalente en Linux, en gris ──────────────────────
        Gtk.Widget pagina_texto () {
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            pagina.margin_top = 22;
            pagina.margin_start = 24;
            pagina.margin_end = 24;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var lista = new Gtk.ListStore (2, typeof (string), typeof (string));
            var arbol = new Gtk.TreeView.with_model (lista);
            string[] titulos = { "Replace", "With" };
            for (int i = 0; i < 2; i++) {
                var col = new Gtk.TreeViewColumn.with_attributes (titulos[i], new Gtk.CellRendererText (), "text", i, null);
                col.expand = true;
                arbol.append_column (col);
            }
            var marco = marco_lista ();
            marco.add (arbol);
            marco.set_size_request (360, 320);
            izq.pack_start (gris_k (marco, "Text replacement is not available on this computer."), true, true, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var t in new string[] { "+", "−" }) {
                botones.pack_start (gris (new Gtk.Button.with_label (t)), false, false, 0);
            }
            izq.pack_start (botones, false, false, 0);
            pagina.pack_start (izq, false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            string[] textos = { "Correct spelling automatically", "Capitalize words automatically", "Add period with double-space" };
            bool[] activos = { false, true, true };
            for (int i = 0; i < 3; i++) {
                var c = new Gtk.CheckButton.with_label (textos[i]);
                c.active = activos[i];
                der.pack_start (gris (c), false, false, 0);
            }
            var sp = new Gtk.Label ("Spelling:");
            sp.xalign = 0;
            sp.margin_top = 8;
            sp.margin_bottom = 8;
            der.pack_start (sp, false, false, 0);
            var ortografia = new Gtk.ComboBoxText ();
            ortografia.append ("auto", "Automatic by Language");
            ortografia.set_active (0);
            der.pack_start (gris (ortografia), false, false, 0);
            var inteligentes = new Gtk.CheckButton.with_label ("Use smart quotes and dashes");
            inteligentes.active = true;
            inteligentes.margin_top = 8;
            inteligentes.margin_bottom = 8;
            der.pack_start (gris (inteligentes), false, false, 0);
            string[] ft = { "for Double Quotes", "for Single Quotes" };
            string[] fv = { "“abc”", "‘abc’" };
            for (int i = 0; i < 2; i++) {
                var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                var l = new Gtk.Label (ft[i]);
                l.xalign = 0;
                f.pack_start (l, false, false, 0);
                var c = new Gtk.ComboBoxText ();
                c.append ("v", fv[i]);
                c.set_active (0);
                f.pack_end (gris (c), false, false, 0);
                der.pack_start (f, false, false, 0);
            }
            pagina.pack_start (der, false, false, 0);
            return pagina;
        }

        // ── Shortcuts ────────────────────────────────────────────────────
        // Las diez categorías y sus filas, tal como salen en Catalina (08-pref-keyboard-shortcuts-1…10): marca, título y atajo. Solo Spotlight es
        // real (el atajo de Spotlyte); lo demás se dibuja en gris. Services y Accessibility traen en la Mac una lista que se desplaza: aquí solo van
        // las filas que se ven completas.
        static FilaAtajo a (string t, string at, int m, int n) {
            return new FilaAtajo.atajo_fila (t, at, m, n);
        }

        static FilaAtajo g (string t, int e, int n) {
            return new FilaAtajo.grupo_fila (t, e, n);
        }

        static FilaAtajo[] filas_de (string categoria) {
            switch (categoria) {
            case "Launchpad & Dock":
                return { a ("Turn Dock Hiding On/Off", "⌥⌘D", 1, 0), a ("Show Launchpad", "⌥⌘L", 1, 0) };
            case "Display":
                return { a ("Decrease display brightness", "F14", 1, 0), a ("Increase display brightness", "F15", 1, 0) };
            case "Mission Control":
                return { a ("Mission Control", "⌃↑", 1, 0), a ("Show Notification Center", "none", 0, 0),
                         a ("Turn Do Not Disturb On/Off", "none", 1, 0), a ("Application windows", "⌃↓", 1, 0),
                         a ("Show Desktop", "F11", 0, 0),
                         g ("▾ Mission Control", -1, 0),
                         a ("Move left a space", "⌃←", 1, 1), a ("Move right a space", "⌃→", 1, 1),
                         a ("Switch to Desktop 1", "⌃1", 0, 1) };
            case "Keyboard":
                return { a ("Change the way Tab moves focus", "⌃F7", 1, 0), a ("Turn keyboard access on or off", "⌃F1", 1, 0),
                         a ("Move focus to the menu bar", "⌃F2", 1, 0), a ("Move focus to the Dock", "⌃F3", 1, 0),
                         a ("Move focus to active or next window", "⌃F4", 1, 0),
                         a ("Move focus to the window toolbar", "⌃F5", 1, 0),
                         a ("Move focus to the floating window", "⌃F6", 1, 0),
                         a ("Move focus to next window", "⌘`", 1, 0),
                         a ("Move focus to the window drawer", "⌥⌘'", 1, 0),
                         a ("Move focus to status menus", "⌃F8", 1, 0) };
            case "Input Sources":
                return { a ("Select the previous input source", "⌃Space", 1, 0),
                         a ("Select next source in Input menu", "⌃⌥Space", 0, 0) };
            case "Screenshots":
                return { a ("Save picture of screen as a file", "⇧⌘3", 1, 0),
                         a ("Copy picture of screen to the clipboard", "⌃⇧⌘3", 1, 0),
                         a ("Save picture of selected area as a file", "⇧⌘4", 1, 0),
                         a ("Copy picture of selected area to the clipboard", "⌃⇧⌘4", 1, 0),
                         a ("Screenshot and recording options", "⇧⌘5", 1, 0) };
            case "Services":
                return { g ("▾ Pictures", 1, 0), a ("Import Image", "none", 1, 1), a ("Set Desktop Picture", "none", 1, 1),
                         g ("▾ Messaging", 1, 0), a ("New Email To Address", "none", 1, 1),
                         a ("New Email With Selection", "none", 1, 1),
                         g ("▾ Development", 0, 0), a ("Create Service", "none", 0, 1),
                         a ("Create Workflow", "none", 0, 1), a ("Get Result of AppleScript", "⌘*", 0, 1),
                         a ("Make New AppleScript", "none", 0, 1) };
            case "Accessibility":
                return { g ("▾ Zoom", 0, 0), a ("Turn zoom on or off", "⌥⌘8", 2, 1),
                         a ("Turn image smoothing on or off", "⌥⌘\\", 2, 1),
                         a ("Zoom out", "⌥⌘−", 2, 1), a ("Zoom in", "⌥⌘=", 2, 1),
                         a ("Turn focus following on or off", "none", 2, 1),
                         g ("▾ Contrast", 0, 0), a ("Increase contrast", "^⌥⌘.", 2, 1),
                         a ("Decrease contrast", "^⌥⌘,", 2, 1),
                         a ("Invert colors", "^⌥⌘8", 0, 0), a ("Turn VoiceOver on or off", "⌘F5", 1, 0) };
            case "App Shortcuts":
                return { g ("▾ All Applications", 2, 0), a ("Show Help menu", "⇧⌘/", 1, 1) };
            }
            return {};
        }

        Gtk.Widget pagina_atajos () {
            string[] categorias_n = { "Launchpad & Dock", "Display", "Mission Control", "Keyboard", "Input Sources", "Screenshots",
                                      "Services", "Spotlight", "Accessibility", "App Shortcuts" };
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            pagina.margin_top = 14;
            pagina.margin_start = 20;
            pagina.margin_end = 20;
            var ay = new Gtk.Label ("To change a shortcut, select it, click the key combination, and then type the new keys.");
            ay.xalign = 0;
            pagina.pack_start (ay, false, false, 0);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var categorias = new Gtk.ListBox ();
            categorias.set_size_request (170, 240);
            var derecha = new Gtk.Stack ();
            foreach (var n in categorias_n) {
                var fila = new FilaCategoria ();
                fila.add (fila_categoria (n));
                fila.nombre_cat = n;
                categorias.add (fila);
                derecha.add_named (pagina_de (n), n);
            }
            categorias.row_selected.connect ((f) => {
                var fc = f as FilaCategoria;
                if (fc != null) {
                    derecha.set_visible_child_name (fc.nombre_cat);
                }
            });
            var m1 = marco_lista ();
            m1.add (categorias);
            cuerpo.pack_start (m1, false, false, 0);
            cuerpo.pack_start (derecha, true, true, 0);
            pagina.pack_start (cuerpo, true, true, 0);
            derecha.show_all ();      // Gtk.Stack solo cambia a una página que ya es visible
            categorias.select_row (categorias.get_row_at_index (0));
            derecha.set_visible_child_name (categorias_n[0]);

            var nav = new Gtk.CheckButton.with_label ("Use keyboard navigation to move focus between controls");
            gris_k (nav, "Tab and Shift Tab already move the focus between controls.");
            pagina.pack_start (nav, false, false, 0);
            var tab = new Gtk.Label ("Press the Tab key to move focus forward and Shift Tab to move focus backward.");
            tab.xalign = 0;
            pagina.pack_start (tab, false, false, 0);
            return pagina;
        }

        static string icono_categoria (string n) {
            switch (n) {
            case "Launchpad & Dock": return "dock";
            case "Display": return "display";
            case "Mission Control": return "expose";
            case "Keyboard": return "keyboard";
            case "Input Sources": return "keyboard";
            case "Screenshots": return "screenshots";
            case "Services": return "services";
            case "Spotlight": return "spotlight";
            case "Accessibility": return "ua";
            case "App Shortcuts": return "appshortcuts";
            }
            return "";
        }

        Gtk.Widget fila_categoria (string n) {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            caja.margin = 4;
            var icono = IconosCatalina.de_atajos (icono_categoria (n), 16);
            if (icono != null) {
                caja.pack_start (icono, false, false, 0);
            }
            var l = new Gtk.Label (n);
            l.xalign = 0;
            caja.pack_start (l, true, true, 0);
            return caja;
        }

        /** La lista de una categoría con su pie: Restore Defaults, o + y − en App Shortcuts. */
        Gtk.Widget pagina_de (string categoria) {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            var marco = marco_lista ();
            var desplazable = new Gtk.ScrolledWindow (null, null);
            desplazable.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            desplazable.set_size_request (-1, 240);
            desplazable.add (atajos_de (categoria));
            marco.add (desplazable);
            caja.pack_start (marco, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            if (categoria == "App Shortcuts") {
                var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                botones.get_style_context ().add_class ("linked");
                var mas = new Gtk.Button.with_label ("+");
                mas.clicked.connect (() => { if (hoja_nuevo_atajo ()) rellenar_apps (); });
                botones.pack_start (mas, false, false, 0);
                boton_menos = new Gtk.Button.with_label ("−");
                boton_menos.sensitive = false;
                boton_menos.clicked.connect (quitar_atajo_app);
                botones.pack_start (boton_menos, false, false, 0);
                pie.pack_start (botones, false, false, 0);
            } else {
                pie.pack_end (gris (new Gtk.Button.with_label ("Restore Defaults")), false, false, 0);
            }
            pie.margin_top = 4;
            pie.margin_bottom = 4;
            caja.pack_start (pie, false, false, 0);
            return caja;
        }

        Gtk.Widget fila_atajo (string titulo, string? atajo, int marcada, int nivel, int grupo_estado = 2) {
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            fila.margin = 5;
            fila.margin_start = 6 + 22 * nivel;
            if (marcada != 2 || grupo_estado != 2) {
                var marca = new Gtk.CheckButton ();
                if (grupo_estado == -1) {
                    marca.inconsistent = true;
                } else {
                    marca.active = grupo_estado == 2 ? marcada == 1 : grupo_estado == 1;
                }
                fila.pack_start (gris (marca), false, false, 0);
            } else {
                fila.pack_start (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), false, false, 12);
            }
            var etiqueta = new Gtk.Label (titulo);
            etiqueta.xalign = 0;
            etiqueta.ellipsize = Pango.EllipsizeMode.MIDDLE;       // «Copy picture of sel…area to the clipboard»
            fila.pack_start (etiqueta, true, true, 0);
            if (atajo != null) {
                var derecha = new Gtk.Label (atajo);
                if (atajo == "none") {
                    derecha.get_style_context ().add_class ("mp-sd-detalle");
                }
                fila.pack_end (derecha, false, false, 6);
            }
            return fila;
        }

        Gtk.ListBox? lista_apps = null;
        Gtk.Button? boton_menos = null;

        /** App Shortcuts: «All Applications» con lo que viene de fábrica (en gris) y los atajos que armó la persona, por app. */
        Gtk.Widget lista_app_shortcuts () {
            lista_apps = new Gtk.ListBox ();
            lista_apps.set_selection_mode (Gtk.SelectionMode.SINGLE);
            lista_apps.row_selected.connect ((fila) => {
                if (boton_menos != null) boton_menos.sensitive = fila is FilaUsuario;
            });
            rellenar_apps ();
            return lista_apps;
        }

        void rellenar_apps () {
            foreach (var h in lista_apps.get_children ()) lista_apps.remove (h);
            lista_apps.add (fila_atajo ("▾ All Applications", null, 2, 0, 2));
            var de_fabrica = fila_atajo ("Show Help menu", "⇧⌘/", 1, 1);
            gris_k (de_fabrica, "This shortcut is not available on this computer.");
            lista_apps.add (de_fabrica);
            var todos = AtajoApp.cargar ();
            // por app: primero All Applications, luego las demás en orden de aparición
            var apps = new GenericArray<string> ();
            apps.add ("*");
            for (int i = 0; i < todos.length; i++) {
                bool ya = false;
                for (int k = 0; k < apps.length; k++) if (apps[k] == todos[i].app) ya = true;
                if (!ya) apps.add (todos[i].app);
            }
            for (int k = 0; k < apps.length; k++) {
                bool grupo_puesto = apps[k] == "*";
                for (int i = 0; i < todos.length; i++) {
                    if (todos[i].app != apps[k]) continue;
                    if (!grupo_puesto) {
                        lista_apps.add (fila_atajo ("▾ " + todos[i].nombre_app, null, 2, 0, 2));
                        grupo_puesto = true;
                    }
                    var fila = new FilaUsuario (todos[i]);
                    fila.add (fila_atajo (todos[i].titulo, todos[i].atajo, 2, 1));
                    lista_apps.add (fila);
                }
            }
            lista_apps.show_all ();
        }

        void quitar_atajo_app () {
            var fila = lista_apps.get_selected_row () as FilaUsuario;
            if (fila == null) return;
            var todos = AtajoApp.cargar ();
            for (int i = 0; i < todos.length; i++) {
                if (todos[i].app == fila.atajo.app && todos[i].titulo == fila.atajo.titulo && todos[i].atajo == fila.atajo.atajo) {
                    todos.remove_index (i);
                    break;
                }
            }
            AtajoApp.guardar (todos);
            rellenar_apps ();
        }

        /** La combinación que se oprimió, escrita como en la Mac (⌃⌥⇧⌘ y la tecla); «» si no es una combinación. Con keyd, ⌘ llega como
         *  Ctrl (o como Super si no tiene regla) y ⌃⌘ como Ctrl+Super: Ctrl o Super solos cuentan como ⌘. */
        static string combinacion_mac (Gdk.EventKey ev) {
            uint k = ev.keyval;
            if (k == Gdk.Key.Control_L || k == Gdk.Key.Control_R || k == Gdk.Key.Shift_L || k == Gdk.Key.Shift_R
                || k == Gdk.Key.Alt_L || k == Gdk.Key.Alt_R || k == Gdk.Key.Super_L || k == Gdk.Key.Super_R
                || k == Gdk.Key.Meta_L || k == Gdk.Key.Meta_R || k == Gdk.Key.ISO_Level3_Shift) return "";
            bool ctrl = (ev.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool sup = (ev.state & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.META_MASK)) != 0;
            bool alt = (ev.state & Gdk.ModifierType.MOD1_MASK) != 0;
            bool mayus = (ev.state & Gdk.ModifierType.SHIFT_MASK) != 0;
            var nombre = Gdk.keyval_name (Gdk.keyval_to_lower (k)) ?? "";
            string tecla;
            if (nombre.has_prefix ("F") && nombre.length <= 3 && int.parse (nombre.substring (1)) > 0) {
                tecla = nombre;
            } else {
                switch (nombre) {
                case "space": tecla = "Space"; break;
                case "Return": tecla = "↩"; break;
                case "Tab": case "ISO_Left_Tab": tecla = "⇥"; break;
                case "Escape": tecla = "⎋"; break;
                case "BackSpace": tecla = "⌫"; break;
                case "Delete": tecla = "⌦"; break;
                case "Left": tecla = "←"; break;
                case "Right": tecla = "→"; break;
                case "Up": tecla = "↑"; break;
                case "Down": tecla = "↓"; break;
                default:
                    unichar u = Gdk.keyval_to_unicode (Gdk.keyval_to_lower (k));
                    if (u < 33) return "";
                    tecla = u.to_string ().up ();
                    break;
                }
            }
            // sin ningún modificador solo valen las teclas de función
            if (!ctrl && !sup && !alt && !mayus && !tecla.has_prefix ("F")) return "";
            var sb = new StringBuilder ();
            if (ctrl && sup) sb.append ("⌃");
            if (alt) sb.append ("⌥");
            if (mayus) sb.append ("⇧");
            if (ctrl || sup) sb.append ("⌘");
            sb.append (tecla);
            return sb.str;
        }

        /** ¿Ya lo usa otra acción? Las de las listas de Shortcuts y las que la persona ya armó para esa app o para todas. */
        bool atajo_en_uso (string atajo, string app) {
            foreach (var cat in new string[] { "Launchpad & Dock", "Display", "Mission Control", "Keyboard", "Screenshots", "Services",
                                                "Spotlight", "Accessibility" }) {
                foreach (var d in filas_de (cat)) {
                    if (!d.grupo && d.atajo == atajo) return true;
                }
            }
            if (atajo == "⌥⌘Space" || atajo == "⌘Space") return true;
            var todos = AtajoApp.cargar ();
            for (int i = 0; i < todos.length; i++) {
                if (todos[i].atajo == atajo && (todos[i].app == app || todos[i].app == "*" || app == "*")) return true;
            }
            return false;
        }

        /** La hoja de «+»: Application, Menu Title y Keyboard Shortcut (el nib de Keyboard, ventana de 408×195). */
        bool hoja_nuevo_atajo () {
            var d = new Gtk.Dialog ();
            d.transient_for = ventana;
            d.modal = true;
            d.set_decorated (false);
            d.get_style_context ().add_class ("mp-hoja");
            var caja = d.get_content_area () as Gtk.Box;
            margenes (caja, 18, 18, 18, 18);
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 10;
            var etiquetas = new string[] { "Application:", "Menu Title:", "", "Keyboard Shortcut:" };
            for (int i = 0; i < etiquetas.length; i++) {
                if (etiquetas[i] == "") continue;
                var l = etiqueta_fila (etiquetas[i]);
                g.attach (l, 0, i, 1, 1);
            }
            var apps = new Gtk.ComboBoxText ();
            apps.append ("*", "All Applications");
            var vistas = new HashTable<string, string> (str_hash, str_equal);
            var todas = AppInfo.get_all ();
            todas.sort ((a, b) => strcmp (a.get_display_name ().casefold (), b.get_display_name ().casefold ()));
            foreach (var ai in todas) {
                if (!ai.should_show () || ai.get_id () == null) continue;
                apps.append (ai.get_id (), ai.get_display_name ());
                vistas[ai.get_id ()] = ai.get_display_name ();
            }
            apps.append ("other", "Other…");
            apps.set_active_id ("*");
            apps.set_size_request (240, -1);
            g.attach (apps, 1, 0, 1, 1);
            var titulo = new Gtk.Entry ();
            titulo.set_size_request (240, -1);
            g.attach (titulo, 1, 1, 1, 1);
            var ayuda = new Gtk.Label ("Enter the exact name of the menu command you want to add.");
            ayuda.xalign = 0;
            ayuda.set_line_wrap (true);
            ayuda.set_max_width_chars (36);
            ayuda.get_style_context ().add_class ("mp-sd-detalle");
            g.attach (ayuda, 1, 2, 1, 1);
            var atajo = new Gtk.Entry ();
            atajo.editable = false;
            atajo.set_size_request (150, -1);
            atajo.halign = Gtk.Align.START;
            g.attach (atajo, 1, 3, 1, 1);
            var uso = new Gtk.Label ("Shortcut used by another action");
            uso.xalign = 0;
            uso.get_style_context ().add_class ("mp-sd-detalle");
            uso.no_show_all = true;
            g.attach (uso, 1, 4, 1, 1);
            g.margin_bottom = 16;
            caja.pack_start (g, false, false, 0);
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            var anadir = d.add_button ("Add", Gtk.ResponseType.OK);
            anadir.get_style_context ().add_class ("suggested-action");
            d.set_default_response (Gtk.ResponseType.OK);
            anadir.sensitive = false;

            string app_previa = "*";
            void validar () {
                bool en_uso = atajo.text != "" && atajo_en_uso (atajo.text, apps.get_active_id () ?? "*");
                uso.visible = en_uso;
                anadir.sensitive = titulo.text.strip () != "" && atajo.text != "" && !en_uso;
            }
            titulo.changed.connect (() => { validar (); });
            apps.changed.connect (() => {
                if (apps.get_active_id () == "other") {
                    // Other…: un .desktop cualquiera
                    var fc = new Gtk.FileChooserDialog ("Choose an application", d, Gtk.FileChooserAction.OPEN,
                                                        "Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.ACCEPT);
                    var filtro = new Gtk.FileFilter ();
                    filtro.add_pattern ("*.desktop");
                    filtro.set_filter_name ("Applications");
                    fc.add_filter (filtro);
                    fc.set_current_folder ("/usr/share/applications");
                    string? elegido = null;
                    if (fc.run () == Gtk.ResponseType.ACCEPT) {
                        var ai = new DesktopAppInfo.from_filename (fc.get_filename ());
                        if (ai != null && ai.get_id () != null) {
                            elegido = ai.get_id ();
                            if (!vistas.contains (elegido)) {
                                apps.append (elegido, ai.get_display_name ());
                                vistas[elegido] = ai.get_display_name ();
                            }
                        }
                    }
                    fc.destroy ();
                    apps.set_active_id (elegido ?? app_previa);
                }
                app_previa = apps.get_active_id () ?? "*";
                validar ();
            });
            // El atajo se captura oprimiéndolo; Supr o Retroceso lo borran.
            atajo.key_press_event.connect ((ev) => {
                if (ev.keyval == Gdk.Key.BackSpace || ev.keyval == Gdk.Key.Delete) {
                    atajo.text = "";
                    validar ();
                    return true;
                }
                var c = combinacion_mac (ev);
                if (c != "") {
                    atajo.text = c;
                    validar ();
                }
                return true;
            });
            d.show_all ();
            uso.hide ();
            int r = d.run ();
            bool agregado = false;
            if (r == Gtk.ResponseType.OK) {
                var nuevo = new AtajoApp ();
                nuevo.app = apps.get_active_id () ?? "*";
                nuevo.nombre_app = nuevo.app == "*" ? "All Applications" : (vistas[nuevo.app] ?? nuevo.app);
                nuevo.titulo = titulo.text.strip ();
                nuevo.atajo = atajo.text;
                var todos = AtajoApp.cargar ();
                todos.add (nuevo);
                AtajoApp.guardar (todos);
                agregado = true;
            }
            d.destroy ();
            return agregado;
        }

        Gtk.Widget atajos_de (string categoria) {
            if (categoria == "App Shortcuts") return lista_app_shortcuts ();
            var lista = new Gtk.ListBox ();
            lista.set_selection_mode (Gtk.SelectionMode.NONE);
            if (categoria == "Spotlight") {
                var ajuste = new PanelSpotlight ();          // el atajo de Spotlyte es el de ese panel
                var datos = ajuste.leer ();
                string actual = "<Super>space";
                if (datos.has_member ("hotkey-show-app") && datos.get_member ("hotkey-show-app").get_node_type () == Json.NodeType.VALUE) {
                    actual = datos.get_string_member ("hotkey-show-app");
                }
                var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                fila.margin = 6;
                var marca = new Gtk.CheckButton ();
                marca.active = true;
                gris (marca);
                fila.pack_start (marca, false, false, 0);
                var l = new Gtk.Label ("Show Spotlight search");
                l.xalign = 0;
                fila.pack_start (l, true, true, 0);
                var combo = new Gtk.ComboBoxText ();
                foreach (var o in PanelSpotlight.atajos_ofrecidos ()) {
                    combo.append (o.clave, o.nombre);
                }
                if (!combo.set_active_id (actual)) {
                    combo.append (actual, actual);
                    combo.set_active_id (actual);
                }
                combo.changed.connect (() => {
                    if (!cargando && !prueba) {
                        ajuste.escribir ("hotkey-show-app", new Json.Node (Json.NodeType.VALUE).init_string (combo.get_active_id ()));
                    }
                });
                fila.pack_end (combo, false, false, 0);
                lista.add (fila);
                // Show Finder search window: Fynder no tiene esa ventana; se dibuja como en la captura, en gris.
                var fila2 = fila_atajo ("Show Finder search window", "⌥⌘Space", 1, 0);
                gris_k (fila2, "Fynder has no search window yet.");
                lista.add (fila2);
                return lista;
            }
            foreach (var d in filas_de (categoria)) {
                Gtk.Widget fila;
                if (d.grupo) {
                    fila = fila_atajo (d.titulo, null, 2, d.nivel, d.estado);
                } else {
                    fila = fila_atajo (d.titulo, d.atajo, d.marcada, d.nivel);
                }
                gris_k (fila, "This shortcut is not available on this computer.");
                lista.add (fila);
            }
            return lista;
        }

        // ── Input Sources ────────────────────────────────────────────────
        /** Las distribuciones del teclado, en el orden de los grupos de X (org.gnome.libgnomekbd.keyboard). */
        string[] capas () {
            var prueba_capas = Environment.get_variable ("MINT_TECLADO_CAPAS");
            if (prueba_capas != null && prueba_capas != "") {
                return prueba_capas.split (",");
            }
            var s = abrir_settings ("org.gnome.libgnomekbd.keyboard");
            return s != null ? s.get_strv ("layouts") : new string[] {};
        }

        /** «us» → «U.S.»; «us\tintl» y los demás se muestran como los define xkb. */
        static string nombre_capa (string capa) {
            switch (capa) {
            case "us": return "U.S.";
            case "es": return "Spanish";
            case "latam": return "Latin American";
            case "us\tintl": return "U.S. International";
            }
            return capa.replace ("\t", " (");
        }

        Gtk.Widget pagina_fuentes () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            pagina.margin_top = 14;
            pagina.margin_start = 20;
            pagina.margin_end = 20;
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var lista = new Gtk.ListBox ();
            lista.set_size_request (205, 330);
            var dibujo = new DibujoTeclado ();
            foreach (var capa in capas ()) {
                var fila = new Gtk.ListBoxRow ();
                var caja_capa = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                caja_capa.margin = 6;
                var bandera = IconosCatalina.bandera (capa, 18);      // solo U.S. y Spanish; las demás sin bandera
                if (bandera != null) {
                    caja_capa.pack_start (bandera, false, false, 0);
                }
                var l = new Gtk.Label (nombre_capa (capa));
                l.xalign = 0;
                caja_capa.pack_start (l, true, true, 0);
                fila.add (caja_capa);
                lista.add (fila);
            }
            lista.row_selected.connect ((f) => { if (f != null) dibujo.poner (f.get_index ()); });
            var izq = marco_lista ();
            izq.add (lista);
            var der = marco_lista ();
            der.add (dibujo);
            cuerpo.pack_start (izq, false, false, 0);
            cuerpo.pack_start (der, true, true, 0);
            pagina.pack_start (cuerpo, true, true, 0);
            if (lista.get_children ().length () > 0) {
                lista.select_row (lista.get_row_at_index (0));
            }

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var t in new string[] { "+", "−" }) {
                botones.pack_start (gris_k (new Gtk.Button.with_label (t), "Add and remove keyboard layouts in the keyboard settings of Cinnamon."), false, false, 0);
            }
            pie.pack_start (botones, false, false, 0);
            var cajas = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var menu = new Gtk.CheckButton.with_label ("Show Input menu in menu bar");
            menu.active = true;
            gris_k (menu, "The keyboard layout menu lives in the Cinnamon panel.");
            var auto = new Gtk.CheckButton.with_label ("Automatically switch to a document’s input source");
            gris_k (auto, "This computer does not switch the layout by document.");
            cajas.pack_start (menu, false, false, 0);
            cajas.pack_start (auto, false, false, 0);
            pie.pack_start (cajas, false, false, 0);
            pagina.pack_start (pie, false, false, 0);
            return pagina;
        }

        // ── Dictation: sin equivalente en Linux, en gris ─────────────────
        /** El nombre del micrófono predeterminado, como el «PBH-S370 ⌄» de la captura (si no se puede leer, «Built-in Input»). */
        static string micro_predeterminado () {
            var nombre_m = salida_de ({ "pactl", "get-default-source" });
            var texto = salida_de ({ "pactl", "list", "sources" });
            bool actual = false;
            foreach (var linea_c in texto.split ("\n")) {
                var linea = linea_c.strip ();
                if (linea.has_prefix ("Name:")) {
                    actual = linea.substring (linea.index_of (":") + 1).strip () == nombre_m;
                } else if (actual && linea.has_prefix ("Description:")) {
                    return linea.substring (linea.index_of (":") + 1).strip ();
                }
            }
            return "Built-in Input";
        }

        Gtk.Widget pagina_dictado () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            pagina.margin_top = 30;
            pagina.margin_start = 30;
            pagina.margin_end = 30;
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            // El micrófono de la izquierda: la captura trae el ícono de micrófono de Apple (sin extraer todavía) y debajo el dispositivo de entrada con su flecha.
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            izq.set_size_request (110, -1);
            var dispositivo = new Gtk.Label (micro_predeterminado () + " ⌄");
            dispositivo.get_style_context ().add_class ("mp-sd-detalle");
            dispositivo.margin_top = 78;       // donde en la captura acaba el ícono del micrófono
            izq.pack_start (gris_k (dispositivo, "Dictation is not available on this computer."), false, false, 0);
            cuerpo.pack_start (izq, false, false, 0);
            var der = new Gtk.Grid ();
            der.column_spacing = 10;
            der.row_spacing = 10;
            var t = new Gtk.Label ("Use Dictation wherever you can type text. To start dictating, use the shortcut or select Start Dictation from the Edit menu.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (52);
            der.attach (t, 0, 0, 2, 1);
            der.attach (etiqueta_fila ("Dictation:"), 0, 1, 1, 1);
            var onoff = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var r_on = new Gtk.RadioButton.with_label_from_widget (null, "On");
            var r_off = new Gtk.RadioButton.with_label_from_widget (r_on, "Off");
            r_off.active = true;
            onoff.pack_start (r_on, false, false, 0);
            onoff.pack_start (r_off, false, false, 0);
            der.attach (gris_k (onoff, "Dictation is not available on this computer."), 1, 1, 1, 1);
            string[] textos = { "Language:", "Shortcut:" };
            string[] valores = { "English (United States)", "Off" };
            for (int i = 0; i < 2; i++) {
                der.attach (etiqueta_fila (textos[i]), 0, 2 + i, 1, 1);
                var c = new Gtk.ComboBoxText ();
                c.append ("v", valores[i]);
                c.set_active (0);
                der.attach (gris (c), 1, 2 + i, 1, 1);
            }
            cuerpo.pack_start (der, false, false, 0);
            pagina.pack_start (cuerpo, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            pie.pack_end (gris_k (new Gtk.Button.with_label ("About Dictation & Privacy…"), "Dictation is not available on this computer."), false, false, 0);
            pie.margin_top = 8;
            pie.margin_bottom = 8;
            pagina.pack_start (pie, false, false, 0);
            return pagina;
        }

        // ── Modifier Keys ────────────────────────────────────────────────
        /** {tecla: acción} del bloque que escribe el ayudante en keyd; lo no listado va por defecto. */
        public static HashTable<string, string> leer_modificadoras () {
            var actual = new HashTable<string, string> (str_hash, str_equal);
            foreach (var t in TECLAS) {
                actual[t] = t;
            }
            string texto;
            try {
                FileUtils.get_contents (CONF_KEYD, out texto);
            } catch (Error e) {
                return actual;
            }
            bool dentro = false;
            foreach (var linea in texto.split ("\n")) {
                if (linea.strip () == BLOQUE_INICIO) {
                    dentro = true;
                } else if (linea.strip () == BLOQUE_FIN) {
                    dentro = false;
                } else if (dentro && linea.has_prefix ("# ")) {
                    var partes = linea.substring (2).split ("=");
                    if (partes.length == 2 && actual.contains (partes[0].strip ())) {
                        actual[partes[0].strip ()] = partes[1].strip ();
                    }
                }
            }
            return actual;
        }

        void hoja_modificadoras () {
            var d = new Gtk.Dialog ();
            d.transient_for = ventana;
            d.modal = true;
            d.set_decorated (false);
            d.get_style_context ().add_class ("mp-hoja");
            var caja = d.get_content_area () as Gtk.Box;
            caja.set_spacing (12);
            margenes (caja, 20, 20, 20, 20);
            var t = new Gtk.Label ("For each modifier key listed below, choose the action you want it to perform from the pop-up menu.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (46);
            caja.pack_start (t, false, false, 0);
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 10;
            g.halign = Gtk.Align.CENTER;
            var actuales = leer_modificadoras ();
            var combos = new Gtk.ComboBoxText[4];
            for (int i = 0; i < 4; i++) {
                g.attach (etiqueta_fila (TECLAS_TXT[i]), 0, i, 1, 1);
                var c = new Gtk.ComboBoxText ();
                for (int k = 0; k < ACCIONES.length; k++) {
                    if (ACCIONES[k] == "none") {     // como en la Mac: una raya antes de «No Action»
                        c.append ("-", "-");
                    }
                    c.append (ACCIONES[k], ACCIONES_TXT[k]);
                }
                c.set_row_separator_func ((modelo, it) => {
                    string texto;
                    modelo.get (it, 0, out texto, -1);
                    return texto == "-";
                });
                c.set_active_id (actuales[TECLAS[i]]);
                combos[i] = c;
                g.attach (c, 1, i, 1, 1);
            }
            caja.pack_start (g, false, false, 0);
            var restaurar = d.add_button ("Restore Defaults", Gtk.ResponseType.REJECT) as Gtk.Button;
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            var ok = d.add_button ("OK", Gtk.ResponseType.OK);
            ok.get_style_context ().add_class ("suggested-action");
            d.set_default_response (Gtk.ResponseType.OK);
            restaurar.clicked.connect (() => {
                for (int i = 0; i < 4; i++) {
                    combos[i].set_active_id (TECLAS[i]);
                }
            });
            d.show_all ();
            int r;
            while (true) {
                r = d.run ();
                if (r == Gtk.ResponseType.REJECT) {
                    continue;        // «Restore Defaults» solo vuelve a poner los menús; se aplica con OK
                }
                break;
            }
            var elegido = new HashTable<string, string> (str_hash, str_equal);
            bool cambio = false;
            for (int i = 0; i < 4; i++) {
                elegido[TECLAS[i]] = combos[i].get_active_id ();
                if (elegido[TECLAS[i]] != actuales[TECLAS[i]]) {
                    cambio = true;
                }
            }
            d.destroy ();
            if (r == Gtk.ResponseType.OK && cambio) {
                aplicar_modificadoras (elegido);
            }
        }

        /** Se lo pide al ayudante de root por pkexec (pide la clave una vez); keyd recarga solo. */
        bool aplicar_modificadoras (HashTable<string, string> elegido) {
            if (prueba) {
                stderr.printf ("[prueba] modifier-keys\n");
                return true;
            }
            string[] cmd = { "pkexec", AYUDANTE };
            foreach (var t in TECLAS) {
                cmd += "%s=%s".printf (t, elegido[t]);
            }
            try {
                var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                string? salida, error;
                p.communicate_utf8 (null, null, out salida, out error);
                int codigo = p.get_exit_status ();
                if (codigo != 0) {
                    if (codigo != 126 && codigo != 127) {   // 126/127: se canceló la clave; no es un error que contar
                        var msg = ((error ?? "") != "" ? error : ((salida ?? "") != "" ? salida : "The change was not applied.")).strip ();
                        aviso ("Modifier Keys", msg);
                    }
                    return false;
                }
            } catch (Error e) {
                aviso ("Modifier Keys", "Could not change the modifier keys: %s".printf (e.message));
                return false;
            }
            return true;
        }

        void aviso (string titulo, string texto) {
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.OK, "%s", titulo);
            d.format_secondary_text ("%s", texto);
            d.run ();
            d.destroy ();
        }
    }
}
