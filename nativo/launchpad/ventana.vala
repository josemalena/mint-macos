/*
 * La ventana del Launchpad de Catalina: pantalla completa sobre el fondo desenfocado, buscador arriba, rejilla de 7×5
 * paginada, puntos de página, y la carpeta «Other». Todas las medidas salen de las capturas de Catalina (1920×1200,
 * 1 px = 1 px) y se escalan con la pantalla.
 */
namespace Launchpad {
    const string GLIFOS = "/.local/share/constanza/glifos-finder";
    const string FUENTE = ".SF NS";

    // ── medidas de la captura de Catalina (pantalla de 1920×1200) ────────
    const int COLUMNAS = 7;
    const int FILAS = 5;                      // 35 por página
    const double ICONO = 112;
    const double PASO_X = 215;
    const double PASO_Y = 193;
    const double COL0_X = 312;                // centro de la primera columna
    const double FILA0_Y = 98;                // arriba del ícono de la primera fila
    const double ETIQUETA_Y = 135;
    const double ETIQUETA_PX = 13.5;
    const double SEL_X = 233;
    const double SEL_Y = 75;
    const double SEL_W = 158;
    const double SEL_H = 171;
    const double BUSC_X = 835;
    const double BUSC_Y = 29;
    const double BUSC_W = 250;
    const double BUSC_H = 23;
    const double PUNTOS_Y = 1066.5;
    const double PUNTO_D = 8;
    const double PUNTO_PASO = 20;
    const double LADO_CARPETA = 124;
    const double CARPETA_RADIO = 11;
    const double MINI = 26;
    const double MINI_PASO = 34;
    const double MINI_X = 16;
    const double MINI_Y = 13;
    const double PANEL_X = 185;
    const double PANEL_ANCHO = 1550;
    const double PANEL_ARRIBA = 70;
    const double PANEL_PRIMERA = 70;
    const double PANEL_ABAJO = 24;
    const double PANEL_RADIO = 28;
    const int PANEL_FILAS = 3;                // una carpeta muestra hasta 3 filas (21) por página
    const double TITULO_PX = 26;

    void rect_redondo (Cairo.Context cr, double x, double y, double w, double h, double r) {
        r = double.min (r, double.min (w / 2, h / 2));
        cr.new_sub_path ();
        cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
        cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
        cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
        cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
        cr.close_path ();
    }

    // Devuelve al sistema la memoria libre del montón (el blur y el cuadro de precalentamiento dejan huecos grandes).
    [CCode (cname = "malloc_trim", cheader_filename = "malloc.h")]
    extern int malloc_trim (size_t pad);

    double ahora () {
        return GLib.get_monotonic_time () / 1000000.0;
    }

    public class Ventana : Gtk.Window {
        public int W;
        public int H;
        double esc;
        double dx;
        List<Elemento> elementos;
        List<App> todas;
        int por_pagina = COLUMNAS * FILAS;
        int paginas;
        public int pagina = 0;
        double pos = 0.0;                    // página mostrada (con animación)
        public string consulta = "";
        int sel = 0;
        public Carpeta? carpeta = null;
        int pag_carpeta = 0;
        public double t0;
        bool hay_arrastre = false;
        double arr_x = 0;
        double arr_y = 0;
        double scroll_acum = 0.0;
        double scroll_hasta = 0.0;
        Cairo.ImageSurface? fondo = null;
        string? ruta_fondo = null;
        Cairo.ImageSurface? lupa = null;
        Cairo.ImageSurface? borrar = null;
        string sello;

