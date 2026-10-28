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
window.acerca-ventana stackswitcher button { padding-left: 8px; padding-right: 8px; min-width: 0; }
window.acerca-ventana label { font-family: ".SF NS"; }
.acerca-so { font-size: 26px; }
.acerca-version { font-size: 12px; }
.acerca-fila { font-size: 12px; }
.acerca-pie { font-size: 10px; opacity: 0.55; }
button.acerca-enlace-flecha { padding: 0; min-height: 0; border: none; background: none; box-shadow: none; }
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
            if (equipo.ranuras.length > 0) pila.add_titled (memoria (), "memory", "Memory");
            pila.add_titled (soporte (), "support", "Support");
            pila.add_titled (servicio (), "service", "Service");

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
            // «Credits» va en la misma fila que «License Agreement» (una fila más haría la pestaña Overview más alta que Displays): abre el About
            // completo de mint-macos con el diseño, el código, las marcas de Apple y la lista de componentes con su «Based on …».
            var mas = new Gtk.Button.with_label ("Credits");
            mas.relief = Gtk.ReliefStyle.NONE;
            mas.get_style_context ().add_class ("acerca-enlace");
            mas.clicked.connect (() => { MacOS.dialogo_creditos ("About This Mac", this).present (); });
            caja.pack_start (mas, false, false, 0);
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
        Volumen[] volumenes_vivos = {};
        Gtk.DrawingArea[] barras = {};
        Categoria[] categorias_vivas = {};      // campo: las barras se dibujan mucho después de armar la pestaña

        Gtk.Widget storage () {
            var lista = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            lista.set_size_request (586, -1);
            volumenes_vivos = volumenes (equipo.sistema);
            categorias_vivas = categorias ();
            foreach (var v in volumenes_vivos) lista.pack_start (renglon_de (v), false, false, 0);
            calcular_categorias (volumenes_vivos, categorias_vivas, () => { foreach (var b in barras) b.queue_draw (); });
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
            // Los tres discos de Catalina que trae el tema Constanza (finder/): interno, externo y removible.
            var icono = new Gtk.Image.from_icon_name (v.removible ? "drive-removable-media" : (v.externo ? "drive-harddisk-usb" : "drive-harddisk"), Gtk.IconSize.DIALOG);
            icono.pixel_size = 48;
            icono_col.pack_start (icono, false, false, 0);
            var desc = etiqueta (esc (v.descripcion), "acerca-disco", false);
            desc.justify = Gtk.Justification.CENTER;
            desc.xalign = 0.5f;
            icono_col.pack_start (desc, false, false, 0);
            fila.pack_start (icono_col, false, false, 0);

            var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            col.valign = Gtk.Align.START;
            var cabecera = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var textos = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            textos.pack_start (etiqueta (esc (v.nombre), "acerca-volumen"), false, false, 0);
            // Un volumen sin statfs (APFS por FUSE) solo tiene su tamaño: sin «available of» ni barra.
            textos.pack_start (etiqueta (esc (v.libre < 0 ? tamano_legible (v.tamano)
                                                          : "%s available of %s".printf (tamano_legible (v.libre), tamano_legible (v.tamano))), "acerca-libre"), false, false, 0);
            cabecera.pack_start (textos, true, true, 0);
            if (v.montaje == "/") {          // Manage… (el volumen del sistema): el analizador de disco de Mint
                var manejar = new Gtk.Button.with_label ("Manage…");
                manejar.valign = Gtk.Align.START;
                manejar.clicked.connect (() => lanzar ({ "baobab" }));
                cabecera.pack_end (manejar, false, false, 0);
            }
            col.pack_start (cabecera, false, false, 0);
            var barra = new Gtk.DrawingArea ();
            barra.set_size_request (-1, 20);
            barra.margin_top = 3;
            barra.draw.connect ((cr) => { dibujar_barra (cr, barra, v, categorias_vivas); return true; });
            barras += barra;
            if (v.libre >= 0) col.pack_start (barra, false, false, 0);
            fila.pack_start (col, true, true, 0);
            return fila;
        }

        /** La barra del volumen: por categorías cuando ya se calcularon, gris con «Calculating…» mientras tanto. */
        static void dibujar_barra (Cairo.Context cr, Gtk.DrawingArea barra, Volumen v, Categoria[] cats) {
            int w = barra.get_allocated_width (), h = barra.get_allocated_height ();
            double total = v.tamano > 0 ? v.tamano : 1;
            double usado = (v.tamano - v.libre) / total;
            cr.rectangle (0.5, 0.5, w - 1, h - 1);
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.15);
            cr.fill_preserve ();
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
            cr.set_line_width (1);
            cr.stroke ();
            double x = 1;
            double ancho_usado = (w - 2) * usado;
            var sel = v.categoria_bytes;
            bool listo = v.pendientes <= 0 && sel.length == cats.length;
            if (!listo) {
                cr.rectangle (1, 1, ancho_usado, h - 2);
                cr.set_source_rgba (0.62, 0.62, 0.64, 0.95);
                cr.fill ();
                texto_en_barra (cr, "Calculating…", 6, h);
                return;
            }
            int64 suma = 0;
            for (int i = 0; i < cats.length; i++) {
                if (sel[i] <= 0) continue;
                double ancho = (w - 2) * ((double) sel[i] / total);
                if (x + ancho > 1 + ancho_usado) ancho = 1 + ancho_usado - x;
                if (ancho <= 0) break;
                cr.rectangle (x, 1, ancho, h - 2);
                cr.set_source_rgb (cats[i].r, cats[i].g, cats[i].b);
                cr.fill ();
                if (ancho > 64) texto_en_barra (cr, cats[i].nombre, x + 5, h, true);
                x += ancho;
                suma += sel[i];
            }
            if (x < 1 + ancho_usado) {          // el resto de lo usado: Other
                cr.rectangle (x, 1, 1 + ancho_usado - x, h - 2);
                cr.set_source_rgb (0.66, 0.66, 0.68);
                cr.fill ();
            }
        }

        static void texto_en_barra (Cairo.Context cr, string t, double x, int h, bool claro = false) {
            cr.select_font_face (".SF NS", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (11);
            cr.set_source_rgb (1, 1, 1);
            cr.move_to (x, h / 2.0 + 4);
            cr.show_text (t);
        }

        // ── Memory ──────────────────────────────────────────────────────
        // La forma de la captura de High Sierra: el total instalado a la izquierda y un recuadro por ranura con su módulo.
        // Sin los textos largos («Your Mac contains…», «Installed», el enlace de Apple): no hay fuente en inglés y no se
        // inventan. Los tamaños salen de memoria.ranuras (SMBIOS, vía mint-macos-equipo).
        Gtk.Widget memoria () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
            caja.set_size_request (586, 221);
            caja.margin_start = 40;
            caja.margin_end = 40;
            caja.margin_top = 24;
            int64 total = 0;
            foreach (var b in equipo.ranuras) total += b;
            var fila_total = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            fila_total.pack_start (recuadro_memoria ("%d GB".printf ((int) Math.round (total / 1073741824.0)), true), false, false, 0);
            caja.pack_start (fila_total, false, false, 0);
            var ranuras = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            ranuras.homogeneous = true;
            foreach (var t in ranuras_texto (equipo.ranuras)) ranuras.pack_start (recuadro_memoria (t, false), true, true, 0);
            caja.pack_start (ranuras, false, false, 0);
            return caja;
        }

        static Gtk.Widget recuadro_memoria (string texto, bool total) {
            var a = new Gtk.DrawingArea ();
            a.set_size_request (total ? 100 : -1, total ? 58 : 40);
            a.draw.connect ((cr) => {
                int w = a.get_allocated_width (), h = a.get_allocated_height ();
                cr.rectangle (0.5, 0.5, w - 1, h - 1);
                if (total) cr.set_source_rgb (0.1, 0.55, 0.85); else cr.set_source_rgb (0.55, 0.55, 0.56);
                cr.fill_preserve ();
                if (total) { cr.set_source_rgb (0.2, 0.75, 1.0); cr.set_line_width (2); cr.stroke (); }
                else cr.new_path ();
                cr.select_font_face (".SF NS", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
                cr.set_font_size (total ? 16 : 15);
                Cairo.TextExtents te;
                cr.text_extents (texto, out te);
                cr.set_source_rgb (1, 1, 1);
                cr.move_to ((w - te.width) / 2 - te.x_bearing, (h + te.height) / 2);
                cr.show_text (texto);
                return true;
            });
            return a;
        }

        // ── Support y Service ───────────────────────────────────────────
        // Las pestañas de Apple (Ayuda de Mac, AppleCare…) enseñan aquí los enlaces que trae Linux Mint, tomados de
        // /etc/os-release y /etc/linuxmint/info; un enlace que el sistema no trae no sale.
        Gtk.Widget soporte () {
            var caja = enlaces_con_logo ("%s Resources".printf (equipo.sistema), {
                { "User Guide", url_de ("/etc/linuxmint/info", "USER_GUIDE_URL") },
                { "Release Notes", url_de ("/etc/linuxmint/info", "RELEASE_NOTES_URL") },
                { "Support", url_de ("/etc/os-release", "SUPPORT_URL") }
            });
            caja.set_size_request (586, 301);
            return caja;
        }

        Gtk.Widget servicio () {
            var caja = enlaces_con_logo ("%s Service".printf (equipo.sistema), {
                { "New Features", url_de ("/etc/linuxmint/info", "NEW_FEATURES_URL") },
                { "Troubleshooting Guide", url_de ("/etc/os-release", "BUG_REPORT_URL") }
            });
            caja.set_size_request (586, 301);
            return caja;
        }

        static string url_de (string archivo, string clave) {
            foreach (var l in leer (archivo).split ("\n")) {
                if (l.has_prefix (clave + "=")) return l.substring (clave.length + 1).replace ("\"", "").strip ();
            }
            return "";
        }

        /** Un título grueso a la izquierda con el logo y, a la derecha, los enlaces con su flecha en un círculo. */
        Gtk.Box enlaces_con_logo (string titulo_seccion, string[,] enlaces) {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 40);
            caja.halign = Gtk.Align.CENTER;
            caja.valign = Gtk.Align.CENTER;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            izq.valign = Gtk.Align.CENTER;
            izq.pack_start (etiqueta ("<b>%s</b>".printf (esc (titulo_seccion)), "acerca-fila"), false, false, 0);
            caja.pack_start (izq, false, false, 0);
            caja.pack_start (disco_del_sistema (), false, false, 0);
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            der.valign = Gtk.Align.CENTER;
            for (int i = 0; i < enlaces.length[0]; i++) {
                var url = enlaces[i, 1];
                if (url == "") continue;
                der.pack_start (enlace_con_flecha (enlaces[i, 0], url), false, false, 0);
            }
            caja.pack_start (der, false, false, 0);
            return caja;
        }

        static Gtk.Widget enlace_con_flecha (string texto, string url) {
            var b = new Gtk.Button ();
            b.relief = Gtk.ReliefStyle.NONE;
            b.get_style_context ().add_class ("acerca-enlace-flecha");
            var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var flecha = new Gtk.DrawingArea ();
            flecha.set_size_request (14, 14);
            flecha.draw.connect ((cr) => {           // ➜ en un círculo gris
                cr.arc (7, 7, 6.5, 0, 2 * Math.PI);
                cr.set_source_rgba (0.35, 0.35, 0.37, 1);
                cr.fill ();
                cr.set_source_rgb (1, 1, 1);
                cr.set_line_width (1.6);
                cr.move_to (3.5, 7); cr.line_to (10, 7);
                cr.move_to (7.5, 4); cr.line_to (10.5, 7); cr.line_to (7.5, 10);
                cr.stroke ();
                return true;
            });
            h.pack_start (flecha, false, false, 0);
            h.pack_start (etiqueta (esc (texto), "acerca-fila", false), false, false, 0);
            b.add (h);
            b.clicked.connect (() => lanzar ({ "xdg-open", url }));
            return b;
        }
    }
}
