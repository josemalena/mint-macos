/*
 * Mission Control: la mitad que Cinnamon sabe hacer (Displays have separate Spaces, los atajos de la extensión misioncontrol@macos) y
 * la hoja de Hot Corners, que escribe `hotcorner-layout` de org.cinnamon (port de PanelMissionControl en settings/propios.py). Una
 * esquina de Cinnamon corre `expo`, `scale`, `desktop` o un comando; las acciones de Catalina que no son de esas tres van como
 * comando (las que viven dentro de Cinnamon, por Eval).
 */
namespace Preferencias {

    public class AccionEsquina {
        public string comando;
        public string nombre;
        public AccionEsquina (string comando, string nombre) {
            this.comando = comando;
            this.nombre = nombre;
        }
    }

    /** Las esquinas activas de Cinnamon: lo comparten Mission Control y Desktop & Screen Saver. */
    public class Esquinas {
        const string EVAL = "gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval ";
        // 0 arriba izquierda, 1 arriba derecha, 2 abajo izquierda, 3 abajo derecha (el orden de Cinnamon).
        const string VACIA = "expo:false:0";

        /** (comando de la esquina, nombre en Catalina); el primero es «–», apagada. */
        public static AccionEsquina[] acciones () {
            return {
                new AccionEsquina ("", "–"),
                new AccionEsquina ("scale", "Mission Control"),
                new AccionEsquina (EVAL + "global.mintMacosAppWindows()", "Application Windows"),
                new AccionEsquina ("desktop", "Desktop"),
                new AccionEsquina ("~/.local/bin/mac-launchpad", "Launchpad"),
                new AccionEsquina (EVAL + "global.mintMacosNotificationCenter()", "Notification Center"),
                new AccionEsquina ("cinnamon-screensaver-command -a", "Start Screen Saver"),
                new AccionEsquina ("xset dpms force off", "Put Display to Sleep"),
                new AccionEsquina ("cinnamon-screensaver-command -l", "Lock Screen")
            };
        }

        public static string expandir (string cmd) {
            return cmd.has_prefix ("~") ? Environment.get_home_dir () + cmd.substring (1) : cmd;
        }

        /** [comando|""] por esquina: lo que hoy hace cada una ("" si está apagada). */
        public static string[] leer (Settings? ajustes = null) {
            var aj = ajustes ?? new Settings ("org.cinnamon");
            string[] capas = aj.get_strv ("hotcorner-layout");
            while (capas.length < 4) {
                capas += VACIA;
            }
            string[] salida = {};
            for (int i = 0; i < 4; i++) {
                salida += comando_de (capas[i]);
            }
            return salida;
        }

        /** El comando de «comando:activa:retraso» (el comando puede llevar «:»; las dos últimas partes son fijas). */
        static string comando_de (string item) {
            string[] partes = partir_derecha (item);
            return (partes.length == 3 && partes[1] == "true") ? partes[0] : "";
        }

        /** Como rsplit(":", 2) de Python: [comando, activa, retraso], o el texto entero si no tiene dos «:». */
        static string[] partir_derecha (string s) {
            int ult = s.last_index_of (":");
            if (ult < 0) {
                return { s };
            }
            int pen = s.substring (0, ult).last_index_of (":");
            if (pen < 0) {
                return { s };
            }
            return { s.substring (0, pen), s.substring (pen + 1, ult - pen - 1), s.substring (ult + 1) };
        }

        /** Cambia una esquina y deja las otras (con su retraso) como estaban. */
        public static void escribir (int indice, string comando, Settings? ajustes = null) {
            var aj = ajustes ?? new Settings ("org.cinnamon");
            string[] capas = aj.get_strv ("hotcorner-layout");
            while (capas.length < 4) {
                capas += VACIA;
            }
            string retraso = "0";
            var partes = partir_derecha (capas[indice]);
            if (partes.length == 3) {
                retraso = partes[2];
            }
            capas[indice] = comando != "" ? "%s:true:%s".printf (expandir (comando), retraso) : VACIA;
            aj.set_strv ("hotcorner-layout", capas);
        }
    }