        public Ventana (Gtk.Application? app, int ancho = 0, int alto = 0) {
            Object (title: "Launchpad");
            if (app != null) {
                application = app;
            }
            app_paintable = true;
            decorated = false;
            skip_taskbar_hint = true;
            skip_pager_hint = true;
            set_keep_above (true);
            role = "launchpad";
            if (ancho == 0) {
                var display = Gdk.Display.get_default ();
                var pantalla = display.get_primary_monitor () ?? display.get_monitor (0);
                // El gestor de ventanas escoge el monitor de un fullscreen() a secas (con dos pantallas salía en la otra,
                // recortado): se pide el principal por su número.
                var geo = pantalla.get_geometry ();
                // Muffin no hace caso de fullscreen_on_monitor: se coloca la ventana sobre el monitor principal y luego se
                // pide pantalla completa, que el gestor da en el monitor donde está.
                move (geo.x, geo.y);
                set_default_size (geo.width, geo.height);
                for (int i = 0; i < display.get_n_monitors (); i++) {
                    if (display.get_monitor (i) == pantalla) {
                        fullscreen_on_monitor (get_screen (), i);
                    }
                }
                fullscreen ();
                W = geo.width;
                H = geo.height;
            } else {
                W = ancho;
                H = alto;
            }
            string? tam = Environment.get_variable ("LAUNCHPAD_TAM");
            if (tam != null && tam.contains ("x")) {
                var p = tam.split ("x");
                W = int.parse (p[0]);
                H = int.parse (p[1]);
            }
            esc = double.min ((double) W / REF_W, (double) H / REF_H);
            dx = (W - REF_W * esc) / 2;              // centrado si la pantalla no es 16:10
            leer_aplicaciones (out elementos, out todas);
            recalcular_paginas ();
            t0 = ahora ();

            ruta_fondo = construir_fondo (W, H);
            cargar_fondo ();
            lupa = glifo ("SearchMagGlass");
            borrar = glifo ("Cancel");

            add_events (Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK
                        | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.KEY_PRESS_MASK
                        | Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK);
            draw.connect (al_pintar);
            key_press_event.connect (al_tecla);
            button_press_event.connect (al_pulsar);
            button_release_event.connect (al_soltar);
            scroll_event.connect (al_scroll);
            add_tick_callback (cuadro);
            sello = sello_apps ();
        }

        void recalcular_paginas () {
            paginas = int.max (1, (int) Math.ceil ((double) elementos.length () / por_pagina));
        }

        void cargar_fondo () {
            fondo = null;
            if (ruta_fondo != null) {
                var s = new Cairo.ImageSurface.from_png (ruta_fondo);
                if (s.status () == Cairo.Status.SUCCESS) {
                    fondo = s;
                }
            }
        }

        Cairo.ImageSurface? glifo (string nombre) {
            foreach (var e in new string[] { "@2x", "@1x" }) {
                try {
                    var pb = new Gdk.Pixbuf.from_file (Environment.get_home_dir () + GLIFOS + "/" + nombre + e + ".png");
                    return superficie_de (pb);
                } catch (Error err) {
                }
            }
            return null;
        }

        // ── residente: se arma una vez y se muestra y oculta ──────────────
        /** Pinta un cuadro fuera de pantalla para que los íconos queden cargados antes del primer atajo. */
        public void precalentar () {
            double antes = t0;
            t0 -= 10;
            // Una superficie de grabación: carga los íconos sin reservar los 9 MB de píxeles de un cuadro.
            var sup = new Cairo.RecordingSurface (Cairo.Content.COLOR_ALPHA, null);
            al_pintar (new Cairo.Context (sup));
            t0 = antes;
            malloc_trim (0);
        }

        /** Lo deja como recién abierto (página 1, sin búsqueda, sin carpeta) y lo enseña. */
        public void mostrar () {
            string nuevo = sello_apps ();
            if (nuevo != sello) {                       // se instaló o quitó una app
                sello = nuevo;
                leer_aplicaciones (out elementos, out todas);
                recalcular_paginas ();
            }
            string? ruta = construir_fondo (W, H);      // de caché; cambia si cambió el escritorio
            if (ruta != ruta_fondo) {
                ruta_fondo = ruta;
                cargar_fondo ();
            }
            pagina = 0;
            pos = 0.0;
            consulta = "";
            sel = 0;
            carpeta = null;
            pag_carpeta = 0;
            hay_arrastre = false;
            scroll_acum = 0.0;
            scroll_hasta = 0.0;
            t0 = ahora ();
            show_all ();
            present_with_time (Gdk.CURRENT_TIME);
        }

        public void ocultar () {
            hide ();
        }

        // ── geometría ─────────────────────────────────────────────────────
        double px (double v) {
            return v * esc;
        }

        /** (centro x, arriba del ícono) de la posición i de una página. */
        void celda (int i, out double cx, out double y, double y_primera = -1) {
            int col = i % COLUMNAS, fila = i / COLUMNAS;
            cx = dx + px (COL0_X + col * PASO_X);
            y = px ((y_primera < 0 ? FILA0_Y : y_primera) + fila * PASO_Y);
        }

