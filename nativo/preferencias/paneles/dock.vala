/*
 * Dock: Plank por dconf, el efecto genio por la extensión Magic Lamp y el doble clic de la barra de título por el gsettings
 * del gestor de ventanas (port de PanelDock en settings/propios.py). El diseño es el de la captura de Catalina
 * (Screen Shot 2026-10-14 at 12.12.52 AM). Lo que Linux o nuestro Plank no tienen (Prefer tabs when opening documents) no se
 * inventa: se dibuja en gris, como en una Mac sin esa función.
 */
namespace Preferencias {

    const string MAGIC_LAMP = "CinnamonMagicLamp@klangman";

    /** El slider de Catalina: sin número, con marcas «Small … Large» debajo. */
    public Gtk.Scale escala (double minimo, double maximo, double valor, string pie_izq, string pie_der, owned EscalaCambio al_cambiar) {
        var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, minimo, maximo, 1);
        esc.draw_value = false;
        esc.set_value (valor);
        esc.set_size_request (200, -1);
        esc.add_mark (minimo, Gtk.PositionType.BOTTOM, pie_izq);
        esc.add_mark (maximo, Gtk.PositionType.BOTTOM, pie_der);
        esc.value_changed.connect (() => al_cambiar ((int) esc.get_value ()));
        return esc;
    }

    public delegate void EscalaCambio (int valor);
    public delegate void Accion ();

    /** Un diccionario plano de texto en JSON, el formato de dock-tema-original.json (sin json-glib). */
    HashTable<string, string> leer_json_plano (string ruta) {
        var d = new HashTable<string, string> (str_hash, str_equal);
        try {
            string texto;
            FileUtils.get_contents (ruta, out texto);
            var re = new Regex ("\"([^\"]*)\"\\s*:\\s*\"([^\"]*)\"");
            MatchInfo m;
            for (re.match (texto, 0, out m); m.matches (); m.next ()) {
                d[m.fetch (1)] = m.fetch (2);
            }
        } catch (Error e) {
        }
        return d;
    }

    public class PanelDock : Panel {
        // El tema de Plank se edita en su archivo: Plank lo vigila y recarga solo. Lo que había se guarda al apagar un control,
        // para devolverlo igual al encenderlo.
        const string INDICADOR = "IndicatorSize";
        const string REBOTE = "LaunchBounceHeight";
        Settings? plank = null;

        public PanelDock () {
            id = "com.apple.preference.dock";
            nombre = es_monterey () ? "Dock & Menu Bar" : "Dock";
            palabras = "dock, size, magnification, position, minimize, genie, hide, zoom, title bar";
        }

        static string respaldo_ruta () {
            return Path.build_filename (carpeta_apps (), "dock-tema-original.json");
        }

        static string defecto_tema (string clave) {
            return clave == INDICADOR ? "0.75" : "0.35";
        }

        string? archivo_tema () {
            var tema = plank.get_string ("theme");
            foreach (var base_ in new string[] { carpeta_temas_dock (), "/usr/local/share/plank/themes", "/usr/share/plank/themes" }) {
                var ruta = Path.build_filename (base_, tema, "dock.theme");
                if (FileUtils.test (ruta, FileTest.EXISTS)) {
                    return ruta;
                }
            }
            return null;
        }

        static string? leer_tema (string ruta, string clave) {
            try {
                string texto;
                FileUtils.get_contents (ruta, out texto);
                var re = new Regex ("^" + Regex.escape_string (clave) + "=(.*)$", RegexCompileFlags.MULTILINE);
                MatchInfo m;
                if (re.match (texto, 0, out m)) {
                    return m.fetch (1).strip ();
                }
            } catch (Error e) {
            }
            return null;
        }

        static void poner_tema (string ruta, string clave, string valor) {
            try {
                string texto;
                FileUtils.get_contents (ruta, out texto);
                var re = new Regex ("^" + Regex.escape_string (clave) + "=.*$", RegexCompileFlags.MULTILINE);
                if (re.match (texto)) {
                    texto = re.replace_literal (texto, -1, 0, "%s=%s".printf (clave, valor));
                } else {
                    texto += "\n%s=%s\n".printf (clave, valor);
                }
                FileUtils.set_contents (ruta, texto);
            } catch (Error e) {
                warning ("dock.theme: %s", e.message);
            }
        }

        /** Encendido: el valor de antes (o el de la casa). Apagado: 0, guardando el de antes. */
        void encender_tema (string clave, bool encendido) {
            var ruta = archivo_tema ();
            if (ruta == null) {
                return;
            }
            var guardado = leer_json_plano (respaldo_ruta ());
            var actual = leer_tema (ruta, clave);
            if (encendido) {
                var antes = guardado[clave];
                poner_tema (ruta, clave, (antes != null && antes != "") ? antes : defecto_tema (clave));
            } else {
                if (actual != null && actual != "0" && actual != "0.0") {
                    guardado[clave] = actual;
                    var sb = new StringBuilder ("{");
                    bool primero = true;
                    guardado.foreach ((k, v) => {
                        sb.append ("%s\"%s\": \"%s\"".printf (primero ? "" : ", ", k, v));
                        primero = false;
                    });
                    sb.append ("}");
                    DirUtils.create_with_parents (Path.get_dirname (respaldo_ruta ()), 0755);
                    try {
                        FileUtils.set_contents (respaldo_ruta (), sb.str);
                    } catch (Error e) {
                    }
                }
                poner_tema (ruta, clave, "0");
            }
        }

        bool tema_encendido (string clave) {
            var ruta = archivo_tema ();
            if (ruta == null) {
                return true;
            }
            var v = leer_tema (ruta, clave);
            if (v == null) {
                return false;
            }
            double d;
            return double.try_parse (v, out d) ? d > 0 : true;
        }

        // ── la página ────────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            return es_monterey () ? construir_con_barra () : pagina_dock ();
        }

        static Gtk.Widget gris_motivo (Gtk.Widget w, string motivo) {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        // ── Monterey: la barra lateral de módulos (capturas 08-pref-...dock--Clock, --WiFi, --Sound…) ──
        struct Modulo {
            string id;
            string nombre;
            string seccion;
            string applet;       // uuid de la miniapp de la barra, o "" si aquí no hay equivalente (la casilla va en gris)
            string nota;         // «X is always available in Control Center.» y demás
        }

        Gtk.Widget construir_con_barra () {
            Modulo[] modulos = {
                Modulo () { id = "wifi", nombre = "Wi-Fi", seccion = "Control Center", applet = "network@cinnamon.org", nota = "Wi-Fi is always available in Control Center." },
                Modulo () { id = "bluetooth", nombre = "Bluetooth", seccion = "Control Center", applet = "", nota = "Bluetooth is always available in Control Center." },
                Modulo () { id = "airdrop", nombre = "AirDrop", seccion = "Control Center", applet = "", nota = "AirDrop is always available in Control Center." },
                Modulo () { id = "focus", nombre = "Focus", seccion = "Control Center", applet = "", nota = "Focus is always available in Control Center." },
                Modulo () { id = "mirroring", nombre = "Screen Mirroring", seccion = "Control Center", applet = "", nota = "Screen Mirroring is always available in Control Center." },
                Modulo () { id = "display", nombre = "Display", seccion = "Control Center", applet = "", nota = "Display is always available in Control Center." },
                Modulo () { id = "sound", nombre = "Sound", seccion = "Control Center", applet = "sound@cinnamon.org", nota = "Sound is always available in Control Center." },
                Modulo () { id = "nowplaying", nombre = "Now Playing", seccion = "Control Center", applet = "", nota = "Now Playing is always available in Control Center." },
                Modulo () { id = "accesibilidad", nombre = "Accessibility Shortcuts", seccion = "Other Modules", applet = "", nota = "" },
                Modulo () { id = "bateria", nombre = "Battery", seccion = "Other Modules", applet = "power@cinnamon.org", nota = "" },
                Modulo () { id = "usuarios", nombre = "Fast User Switching", seccion = "Other Modules", applet = "usuario@macos", nota = "" },
                Modulo () { id = "oido", nombre = "Hearing", seccion = "Other Modules", applet = "", nota = "" },
                Modulo () { id = "reloj", nombre = "Clock", seccion = "Menu Bar Only", applet = "calendar@cinnamon.org", nota = "" },
                Modulo () { id = "spotlight", nombre = "Spotlight", seccion = "Menu Bar Only", applet = "buscar@macos", nota = "" },
                Modulo () { id = "siri", nombre = "Siri", seccion = "Menu Bar Only", applet = "", nota = "" },
                Modulo () { id = "timemachine", nombre = "Time Machine", seccion = "Menu Bar Only", applet = "", nota = "" }
            };
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            var lista = new Gtk.ListBox ();
            lista.selection_mode = Gtk.SelectionMode.SINGLE;
            lista.set_size_request (210, -1);
            var pila = new Gtk.Stack ();
            // la primera fila: el panel de siempre
            var fila_dock = new Gtk.ListBoxRow ();
            fila_dock.name = "dock";
            var t_dock = new Gtk.Label ("Dock & Menu Bar");
            t_dock.xalign = 0;
            t_dock.margin = 8;
            fila_dock.add (t_dock);
            lista.add (fila_dock);
            pila.add_named (pagina_dock (), "dock");
            string seccion_actual = "";
            foreach (var m in modulos) {
                if (m.seccion != seccion_actual) {
                    seccion_actual = m.seccion;
                    var cab = new Gtk.ListBoxRow ();
                    cab.selectable = false;
                    cab.activatable = false;
                    var c = new Gtk.Label (m.seccion);
                    c.xalign = 0;
                    c.margin = 8;
                    c.get_style_context ().add_class ("dim-label");
                    cab.add (c);
                    lista.add (cab);
                }
                var fila = new Gtk.ListBoxRow ();
                fila.name = m.id;
                var v = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                var n = new Gtk.Label (m.nombre);
                n.xalign = 0;
                var sub = new Gtk.Label (m.applet != "" && applet_en_barra (m.applet) ? "Menu Bar & Control Center" : (m.seccion == "Menu Bar Only" ? "Menu Bar Only" : "Control Center"));
                sub.xalign = 0;
                sub.get_style_context ().add_class ("dim-label");
                v.pack_start (n, false, false, 0);
                v.pack_start (sub, false, false, 0);
                v.margin = 8;
                fila.add (v);
                lista.add (fila);
                pila.add_named (m.id == "reloj" ? new PanelDateTime ().pagina_reloj () : pagina_modulo (m.nombre, m.applet, m.nota, sub), m.id);
            }
            lista.row_selected.connect ((r) => {
                if (r != null) {
                    pila.set_visible_child_name (r.name);
                }
            });
            var marco = new Gtk.ScrolledWindow (null, null);
            marco.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            marco.add (lista);
            marco.set_size_request (210, 360);
            caja.pack_start (marco, false, false, 0);
            caja.pack_start (pila, true, true, 0);
            lista.select_row (fila_dock);
            caja.show_all ();
            return caja;
        }

        /** La página de un módulo del Control Center: título, la nota y «Show in Menu Bar» (la miniapp de la barra de Cinnamon, si hay). */
        Gtk.Widget pagina_modulo (string nombre, string applet, string nota, Gtk.Label subtitulo) {
            var pag = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            margenes (pag, 20, 20, 20, 20);
            var t = new Gtk.Label (nombre);
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            pag.pack_start (t, false, false, 0);
            if (nota != "") {
                var n = new Gtk.Label (nota);
                n.xalign = 0;
                n.set_line_wrap (true);
                n.set_max_width_chars (30);
                n.get_style_context ().add_class ("dim-label");
                pag.pack_start (n, false, false, 0);
            }
            var casilla = new Gtk.CheckButton.with_label ("Show in Menu Bar");
            if (applet != "") {
                casilla.active = applet_en_barra (applet);
                casilla.toggled.connect (() => {
                    poner_applet_en_barra (applet, casilla.active);
                    subtitulo.set_text (casilla.active ? "Menu Bar & Control Center" : "Control Center");
                });
            } else {
                gris_motivo (casilla, "There is no menu bar item for this on this computer.");
            }
            pag.pack_start (casilla, false, false, 4);
            return pag;
        }

        Gtk.Widget? pagina_dock () {
            plank = abrir_dock ();
            if (plank == null) {
                var l = new Gtk.Label ("The Dock is not installed.");
                l.show ();
                return l;
            }
            var p = plank;
            var cuadro = new Gtk.Grid ();
            cuadro.column_spacing = 14;
            cuadro.row_spacing = 14;
            cuadro.get_style_context ().add_class ("mp-propio");
            cuadro.halign = Gtk.Align.CENTER;
            margenes (cuadro, 22, 22, 30, 30);
            int fila = 0;

            // Size
            cuadro.attach (etiqueta_fila ("Size:"), 0, fila, 1, 1);
            cuadro.attach (escala (16, 128, p.get_int ("icon-size"), es_monterey () ? "small" : "Small", es_monterey () ? "large" : "Large", (v) => p.set_int ("icon-size", v)), 1, fila, 2, 1);
            fila++;

            // Magnification
            var mag = new Gtk.CheckButton.with_label ("Magnification:");
            mag.active = p.get_boolean ("zoom-enabled");
            cuadro.attach (mag, 0, fila, 1, 1);
            var zoom = escala (100, 300, double.min (300, double.max (100, p.get_int ("zoom-percent"))), es_monterey () ? "min" : "Min", es_monterey () ? "max" : "Max",
                               (v) => p.set_int ("zoom-percent", v));
            zoom.set_sensitive (mag.active);
            cuadro.attach (zoom, 1, fila, 2, 1);
            mag.toggled.connect (() => {
                p.set_boolean ("zoom-enabled", mag.active);
                zoom.set_sensitive (mag.active);
            });
            fila++;

            // Position on screen
            cuadro.attach (etiqueta_fila ("Position on screen:"), 0, fila, 1, 1);
            var pos = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            Gtk.RadioButton? grupo = null;
            string[] claves = { "left", "bottom", "right" };
            string[] textos = { "Left", "Bottom", "Right" };
            for (int i = 0; i < 3; i++) {
                var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                var r = new Gtk.RadioButton.from_widget (grupo);
                if (grupo == null) {
                    grupo = r;
                }
                r.active = p.get_string ("position") == claves[i];
                var clave = claves[i];
                r.toggled.connect (() => { if (r.active) p.set_string ("position", clave); });
                caja.pack_start (r, false, false, 0);
                caja.pack_start (new Gtk.Label (textos[i]), false, false, 0);
                pos.pack_start (caja, false, false, 0);
            }
            cuadro.attach (pos, 1, fila, 2, 1);
            fila++;

            // Minimize windows using
            cuadro.attach (etiqueta_fila ("Minimize windows using:"), 0, fila, 1, 1);
            var efecto = new Gtk.ComboBoxText ();
            efecto.append ("genie", "Genie effect");
            efecto.append ("scale", "Scale effect");
            efecto.set_active_id (genio_activo () ? "genie" : "scale");
            efecto.changed.connect (() => poner_genio (efecto.get_active_id () == "genie"));
            efecto.halign = Gtk.Align.START;
            cuadro.attach (efecto, 1, fila, 2, 1);
            fila++;

            if (!es_monterey ()) {
            // Prefer tabs when opening documents: lo decide cada app, no el sistema; como en una Mac que no tuviera la función,
            // se dibuja en gris (captura 12.12.52 AM).
            cuadro.attach (etiqueta_fila ("Prefer tabs when opening documents:"), 0, fila, 1, 1);
            var pestanas = new Gtk.ComboBoxText ();
            pestanas.append ("full", "In Full Screen Only");
            pestanas.append ("always", "Always");
            pestanas.append ("manual", "Manually");
            pestanas.set_active (0);
            pestanas.set_sensitive (false);
            pestanas.set_tooltip_text ("Each app decides this on its own on this computer.");
            pestanas.halign = Gtk.Align.START;
            cuadro.attach (pestanas, 1, fila, 2, 1);
            fila++;

            }

            // Minimize windows into application icon (el Plank de mint-macos; con un Plank sin esa clave el control no sale: no
            // hay nada que escribir).
            if (p.settings_schema.has_key ("minimize-into-icon")) {
                var en_icono = new Gtk.CheckButton.with_label ("Minimize windows into application icon");
                en_icono.active = p.get_boolean ("minimize-into-icon");
                en_icono.toggled.connect (() => p.set_boolean ("minimize-into-icon", en_icono.active));
                cuadro.attach (en_icono, 1, fila, 2, 1);
                fila++;
            }

            // Double-click a window's title bar to
            var wm = new Settings ("org.cinnamon.desktop.wm.preferences");
            var dc = new Gtk.CheckButton.with_label ("Double-click a window’s title bar to");
            var valor = wm.get_string ("action-double-click-titlebar");
            bool conocido = valor == "toggle-maximize" || valor == "minimize";
            dc.active = conocido;
            var combo = new Gtk.ComboBoxText ();
            combo.append ("toggle-maximize", "zoom");
            combo.append ("minimize", "minimize");
            combo.set_active_id (conocido ? valor : "toggle-maximize");
            combo.set_sensitive (dc.active);
            Accion doble_clic = () => {
                combo.set_sensitive (dc.active);
                wm.set_string ("action-double-click-titlebar", dc.active ? combo.get_active_id () : "none");
            };
            dc.toggled.connect (() => doble_clic ());
            combo.changed.connect (() => doble_clic ());
            var caja_dc = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            caja_dc.pack_start (dc, false, false, 0);
            caja_dc.pack_start (combo, false, false, 0);
            cuadro.attach (caja_dc, 1, fila, 2, 1);
            fila++;

            // Animate opening applications: el rebote al abrir (LaunchBounceHeight del tema)
            var animar = new Gtk.CheckButton.with_label ("Animate opening applications");
            animar.active = tema_encendido (REBOTE);
            animar.toggled.connect (() => encender_tema (REBOTE, animar.active));
            cuadro.attach (animar, 1, fila, 2, 1);
            fila++;

            // Automatically hide and show the Dock
            var ocultar = new Gtk.CheckButton.with_label ("Automatically hide and show the Dock");
            ocultar.active = p.get_string ("hide-mode") != "none";
            ocultar.toggled.connect (() => p.set_string ("hide-mode", ocultar.active ? "auto" : "none"));
            cuadro.attach (ocultar, 1, fila, 2, 1);
            fila++;

            // Show indicators for open applications: el punto bajo el ícono (IndicatorSize del tema)
            var indic = new Gtk.CheckButton.with_label ("Show indicators for open applications");
            indic.active = tema_encendido (INDICADOR);
            indic.toggled.connect (() => encender_tema (INDICADOR, indic.active));
            cuadro.attach (indic, 1, fila, 2, 1);
            fila++;

            // Show recent applications in Dock: las últimas tres apps cerradas se quedan (clave show-recent-apps del Plank de
            // mint-macos).
            if (p.settings_schema.has_key ("show-recent-apps")) {
                var recientes = new Gtk.CheckButton.with_label ("Show recent applications in Dock");
                recientes.active = p.get_boolean ("show-recent-apps");
                recientes.toggled.connect (() => p.set_boolean ("show-recent-apps", recientes.active));
                cuadro.attach (recientes, 1, fila, 2, 1);
            }

            // Monterey: la sección «Menu Bar» al final (en Catalina «Automatically hide and show the menu bar» vivía en General): ocultar la barra
            // de arriba en el escritorio (panels-autohide del panel de arriba de Cinnamon) y en pantalla completa (la Mac lo tiene; aquí no hay
            // pantalla completa distinta: en gris).
            if (es_monterey ()) {
                fila++;
                cuadro.attach (etiqueta_fila ("Menu Bar:"), 0, fila, 1, 1);
                var cin = new Settings ("org.cinnamon");
                string? arriba = null;
                foreach (var e in cin.get_strv ("panels-enabled")) {
                    var pe = e.split (":");
                    if (pe.length >= 3 && pe[2] == "top") {
                        arriba = pe[0];
                        break;
                    }
                }
                var escritorio = new Gtk.CheckButton.with_label ("Automatically hide and show the menu bar on desktop");
                if (arriba != null) {
                    foreach (var e in cin.get_strv ("panels-autohide")) {
                        if (e.has_prefix (arriba + ":")) {
                            escritorio.active = e.substring (arriba.length + 1) == "true";
                        }
                    }
                    escritorio.toggled.connect (() => {
                        string[] lista = {};
                        bool visto = false;
                        foreach (var e in cin.get_strv ("panels-autohide")) {
                            if (e.has_prefix (arriba + ":")) {
                                lista += "%s:%s".printf (arriba, escritorio.active ? "true" : "false");
                                visto = true;
                            } else {
                                lista += e;
                            }
                        }
                        if (!visto) {
                            lista += "%s:%s".printf (arriba, escritorio.active ? "true" : "false");
                        }
                        cin.set_strv ("panels-autohide", lista);
                    });
                } else {
                    escritorio.set_sensitive (false);
                }
                cuadro.attach (escritorio, 1, fila, 2, 1);
                fila++;
                var pantalla = new Gtk.CheckButton.with_label ("Automatically hide and show the menu bar in full screen");
                pantalla.active = true;
                pantalla.set_sensitive (false);
                pantalla.set_tooltip_text ("Full-screen mode does not exist on this computer.");
                cuadro.attach (pantalla, 1, fila, 2, 1);
            }

            cuadro.show_all ();
            return cuadro;
        }

        // ── el efecto genio: encender o apagar la extensión Magic Lamp ──
        static bool genio_activo () {
            var lista = new Settings ("org.cinnamon").get_strv ("enabled-extensions");
            return MAGIC_LAMP in lista;
        }

        static void poner_genio (bool si) {
            var cfg = new Settings ("org.cinnamon");
            string[] lista = {};
            foreach (var e in cfg.get_strv ("enabled-extensions")) {
                if (e != MAGIC_LAMP) {
                    lista += e;
                }
            }
            if (si) {
                lista += MAGIC_LAMP;
            }
            cfg.set_strv ("enabled-extensions", lista);
        }
    }
}