    public class PanelMissionControl : Panel {
        public PanelMissionControl () {
            id = "com.apple.preference.expose";
            nombre = "Mission Control";
            palabras = "spaces, desktops, workspaces, hot corners, windows, mission control, expose";
        }

        public override Gtk.Widget? construir () {
            var mut = abrir_settings ("org.cinnamon.muffin");
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            caja.get_style_context ().add_class ("mp-propio");

            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            cab.pack_start (imagen_icono_panel (id, 48), false, false, 0);
            var t = new Gtk.Label ("Mission Control gives you an overview of all your open windows, thumbnails of your full-screen applications, all arranged in a unified view.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (70);
            cab.pack_start (t, true, true, 0);
            caja.pack_start (cab, false, false, 0);

            var marco = marco_lista ();
            var cuadro = new Gtk.Grid ();
            cuadro.column_spacing = 14;
            cuadro.row_spacing = 10;
            margenes (cuadro, 16, 16, 20, 20);
            cuadro.halign = Gtk.Align.START;
            marco.add (cuadro);
            // Las tres casillas que Cinnamon no tiene van en gris, como en la captura 12.12.58 AM.
            int fila_c = 0;
            string[] textos = { "Automatically rearrange Spaces based on most recent use",
                                "When switching to an application, switch to a Space with open windows for the application",
                                "Group windows by application" };
            bool[] activas = { true, true, false };
            for (int i = 0; i < 3; i++) {
                var g_ = new Gtk.CheckButton.with_label (textos[i]);
                g_.active = activas[i];
                g_.set_sensitive (false);
                g_.set_tooltip_text ("Cinnamon has no equivalent for this option.");
                cuadro.attach (g_, 0, fila_c, 2, 1);
                fila_c++;
            }
            // Displays have separate Spaces = los escritorios no se reparten entre pantallas.
            var c = new Gtk.CheckButton.with_label ("Displays have separate Spaces");
            c.active = mut != null && !mut.get_boolean ("workspaces-only-on-primary");
            c.toggled.connect (() => { if (mut != null) mut.set_boolean ("workspaces-only-on-primary", !c.active); });
            cuadro.attach (c, 0, fila_c, 1, 1);
            var pide = new Gtk.Label ("Requires log out");
            pide.get_style_context ().add_class ("dim-label");
            cuadro.attach (pide, 1, fila_c, 1, 1);
            caja.pack_start (marco, false, false, 0);

            var tit = new Gtk.Label ("Keyboard and Mouse Shortcuts");
            tit.xalign = 0;
            tit.get_style_context ().add_class ("mp-sd-detalle");
            caja.pack_start (tit, false, false, 0);
            var teclazo = new Gtk.Label ("With a single keystroke, view all open windows, windows of the current application, or hide windows to locate an item on the desktop that might be covered up.");
            teclazo.xalign = 0;
            teclazo.set_line_wrap (true);
            teclazo.set_max_width_chars (80);
            caja.pack_start (teclazo, false, false, 0);
            var atajos = marco_lista ();
            var g = new Gtk.Grid ();
            g.column_spacing = 14;
            g.row_spacing = 10;
            margenes (g, 16, 16, 20, 20);
            g.halign = Gtk.Align.START;
            string[] nombres = { "Mission Control:", "Application windows:", "Show Desktop:", "Spaces left and right:" };
            string[] teclas = { "⌃↑", "⌃↓", "–", "⌃←  ⌃→" };
            for (int i = 0; i < 4; i++) {
                g.attach (etiqueta_fila (nombres[i]), 0, i, 1, 1);
                var v = new Gtk.Label (teclas[i]);
                v.xalign = 0;
                g.attach (v, 1, i, 1, 1);
            }
            atajos.add (g);
            caja.pack_start (atajos, false, false, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var b = new Gtk.Button.with_label ("Hot Corners…");
            b.clicked.connect (() => hoja ());
            pie.pack_start (b, false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            return caja;
        }

        // ── la hoja de las cuatro esquinas ───────────────────────────────
        /** El escritorio actual en miniatura (o null si no se puede leer). */
        Gdk.Pixbuf? fondo (int w, int h) {
            try {
                var bg = abrir_settings ("org.cinnamon.desktop.background");
                if (bg == null) {
                    return null;
                }
                var ruta = File.new_for_uri (bg.get_string ("picture-uri")).get_path ();
                var pb = new Gdk.Pixbuf.from_file (ruta);
                double esc = double.max ((double) w / pb.get_width (), (double) h / pb.get_height ());
                var grande = pb.scale_simple ((int) (pb.get_width () * esc) + 1, (int) (pb.get_height () * esc) + 1, Gdk.InterpType.BILINEAR);
                return new Gdk.Pixbuf.subpixbuf (grande, (grande.get_width () - w) / 2, (grande.get_height () - h) / 2, w, h);
            } catch (Error e) {
                return null;
            }
        }

        public void hoja () {
            var d = new Gtk.Dialog ();
            d.transient_for = ventana;
            d.modal = true;
            d.set_decorated (false);
            d.get_style_context ().add_class ("mp-hoja");
            var caja = d.get_content_area () as Gtk.Box;
            caja.set_spacing (10);
            margenes (caja, 16, 16, 20, 20);
            var t = new Gtk.Label ("Active Screen Corners");
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-sd-detalle");
            caja.pack_start (t, false, false, 0);
            var marco = marco_lista ();
            var g = new Gtk.Grid ();
            g.column_spacing = 30;
            g.row_spacing = 22;
            margenes (g, 16, 16, 36, 36);
            marco.add (g);

            var actuales = Esquinas.leer ();
            var acciones = Esquinas.acciones ();
            var combos = new Gtk.ComboBoxText[4];
            for (int i = 0; i < 4; i++) {
                var c = new Gtk.ComboBoxText ();
                for (int n = 0; n < acciones.length; n++) {
                    c.append (n.to_string (), acciones[n].nombre);
                }
                int encontrado = -1;
                for (int n = 0; n < acciones.length; n++) {
                    if (Esquinas.expandir (acciones[n].comando) == actuales[i]) {
                        encontrado = n;
                    }
                }
                if (encontrado >= 0) {
                    c.set_active (encontrado);
                } else {                                  // un comando ajeno: se muestra tal cual
                    c.append ("x", actuales[i]);
                    c.set_active_id ("x");
                }
                c.set_size_request (212, -1);
                int esquina = i;
                c.changed.connect (() => elegida (esquina, c));
                combos[i] = c;
            }
            var miniatura = new Gtk.DrawingArea ();
            miniatura.set_size_request (100, 70);
            var fondo_pb = fondo (100, 70);
            miniatura.draw.connect ((cr) => {
                if (fondo_pb != null) {
                    Gdk.cairo_set_source_pixbuf (cr, fondo_pb, 0, 0);
                } else {
                    cr.set_source_rgb (0.15, 0.2, 0.3);
                }
                cr.paint ();
                cr.set_source_rgb (1, 1, 1);
                int[,] esq = { { 0, 0, 1, 1 }, { 100, 0, -1, 1 }, { 0, 70, 1, -1 }, { 100, 70, -1, -1 } };
                for (int k = 0; k < 4; k++) {
                    cr.move_to (esq[k, 0], esq[k, 1]);
                    cr.line_to (esq[k, 0] + 9 * esq[k, 2], esq[k, 1]);
                    cr.line_to (esq[k, 0], esq[k, 1] + 9 * esq[k, 3]);
                    cr.close_path ();
                    cr.fill ();
                }
                return false;
            });
            g.attach (combos[0], 0, 0, 1, 1);
            g.attach (combos[1], 2, 0, 1, 1);
            g.attach (combos[2], 0, 1, 1, 1);
            g.attach (combos[3], 2, 1, 1, 1);
            g.attach (miniatura, 1, 0, 1, 2);
            caja.pack_start (marco, false, false, 0);
            var ok = d.add_button ("OK", Gtk.ResponseType.OK);
            ok.get_style_context ().add_class ("suggested-action");
            d.set_default_response (Gtk.ResponseType.OK);
            d.show_all ();
            d.run ();
            d.destroy ();
        }

        void elegida (int indice, Gtk.ComboBoxText combo) {
            var n = combo.get_active_id ();
            if (n == null || n == "x") {
                return;
            }
            Esquinas.escribir (indice, Esquinas.acciones ()[int.parse (n)].comando);
        }
    }
}