        // ── animación ─────────────────────────────────────────────────────
        bool cuadro (Gtk.Widget w, Gdk.FrameClock clock) {
            bool mover = Math.fabs (pos - pagina) > 0.001;
            if (mover) {
                pos += (pagina - pos) * 0.22;
                if (Math.fabs (pos - pagina) < 0.002) {
                    pos = (double) pagina;
                }
            }
            if (mover || ahora () - t0 < 0.3) {
                queue_draw ();
            }
            return true;
        }

        // ── pintar ────────────────────────────────────────────────────────
        public bool al_pintar (Cairo.Context cr) {
            double alfa = double.min (1.0, (ahora () - t0) / 0.18);
            if (fondo != null) {
                cr.set_source_surface (fondo, 0, 0);
                cr.paint ();
            } else {
                cr.set_source_rgb (0.05, 0.12, 0.25);
                cr.paint ();
            }
            cr.push_group ();
            if (carpeta != null) {
                pintar_carpeta (cr);
            } else {
                pintar_buscador (cr);
                if (consulta != "") {
                    pintar_resultados (cr);
                } else {
                    pintar_paginas (cr);
                    if (paginas > 1) {
                        pintar_puntos (cr);
                    }
                }
            }
            cr.pop_group_to_source ();
            cr.paint_with_alpha (alfa);
            return false;
        }

        /** Pinta (o solo mide, con y fuera de pantalla) una línea de texto; devuelve su ancho. */
        double texto (Cairo.Context cr, string s, double cx, double y, double tam, double[] color = { 1, 1, 1, 1 },
                      double ancho = 0, int peso = 300, bool sombra = true, bool centrado = true) {
            var lay = Pango.cairo_create_layout (cr);
            var fd = new Pango.FontDescription ();
            fd.set_family (FUENTE);
            fd.set_absolute_size (tam * Pango.SCALE);
            fd.set_weight ((Pango.Weight) peso);
            lay.set_font_description (fd);
            lay.set_text (s, -1);
            if (ancho > 0) {
                lay.set_width ((int) (ancho * Pango.SCALE));
                lay.set_ellipsize (Pango.EllipsizeMode.END);
            }
            int w, h;
            lay.get_pixel_size (out w, out h);
            double x = centrado ? cx - w / 2.0 : cx;
            double base_ = (double) lay.get_baseline () / Pango.SCALE;
            double top = y - base_;
            if (sombra) {
                cr.move_to (x, top + 1);
                cr.set_source_rgba (0, 0, 0, 0.45 * color[3]);
                Pango.cairo_show_layout (cr, lay);
            }
            cr.move_to (x, top);
            cr.set_source_rgba (color[0], color[1], color[2], color[3]);
            Pango.cairo_show_layout (cr, lay);
            return w;
        }

        Cairo.ImageSurface? icono_cacheado (App app) {
            if (!app.icono_intentado) {
                app.icono = icono_de (app, (int) ICONO);
                app.icono_intentado = true;
            }
            return app.icono;
        }

        void pintar_superficie (Cairo.Context cr, Cairo.ImageSurface sup, double x, double y, double lado) {
            cr.save ();
            cr.translate (x, y);
            cr.scale (lado / sup.get_width (), lado / sup.get_height ());
            cr.set_source_surface (sup, 0, 0);
            cr.paint ();
            cr.restore ();
        }

        void pintar_celda (Cairo.Context cr, Elemento el, double cx, double y) {
            double lado = px (ICONO);
            if (el is Carpeta) {
                pintar_cuadro_carpeta (cr, (Carpeta) el, cx, y);
            } else {
                var sup = icono_cacheado ((App) el);
                if (sup != null) {
                    pintar_superficie (cr, sup, cx - lado / 2, y, lado);
                }
            }
            texto (cr, el.nombre, cx, y + px (ETIQUETA_Y), px (ETIQUETA_PX), { 1, 1, 1, 1 }, px (190));
        }

