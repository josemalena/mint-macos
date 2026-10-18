/*
 * About This Mac / About This PC (Catalina, capturas 12-about-this-mac-overview y 16-about-*): una ventana de 586 px con
 * las pestañas en la barra de título. Overview: el logo del sistema en el disco de la izquierda, el nombre del sistema
 * (grueso) y su nombre de versión (fino), «Version», y las filas del equipo. Displays: la pantalla dibujada, su nombre,
 * tamaño y gráficos. Storage: un renglón por volumen con su barra. Memory, Support y Service no están (no hay captura
 * de ellas todavía: se piden, no se inventan).
 */
namespace Acerca {
    const string CSS = """
window.acerca-ventana headerbar { min-height: 38px; }
window.acerca-ventana label { font-family: ".SF NS"; }
.acerca-so { font-size: 26px; }
.acerca-version { font-size: 12px; }
.acerca-fila { font-size: 12px; }
.acerca-pie { font-size: 10px; opacity: 0.55; }
button.acerca-enlace { padding: 0; min-height: 0; border: none; background: none; box-shadow: none; }
button.acerca-enlace label { font-family: ".SF NS"; font-size: 10px; opacity: 0.55; text-decoration: underline; }
.acerca-pantalla { font-size: 16px; font-weight: bold; }
.acerca-dato { font-size: 12px; }
.acerca-volumen { font-size: 14px; }
.acerca-libre { font-size: 12px; }
.acerca-disco { font-size: 11px; }
""";

    public class Ventana : Gtk.Window {
        Equipo equipo;
        Gtk.Stack pila;

        public Ventana (string pestana = "overview") {
            Object (type: Gtk.WindowType.TOPLEVEL);
            equipo = Equipo.cargar ();
            title = equipo.etiqueta_menu ();
            resizable = false;
            window_position = Gtk.WindowPosition.CENTER;
            get_style_context ().add_class ("acerca-ventana");
            MacOS.aplicar_css (CSS);

            pila = new Gtk.Stack ();
            pila.hhomogeneous = true;
            pila.vhomogeneous = false;
            pila.add_titled (overview (), "overview", "Overview");
            pila.add_titled (displays (), "displays", "Displays");
            pila.add_titled (storage (), "storage", "Storage");

            var barra = new Gtk.HeaderBar ();
            barra.show_close_button = true;
            barra.decoration_layout = "close,minimize,maximize:";
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = pila;
            barra.custom_title = pestanas;
            barra.title = equipo.etiqueta_menu ();
            set_titlebar (barra);
            set_title (equipo.etiqueta_menu ());
            add (pila);
            show_all ();
            pila.visible_child_name = pestana;
        }

        public void ir_a (string pestana) {
            pila.visible_child_name = pestana;
            present ();
        }

        static Gtk.Label etiqueta (string markup, string clase, bool selectable = true) {
            var l = new Gtk.Label (null);
            l.set_markup (markup);
            l.xalign = 0;
            l.selectable = false;
            l.get_style_context ().add_class (clase);
            return l;
        }

        static string esc (string s) {
            return Markup.escape_text (s);
        }

        // ── Overview ────────────────────────────────────────────────────
        Gtk.Widget overview () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 52);
            fila.set_size_request (586, 316);
            fila.margin_start = 52;
            fila.margin_end = 40;
            fila.margin_bottom = 20;

            fila.pack_start (disco_del_sistema (), false, false, 0);

