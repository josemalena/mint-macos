/*
 * General: el panel de Catalina (Screen Shot 2026-10-14 at 12.11.59 AM); port de settings/general.py.
 *
 * Conectado de verdad: Default web browser (xdg-settings) y Show scroll bars (gtk-overlay-scrollbars). Appearance solo tiene el tema
 * oscuro de Constanza, que es el que está activo: Light y Auto se dibujan en gris hasta que exista un tema claro. El resto (Accent y
 * Highlight color, Sidebar icon size, ocultar la barra de menús, Click in the scroll bar to, las casillas de documentos, Recent
 * items, Handoff y font smoothing) no tiene una clave que podamos escribir y comprobar aquí: se dibuja como en la captura, en gris,
 * como en una Mac sin esa función.
 *
 * Las miniaturas de Light/Dark/Auto son arte de Apple y salen del disco de la Mac, no del repo
 * (~/.local/share/mint-macos/settings/apariencia/); sin ellas se ven los nombres solos.
 */
namespace Preferencias {

    public class PanelGeneral : Panel {
        // MINT_GENERAL_PRUEBA: no escribe en gsettings ni en xdg-settings.
        bool prueba = Environment.get_variable ("MINT_GENERAL_PRUEBA") != null;
        bool cargando = false;
        Settings? cfg = null;
        HashTable<string, Gdk.Pixbuf?> miniaturas = new HashTable<string, Gdk.Pixbuf?> (str_hash, str_equal);
        HashTable<string, Gtk.RadioButton> radios = new HashTable<string, Gtk.RadioButton> (str_hash, str_equal);
        GenericArray<Gtk.DrawingArea> areas = new GenericArray<Gtk.DrawingArea> ();
        Gtk.ComboBoxText navegador;

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

        static Gtk.Widget gris_motivo (Gtk.Widget w, string? motivo) {
            w.set_sensitive (false);
            if (motivo != null) {
                w.set_tooltip_text (motivo);
            }
            return w;
        }

        public override Gtk.Widget? construir () {
            cargando = true;
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
                r.active = clave == "dark";
                radios[clave] = r;
                r.toggled.connect (() => {
                    for (int k = 0; k < areas.length; k++) {
                        areas[k].queue_draw ();
                    }
                });
                if (clave != "dark") {
                    gris_motivo (r, "Only the dark theme is installed on this computer.");
                }
                c.pack_start (r, false, false, 0);
                opciones.pack_start (c, false, false, 0);
            }
            g.attach (opciones, 1, fila, 2, 1);
            fila++;

            // Accent color y Highlight color
            g.attach (etiqueta_fila ("Accent color:"), 0, fila, 1, 1);
            var puntos = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            Gtk.RadioButton? gpuntos = null;
            for (int i = 0; i < 8; i++) {
                var r = new Gtk.RadioButton.from_widget (gpuntos);
                if (gpuntos == null) {
                    gpuntos = r;
                }
                r.active = i == 0;
                r.name = "mp-acento-%d".printf (i);
                puntos.pack_start (r, false, false, 0);
            }
            g.attach (gris_motivo (puntos, "The accent color is part of the theme on this computer."), 1, fila, 2, 1);
            fila++;
            g.attach (etiqueta_fila ("Highlight color:"), 0, fila, 1, 1);
            var c1 = new Gtk.ComboBoxText ();
            c1.append ("blue", "Blue");
            c1.set_active (0);
            g.attach (gris (c1), 1, fila, 2, 1);
            fila++;
            g.attach (etiqueta_fila ("Sidebar icon size:"), 0, fila, 1, 1);
            var c2 = new Gtk.ComboBoxText ();
            c2.append ("m", "Medium");
            c2.set_active (0);
            g.attach (gris (c2), 1, fila, 2, 1);
            fila++;
            var ocultar = new Gtk.CheckButton.with_label ("Automatically hide and show the menu bar");
            g.attach (gris (ocultar), 1, fila, 2, 1);
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
            g.attach (gris_motivo (clic, "This is decided by each app on this computer."), 1, fila, 2, 1);
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
            }
            g.attach (etiqueta_fila ("Recent items:"), 0, fila, 1, 1);
            var rec = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var spin = new Gtk.SpinButton.with_range (0, 50, 5);
            spin.set_value (10);
            rec.pack_start (spin, false, false, 0);
            rec.pack_start (new Gtk.Label ("Documents, Apps, and Servers"), false, false, 0);
            g.attach (gris_motivo (rec, "The number of recent items is not adjustable on this computer."), 1, fila, 2, 1);
            fila++;
            string[] extra = { "Allow Handoff between this Mac and your iCloud devices", "Use font smoothing when available" };
            for (int i = 0; i < 2; i++) {
                var c = new Gtk.CheckButton.with_label (extra[i]);
                c.active = true;
                g.attach (gris (c), 1, fila, 2, 1);
                fila++;
            }

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