        void pintar_cuadro_carpeta (Cairo.Context cr, Carpeta c, double cx, double y) {
            double lado = px (LADO_CARPETA);
            double x = cx - lado / 2;
            double y0 = y + px (ICONO) / 2 - lado / 2 - px (0.5);
            rect_redondo (cr, x, y0, lado, lado, px (CARPETA_RADIO));
            cr.set_source_rgba (0.88, 0.90, 0.95, 0.55);
            cr.fill ();
            int i = 0;
            foreach (var a in c.apps) {
                if (i >= 9) {
                    break;
                }
                if (!a.mini_intentado) {
                    a.mini = icono_de (a, (int) MINI);
                    a.mini_intentado = true;
                }
                if (a.mini != null) {
                    pintar_superficie (cr, a.mini, x + px (MINI_X + (i % 3) * MINI_PASO),
                                       y0 + px (MINI_Y + (i / 3) * MINI_PASO), px (MINI));
                }
                i++;
            }
        }

        void pintar_paginas (Cairo.Context cr) {
            uint total = elementos.length ();
            for (int p = 0; p < paginas; p++) {
                double desp = (p - pos) * W;
                if (desp <= -W || desp >= W) {
                    continue;
                }
                cr.save ();
                cr.translate (desp, 0);
                for (int i = 0; i < por_pagina && (uint) (p * por_pagina + i) < total; i++) {
                    double cx, y;
                    celda (i, out cx, out y);
                    pintar_celda (cr, elementos.nth_data ((uint) (p * por_pagina + i)), cx, y);
                }
                cr.restore ();
            }
        }

        List<App> resultados () {
            var todos = buscar (todas, consulta);
            var salida = new List<App> ();
            int i = 0;
            foreach (var a in todos) {
                if (i++ >= por_pagina) {
                    break;
                }
                salida.append (a);
            }
            return salida;
        }

        void pintar_resultados (Cairo.Context cr) {
            var res = resultados ();
            if (res.length () == 0) {
                texto (cr, "No Results", W / 2.0, px (300), px (26), { 1, 1, 1, 0.5 }, 0, 300, false);
                return;
            }
            sel = int.min (sel, (int) res.length () - 1);
            double cx, y;
            celda (sel, out cx, out y);
            // el resaltado es una celda de 158×171 con el ícono centrado
            rect_redondo (cr, cx - px (SEL_W) / 2, y - px (FILA0_Y - SEL_Y), px (SEL_W), px (SEL_H), px (8));
            cr.set_source_rgba (0, 0, 0.157, 0.72);
            cr.fill ();
            int i = 0;
            foreach (var a in res) {
                celda (i++, out cx, out y);
                pintar_celda (cr, a, cx, y);
            }
        }

        void pintar_puntos (Cairo.Context cr) {
            int n = paginas;
            double cx0 = W / 2.0 - (n - 1) * px (PUNTO_PASO) / 2;
            for (int i = 0; i < n; i++) {
                cr.arc (cx0 + i * px (PUNTO_PASO), px (PUNTOS_Y), px (PUNTO_D) / 2, 0, 2 * Math.PI);
                cr.set_source_rgba (1, 1, 1, i == pagina ? 1.0 : 0.3);
                cr.fill ();
            }
        }

        void pintar_buscador (Cairo.Context cr) {
            double w = px (BUSC_W), h = px (BUSC_H);
            double x = W / 2.0 - w / 2;
            double y = px (BUSC_Y);
            rect_redondo (cr, x + 0.5, y + 0.5, w - 1, h - 1, px (3.5));
            cr.set_source_rgba (1, 1, 1, 0.066);
            cr.fill_preserve ();
            cr.set_source_rgba (1, 1, 1, 0.2);
            cr.set_line_width (1);
            cr.stroke ();
            double tam = px (15.5);
            double lupa_w = 14 * esc;
            if (consulta != "") {
                glifo_pintar (cr, lupa, x + px (7), y + h / 2 - lupa_w / 2, lupa_w, 0.7);
                texto (cr, consulta, x + px (27), y + h / 2 + tam * 0.36, tam, { 1, 1, 1, 1 }, w - px (55), 300, false, false);
                glifo_pintar (cr, borrar, x + w - px (21), y + h / 2 - lupa_w / 2, lupa_w, 0.6);
            } else {
                double ancho_t = texto (cr, "Search", 0, -100, tam, { 1, 1, 1, 1 }, 0, 300, false);  // solo mide
                double total = lupa_w + px (6) + ancho_t;
                double ix = W / 2.0 - total / 2;
                glifo_pintar (cr, lupa, ix, y + h / 2 - lupa_w / 2, lupa_w, 0.55);
                texto (cr, "Search", ix + lupa_w + px (6), y + h / 2 + tam * 0.36, tam, { 1, 1, 1, 0.5 }, 0, 300, false, false);
            }
        }