            var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            col.valign = Gtk.Align.CENTER;
            var nombre_so = equipo.version_nombre ();
            col.pack_start (etiqueta (nombre_so != ""
                ? "<b>%s</b> <span weight='light'>%s</span>".printf (esc (equipo.sistema), esc (nombre_so))
                : "<b>%s</b>".printf (esc (equipo.sistema)), "acerca-so"), false, false, 0);
            if (equipo.version_numero () != "") {
                col.pack_start (etiqueta ("Version %s".printf (esc (equipo.version_numero ())), "acerca-version"), false, false, 0);
            }
            var datos = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            datos.margin_top = 18;
            if (equipo.nombre != "") datos.pack_start (etiqueta ("<b>%s</b>".printf (esc (equipo.nombre)), "acerca-fila"), false, false, 0);
            agregar_fila (datos, "Processor", equipo.procesador);
            agregar_fila (datos, "Memory", equipo.memoria);
            agregar_fila (datos, "Startup Disk", disco_de_arranque (equipo.sistema));
            agregar_fila (datos, "Graphics", equipo.graficos);
            agregar_fila (datos, "Serial Number", equipo.serie);
            col.pack_start (datos, false, false, 0);

            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            botones.margin_top = 18;
            var informe = new Gtk.Button.with_label ("System Report…");
            informe.clicked.connect (() => lanzar ({ "mintreport" }));
            var actualizar = new Gtk.Button.with_label ("Software Update…");
            actualizar.clicked.connect (() => lanzar ({ "mintupdate" }));
            botones.pack_start (informe, false, false, 0);
            botones.pack_start (actualizar, false, false, 0);
            col.pack_start (botones, false, false, 0);
            fila.pack_start (col, true, true, 0);
            pagina.pack_start (fila, true, true, 0);
            pagina.pack_end (pie_de_licencia (), false, false, 0);
            return pagina;
        }

        /**
         * El pie del Overview, donde Apple pone «™ and © 1983-… Apple Inc. All Rights Reserved. License Agreement»: aquí
         * el sistema y su licencia. Las fuentes: el nombre sale de os-release (NAME) y la licencia de
         * /usr/share/doc/mint-info-cinnamon/copyright («free software … GNU General Public License»); el enlace abre ese texto.
         */
        Gtk.Widget pie_de_licencia () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            caja.halign = Gtk.Align.CENTER;
            caja.margin_bottom = 12;
            var txt = etiqueta ("%s is free software under the GNU General Public License.".printf (esc (equipo.sistema)), "acerca-pie");
            caja.pack_start (txt, false, false, 0);
            var licencia = "/usr/share/doc/mint-info-cinnamon/copyright";
            if (FileUtils.test (licencia, FileTest.EXISTS)) {
                var enlace = new Gtk.Button.with_label ("License Agreement");
                enlace.relief = Gtk.ReliefStyle.NONE;
                enlace.get_style_context ().add_class ("acerca-enlace");
                enlace.clicked.connect (() => lanzar ({ "xdg-open", licencia }));
                caja.pack_start (enlace, false, false, 0);
            }
            return caja;
        }

        static void agregar_fila (Gtk.Box caja, string clave, string valor) {
            if (valor == "") return;       // lo que no se puede leer no se muestra
            caja.pack_start (etiqueta ("<b>%s</b>  %s".printf (esc (clave), esc (valor)), "acerca-fila"), false, false, 0);
        }

        static void lanzar (string[] cmd) {
            try {
                Process.spawn_async (null, cmd, null, SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL, null, null);
            } catch (Error e) {
                warning ("%s: %s", cmd[0], e.message);
            }
        }

        /** El disco con el logo del sistema (en la Mac, el círculo de Catalina con su aro de vidrio). */
        Gtk.Widget disco_del_sistema () {
            var area = new Gtk.DrawingArea ();
            area.set_size_request (152, 152);
            area.valign = Gtk.Align.CENTER;
            Gdk.Pixbuf? logo = null;
            try {
                if (equipo.logo != "") logo = new Gdk.Pixbuf.from_file_at_scale (equipo.logo, 104, 104, true);
                else if (equipo.logo_icono != "") logo = Gtk.IconTheme.get_default ().load_icon (equipo.logo_icono, 104, 0);
            } catch (Error e) {
            }
            area.draw.connect ((cr) => {
                double c = 76;
                var aro = new Cairo.Pattern.linear (0, 0, 0, 152);
                aro.add_color_stop_rgb (0, 0.97, 0.97, 0.97);
                aro.add_color_stop_rgb (1, 0.72, 0.72, 0.74);
                cr.arc (c, c, 74, 0, 2 * Math.PI);
                cr.set_source (aro);
                cr.fill ();
                cr.arc (c, c, 68, 0, 2 * Math.PI);
                cr.set_source_rgb (0.98, 0.98, 0.98);
                cr.fill ();
                if (logo != null) {
                    Gdk.cairo_set_source_pixbuf (cr, logo, c - logo.get_width () / 2.0, c - logo.get_height () / 2.0);
                    cr.paint ();
                }
                return true;
            });
            return area;
        }

        // ── Displays ────────────────────────────────────────────────────
        // Con varios monitores van uno al lado del otro, cada uno con su dibujo arriba y sus textos debajo alineados a
        // la izquierda de su columna (captura de High Sierra con dos monitores); un solo botón abajo a la derecha.
        Gtk.Widget displays () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            caja.set_size_request (586, 376);      // 414 px con la barra de título, como en la Mac
            var columnas = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            columnas.homogeneous = true;
            columnas.margin_top = 44;
            columnas.margin_start = 30;
            columnas.margin_end = 30;
            foreach (var p in pantallas ()) {
                var b = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
                b.halign = Gtk.Align.CENTER;
                // El dibujo de la pantalla: del tema de íconos (el de Apple no se copia al repo).
                var dibujo = new Gtk.Image.from_icon_name ("video-display", Gtk.IconSize.DIALOG);
                dibujo.pixel_size = 96;
                dibujo.halign = Gtk.Align.CENTER;
                b.pack_start (dibujo, false, false, 0);
                var nom = etiqueta (esc (p.nombre), "acerca-pantalla");
                nom.margin_top = 32;
                b.pack_start (nom, false, false, 0);
                var medida = p.pulgadas > 0 ? "%s (%d x %d)".printf (pulgadas_texto (p.pulgadas), p.ancho, p.alto) : "%d x %d".printf (p.ancho, p.alto);
                b.pack_start (etiqueta (esc (medida), "acerca-dato"), false, false, 0);
                if (equipo.graficos != "") b.pack_start (etiqueta (esc ("%s graphics".printf (equipo.graficos)), "acerca-dato"), false, false, 0);
                columnas.pack_start (b, true, true, 0);
            }
            caja.pack_start (columnas, false, false, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            pie.margin = 20;
            var prefs = new Gtk.Button.with_label ("Displays Preferences…");
            prefs.clicked.connect (() => lanzar ({ "mac-settings", "displays" }));
            pie.pack_end (prefs, false, false, 0);
            caja.pack_end (pie, false, false, 0);
            return caja;
        }

        // ── Storage ─────────────────────────────────────────────────────
        Gtk.Widget storage () {
            var lista = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            lista.set_size_request (586, -1);
            foreach (var v in volumenes (equipo.sistema)) lista.pack_start (renglon_de (v), false, false, 0);
            var scroll = new Gtk.ScrolledWindow (null, null);
            scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 500;
            scroll.add (lista);
            return scroll;
        }

        Gtk.Widget renglon_de (Volumen v) {
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 20);
            fila.set_size_request (-1, 150);        // un disco: 188 px con la barra de título; cada disco suma un renglón
            fila.margin_start = 20;
            fila.margin_end = 20;
            fila.margin_top = 20;
            var icono_col = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            icono_col.set_size_request (90, -1);
            var icono = new Gtk.Image.from_icon_name (v.externo ? "drive-removable-media" : "drive-harddisk", Gtk.IconSize.DIALOG);
            icono.pixel_size = 48;
            icono_col.pack_start (icono, false, false, 0);
            var desc = etiqueta (esc (v.descripcion), "acerca-disco", false);
            desc.justify = Gtk.Justification.CENTER;
            desc.xalign = 0.5f;
            icono_col.pack_start (desc, false, false, 0);
            fila.pack_start (icono_col, false, false, 0);

            var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            col.valign = Gtk.Align.START;
            col.pack_start (etiqueta (esc (v.nombre), "acerca-volumen"), false, false, 0);
            col.pack_start (etiqueta (esc ("%s available of %s".printf (tamano_legible (v.libre), tamano_legible (v.tamano))), "acerca-libre"), false, false, 0);
            var barra = new Gtk.DrawingArea ();
            barra.set_size_request (-1, 20);
            barra.margin_top = 3;
            double usado = v.tamano > 0 ? 1.0 - ((double) v.libre / v.tamano) : 0;
            barra.draw.connect ((cr) => {
                int w = barra.get_allocated_width (), h = barra.get_allocated_height ();
                cr.rectangle (0.5, 0.5, w - 1, h - 1);
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.25);
                cr.fill_preserve ();
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
                cr.set_line_width (1);
                cr.stroke ();
                cr.rectangle (1, 1, (w - 2) * usado, h - 2);
                cr.set_source_rgba (0.62, 0.62, 0.64, 0.95);
                cr.fill ();
                return true;
            });
            col.pack_start (barra, false, false, 0);
            fila.pack_start (col, true, true, 0);
            return fila;
        }
    }
}