        void glifo_pintar (Cairo.Context cr, Cairo.ImageSurface? sup, double x, double y, double lado, double alfa) {
            if (sup == null) {
                return;
            }
            cr.save ();
            cr.translate (x, y);
            cr.scale (lado / sup.get_width (), lado / sup.get_height ());
            cr.set_source_rgba (1, 1, 1, alfa);
            cr.mask_surface (sup, 0, 0);
            cr.restore ();
        }

        List<App> apps_carpeta () {
            int n = PANEL_FILAS * COLUMNAS;
            var salida = new List<App> ();
            int i = 0;
            foreach (var a in carpeta.apps) {
                if (i >= pag_carpeta * n && i < (pag_carpeta + 1) * n) {
                    salida.append (a);
                }
                i++;
            }
            return salida;
        }

        int paginas_carpeta () {
            return int.max (1, (int) Math.ceil ((double) carpeta.apps.length () / (PANEL_FILAS * COLUMNAS)));
        }

        void geom_carpeta (out double y, out double alto) {
            int filas = int.min (PANEL_FILAS, int.max (1, (int) Math.ceil ((double) carpeta.apps.length () / COLUMNAS)));
            alto = PANEL_ARRIBA + filas * PASO_Y + PANEL_ABAJO;
            y = REF_H / 2.0 - alto / 2 - 1.5;
        }

        void pintar_carpeta (Cairo.Context cr) {
            double y0, alto0;
            geom_carpeta (out y0, out alto0);
            double x = dx + px (PANEL_X);
            double w = px (PANEL_ANCHO);
            double y = px (y0), alto = px (alto0);
            // la sombra suave que oscurece el fondo alrededor
            for (int i = 10; i > 0; i--) {
                rect_redondo (cr, x - i * 6, y - i * 6, w + i * 12, alto + i * 12, px (PANEL_RADIO) + i * 6);
                cr.set_source_rgba (0, 0, 0, 0.022);
                cr.fill ();
            }
            rect_redondo (cr, x, y, w, alto, px (PANEL_RADIO));
            cr.set_source_rgba (0.88, 0.90, 0.95, 0.55);
            cr.fill ();
            texto (cr, carpeta.nombre, W / 2.0, y - px (24), px (TITULO_PX), { 1, 1, 1, 1 }, 0, 200);
            double primera = y / esc + PANEL_PRIMERA;
            int i = 0;
            foreach (var a in apps_carpeta ()) {
                double cx, ya;
                celda (i++, out cx, out ya, primera);
                pintar_celda (cr, a, cx, ya);
            }
            int n = paginas_carpeta ();
            if (n > 1) {
                double cx0 = W / 2.0 - (n - 1) * px (PUNTO_PASO) / 2;
                for (int j = 0; j < n; j++) {
                    cr.arc (cx0 + j * px (PUNTO_PASO), y + alto - px (14), px (PUNTO_D) / 2, 0, 2 * Math.PI);
                    cr.set_source_rgba (1, 1, 1, j == pag_carpeta ? 1.0 : 0.35);
                    cr.fill ();
                }
            }
        }

        // ── entrada ───────────────────────────────────────────────────────
        /** El elemento bajo el puntero (App o Carpeta) o null. */
        Elemento? hit (double mx, double my) {
            var lista = new List<Elemento> ();
            double primera = FILA0_Y;
            if (carpeta != null) {
                foreach (var a in apps_carpeta ()) {
                    lista.append (a);
                }
                double yy, aa;
                geom_carpeta (out yy, out aa);
                primera = yy + PANEL_PRIMERA;
            } else if (consulta != "") {
                foreach (var a in resultados ()) {
                    lista.append (a);
                }
            } else {
                uint total = elementos.length ();
                for (int i = 0; i < por_pagina && (uint) (pagina * por_pagina + i) < total; i++) {
                    lista.append (elementos.nth_data ((uint) (pagina * por_pagina + i)));
                }
            }
            int i = 0;
            foreach (var el in lista) {
                double cx, y;
                celda (i++, out cx, out y, primera);
                if (Math.fabs (mx - cx) <= px (PASO_X) / 2 - 20 && y - 10 <= my && my <= y + px (ETIQUETA_Y + 12)) {
                    return el;
                }
            }
            return null;
        }

        void abrir_elemento (Elemento el) {
            if (el is Carpeta) {
                carpeta = (Carpeta) el;
                pag_carpeta = 0;
                t0 = ahora ();
                queue_draw ();
            } else {
                ((App) el).lanzar ();
                cerrar ();
            }
        }

        /** Como en la Mac, el Launchpad no sale: se esconde y el siguiente atajo lo vuelve a enseñar. */
        void cerrar () {
            ocultar ();
        }

        void ir_pagina (int n) {
            n = int.max (0, int.min (paginas - 1, n));
            if (n != pagina) {
                pagina = n;
                queue_draw ();
            }
        }

        bool al_tecla (Gdk.EventKey ev) {
            uint k = ev.keyval;
            if (k == Gdk.Key.Escape) {
                if (consulta != "") {
                    consulta = "";
                    sel = 0;
                } else if (carpeta != null) {
                    carpeta = null;
                } else {
                    cerrar ();
                }
                queue_draw ();
                return true;
            }
            if (k == Gdk.Key.Return || k == Gdk.Key.KP_Enter) {
                if (consulta != "") {
                    var res = resultados ();
                    if (res.length () > 0) {
                        abrir_elemento (res.nth_data ((uint) int.min (sel, (int) res.length () - 1)));
                    }
                }
                return true;
            }
            if (k == Gdk.Key.BackSpace) {
                if (consulta.length > 0) {
                    consulta = consulta.substring (0, consulta.index_of_nth_char (consulta.char_count () - 1));
                }
                sel = 0;
                queue_draw ();
                return true;
            }
            if (k == Gdk.Key.Left || k == Gdk.Key.Right || k == Gdk.Key.Up || k == Gdk.Key.Down) {
                int d = 0;
                if (k == Gdk.Key.Left) {
                    d = -1;
                } else if (k == Gdk.Key.Right) {
                    d = 1;
                } else if (k == Gdk.Key.Up) {
                    d = -COLUMNAS;
                } else {
                    d = COLUMNAS;
                }
                if (consulta != "") {
                    int n = (int) resultados ().length ();
                    sel = int.max (0, int.min (n - 1, sel + d));
                } else if (d.abs () == 1 && carpeta == null) {
                    ir_pagina (pagina + d);
                } else if (d.abs () == 1) {
                    pag_carpeta = int.max (0, int.min (paginas_carpeta () - 1, pag_carpeta + d));
                }
                queue_draw ();
                return true;
            }
            if (k == Gdk.Key.Tab) {
                return true;
            }
            string ch = ev.str;
            if (ch != null && ch != "" && ch.get_char ().isprint ()
                && (ev.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK)) == 0) {
                carpeta = null;
                consulta += ch;
                sel = 0;
                queue_draw ();
                return true;
            }
            return false;
        }

        bool al_pulsar (Gdk.EventButton ev) {
            if (ev.button != 1) {
                return true;
            }
            hay_arrastre = true;
            arr_x = ev.x;
            arr_y = ev.y;
            return true;
        }

        bool al_soltar (Gdk.EventButton ev) {
            if (ev.button != 1 || !hay_arrastre) {
                return true;
            }
            hay_arrastre = false;
            double d_x = ev.x - arr_x;
            if (Math.fabs (d_x) > px (80) && consulta == "") {
                int d = d_x > 0 ? -1 : 1;
                if (carpeta == null) {
                    ir_pagina (pagina + d);
                } else {
                    pag_carpeta = int.max (0, int.min (paginas_carpeta () - 1, pag_carpeta + d));
                    queue_draw ();
                }
                return true;
            }
            if (Math.fabs (d_x) > 8 || Math.fabs (ev.y - arr_y) > 8) {
                return true;
            }
            // un clic
            if (carpeta != null) {
                var el = hit (ev.x, ev.y);
                if (el != null) {
                    abrir_elemento (el);
                    return true;
                }
                double y, alto;
                geom_carpeta (out y, out alto);
                double x = dx + px (PANEL_X);
                bool dentro = x <= ev.x && ev.x <= x + px (PANEL_ANCHO) && px (y) <= ev.y && ev.y <= px (y + alto);
                if (!dentro) {
                    carpeta = null;
                    queue_draw ();
                }
                return true;
            }
            // un clic en el buscador no cierra: ya escribe ahí
            if (Math.fabs (ev.x - W / 2.0) <= px (BUSC_W) / 2 && px (BUSC_Y) - 4 <= ev.y && ev.y <= px (BUSC_Y + BUSC_H) + 4) {
                if (!(consulta != "" && ev.x > W / 2.0 + px (BUSC_W) / 2 - px (26))) {   // salvo el botón de borrar
                    return true;
                }
            }
            // los puntos de página
            if (consulta == "" && paginas > 1 && Math.fabs (ev.y - px (PUNTOS_Y)) < px (14)) {
                int n = paginas;
                double cx0 = W / 2.0 - (n - 1) * px (PUNTO_PASO) / 2;
                int i = (int) Math.round ((ev.x - cx0) / px (PUNTO_PASO));
                if (i >= 0 && i < n) {
                    ir_pagina (i);
                    return true;
                }
            }
            // el botón de borrar de la búsqueda
            if (consulta != "") {
                if (Math.fabs (ev.x - (W / 2.0 + px (BUSC_W) / 2 - px (14))) < px (10)
                    && Math.fabs (ev.y - px (BUSC_Y + BUSC_H / 2)) < px (12)) {
                    consulta = "";
                    sel = 0;
                    queue_draw ();
                    return true;
                }
            }
            var el2 = hit (ev.x, ev.y);
            if (el2 != null) {
                abrir_elemento (el2);
            } else {
                cerrar ();     // un clic en el vacío cierra, como en Catalina
            }
            return true;
        }

        bool al_scroll (Gdk.EventScroll ev) {
            if (consulta != "" || carpeta != null) {
                return true;
            }
            if (ev.direction == Gdk.ScrollDirection.SMOOTH) {
                double ddx, ddy;
                ev.get_scroll_deltas (out ddx, out ddy);
                double d = Math.fabs (ddx) > Math.fabs (ddy) ? ddx : ddy;
                scroll_acum += d;
                if (ahora () > scroll_hasta && Math.fabs (scroll_acum) >= 1.0) {
                    ir_pagina (pagina + (scroll_acum > 0 ? 1 : -1));
                    scroll_acum = 0.0;
                    scroll_hasta = ahora () + 0.4;
                }
            } else if (ev.direction == Gdk.ScrollDirection.RIGHT || ev.direction == Gdk.ScrollDirection.DOWN) {
                ir_pagina (pagina + 1);
            } else if (ev.direction == Gdk.ScrollDirection.LEFT || ev.direction == Gdk.ScrollDirection.UP) {
                ir_pagina (pagina - 1);
            }
            return true;
        }

        // ── para las pruebas: un cuadro a PNG ────────────────────────────
        public bool a_png (string archivo, int pag, string cons, bool abrir_carpeta) {
            t0 -= 10;
            pagina = pag;
            pos = pag;
            consulta = cons;
            if (abrir_carpeta) {
                foreach (var e in elementos) {
                    if (e is Carpeta) {
                        carpeta = (Carpeta) e;
                        break;
                    }
                }
            }
            var sup = new Cairo.ImageSurface (Cairo.Format.ARGB32, W, H);
            al_pintar (new Cairo.Context (sup));
            return sup.write_to_png (archivo) == Cairo.Status.SUCCESS;
        }

        public void lista_a_texto () {
            foreach (var e in elementos) {
                if (e is Carpeta) {
                    var c = (Carpeta) e;
                    var sb = new StringBuilder ();
                    foreach (var a in c.apps) {
                        sb.append (sb.len > 0 ? ", " : "").append (a.nombre);
                    }
                    stdout.printf ("[%s] %s\n", c.nombre, sb.str);
                } else {
                    stdout.printf ("%s\n", e.nombre);
                }
            }
        }
    }
}
