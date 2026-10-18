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

    /** LAUNCHPAD_DEBUG=1: anota en stderr lo que pasa al mostrarse (para depurar el monitor y el foco). */
    void depurar (string m) {
        if (Environment.get_variable ("LAUNCHPAD_DEBUG") != null) {
            stderr.printf ("[launchpad %.3f] %s\n", GLib.get_monotonic_time () / 1000000.0, m);
        }
    }

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
        // Reordenar y armar carpetas: se mantiene pulsado un ícono y se lo lleva (ver al_mover y soltar_arrastre).
        Elemento? pulsado = null;
        uint mantener_id = 0;
        bool arrastrando = false;
        Elemento? arr_el = null;
        double ptr_x = 0;
        double ptr_y = 0;
        int destino = 0;                      // dónde caería: índice en la lista (de la rejilla o de la carpeta abierta)
        Elemento? sobre = null;               // el elemento sobre el que se detuvo, para juntarlos en una carpeta
        double t_sobre = 0;
        int borde_dir = 0;
        double t_borde = 0;
        bool fuera_de_carpeta = false;
        bool renombrando = false;
        string nombre_edit = "";
        bool nombre_reemplaza = false;
        double scroll_acum = 0.0;
        double scroll_hasta = 0.0;
        Cairo.ImageSurface? fondo = null;
        string? ruta_fondo = null;
        Cairo.ImageSurface? lupa = null;
        Cairo.ImageSurface? borrar = null;
        string sello;
        bool adaptable = false;               // sigue al monitor donde cae (no en pruebas con tamaño fijo)

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
                // Muffin solo hace caso del monitor (fullscreen_on_monitor) si la ventana ya está mapeada: se pide al mapearse,
                // con el número de GDK del monitor principal (comprobado con dos pantallas). Sin esto caía en la otra.
                int principal = 0;
                for (int i = 0; i < display.get_n_monitors (); i++) {
                    if (display.get_monitor (i) == pantalla) {
                        principal = i;
                    }
                }
                map_event.connect ((ev) => {
                    depurar ("map_event: pido el monitor %d".printf (principal));
                    fullscreen_on_monitor (get_screen (), principal);
                    fullscreen ();
                    return false;
                });
                fullscreen ();
                adaptable = true;
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
                adaptable = false;
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
            motion_notify_event.connect (al_mover);
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
            depurar ("mostrar (W=%d H=%d)".printf (W, H));
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
            if (adaptable) {
                // Y si aun así cayó en otro, se corrige con el tamaño real de la ventana.
                Timeout.add (150, () => {
                    int w = get_allocated_width (), h = get_allocated_height ();
                    depurar ("a los 150 ms: ventana %dx%d, esperaba %dx%d, visible=%s".printf (w, h, W, H, visible.to_string ()));
                    if (visible && w > 1 && h > 1 && (w != W || h != H)) {
                        aplicar_geometria (w, h);
                        queue_draw ();
                    }
                    return false;
                });
            }
        }

        /** Rehace lo que depende del tamaño de la pantalla: la escala, el centrado y el fondo desenfocado (de caché). */
        void aplicar_geometria (int w, int h) {
            W = w;
            H = h;
            esc = double.min ((double) W / REF_W, (double) H / REF_H);
            dx = (W - REF_W * esc) / 2;
            ruta_fondo = construir_fondo (W, H);
            cargar_fondo ();
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
            if (arrastrando) {
                revisar_borde ();
                queue_draw ();
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

        /** Lo que se pinta en la rejilla: los elementos, y si se está llevando uno, sin él y con un hueco donde caería. */
        GenericArray<Elemento?> vista_rejilla () {
            var v = new GenericArray<Elemento?> ();
            foreach (var e in elementos) {
                if (!(arrastrando && e == arr_el)) {
                    v.add (e);
                }
            }
            if (arrastrando && carpeta == null) {
                int d = int.max (0, int.min ((int) v.length, destino));
                v.insert (d, null);
            }
            return v;
        }

        void pintar_paginas (Cairo.Context cr) {
            var vista = vista_rejilla ();
            uint total = vista.length;
            for (int p = 0; p < paginas; p++) {
                double desp = (p - pos) * W;
                if (desp <= -W || desp >= W) {
                    continue;
                }
                cr.save ();
                cr.translate (desp, 0);
                for (int i = 0; i < por_pagina && (uint) (p * por_pagina + i) < total; i++) {
                    var el = vista[p * por_pagina + i];
                    if (el == null) {
                        continue;
                    }
                    double cx, y;
                    celda (i, out cx, out y);
                    if (el == sobre && ahora () - t_sobre > 0.25) {
                        // lista para juntarse: el fondo claro detrás, como cuando una carpeta recibe un ícono
                        rect_redondo (cr, cx - px (LADO_CARPETA) / 2 - px (6), y + px (ICONO) / 2 - px (LADO_CARPETA) / 2 - px (6),
                                      px (LADO_CARPETA) + px (12), px (LADO_CARPETA) + px (12), px (CARPETA_RADIO + 6));
                        cr.set_source_rgba (1, 1, 1, 0.28);
                        cr.fill ();
                    }
                    pintar_celda (cr, el, cx, y);
                }
                cr.restore ();
            }
            pintar_llevado (cr);
        }

        /** El ícono que se lleva, siguiendo al puntero. */
        void pintar_llevado (Cairo.Context cr) {
            if (!arrastrando || arr_el == null) {
                return;
            }
            cr.push_group ();
            pintar_celda (cr, arr_el, ptr_x, ptr_y - px (ICONO) / 2);
            cr.pop_group_to_source ();
            cr.paint_with_alpha (0.92);
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

        /** Las apps de la página de la carpeta; si se lleva una, sin ella y con un hueco donde caería. */
        GenericArray<Elemento?> vista_carpeta () {
            var v = new GenericArray<Elemento?> ();
            foreach (var a in apps_carpeta ()) {
                if (!(arrastrando && a == arr_el)) {
                    v.add (a);
                }
            }
            if (arrastrando && carpeta != null && !fuera_de_carpeta) {
                int d = int.max (0, int.min ((int) v.length, destino - pag_carpeta * PANEL_FILAS * COLUMNAS));
                v.insert (d, null);
            }
            return v;
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
            texto (cr, renombrando ? nombre_edit + "|" : carpeta.nombre, W / 2.0, y - px (24), px (TITULO_PX), { 1, 1, 1, 1 }, 0, 200);
            double primera = y / esc + PANEL_PRIMERA;
            var vista = vista_carpeta ();
            for (int k = 0; k < (int) vista.length; k++) {
                var a = vista[k];
                if (a == null) {
                    continue;
                }
                double cx, ya;
                celda (k, out cx, out ya, primera);
                pintar_celda (cr, a, cx, ya);
            }
            pintar_llevado (cr);
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
            if (renombrando) {
                return tecla_nombre (ev);
            }
            if (ev.keyval == Gdk.Key.Escape && arrastrando) {
                soltar_arrastre (false);
                return true;
            }
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
            if (renombrando) {
                terminar_nombre (true);          // un clic fuera del nombre lo confirma
            }
            hay_arrastre = true;
            arr_x = ev.x;
            arr_y = ev.y;
            ptr_x = ev.x;
            ptr_y = ev.y;
            cancelar_mantener ();
            // Mantener pulsado un ícono lo levanta: se lo lleva a otro lugar o encima de otro para armar una carpeta. La carpeta
            // «Other» (la de Utilities) no se edita.
            if (consulta == "" && !(carpeta != null && carpeta.es_otros)) {
                pulsado = hit (ev.x, ev.y);
                if (pulsado != null) {
                    mantener_id = Timeout.add (450, () => {
                        mantener_id = 0;
                        if (pulsado != null) {
                            empezar_arrastre ();
                        }
                        return false;
                    });
                }
            }
            return true;
        }

        void cancelar_mantener () {
            if (mantener_id != 0) {
                Source.remove (mantener_id);
                mantener_id = 0;
            }
            pulsado = null;
        }

        bool al_mover (Gdk.EventMotion ev) {
            ptr_x = ev.x;
            ptr_y = ev.y;
            if (arrastrando) {
                calcular_destino ();
                queue_draw ();
                return true;
            }
            if (pulsado != null && (Math.fabs (ev.x - arr_x) > px (10) || Math.fabs (ev.y - arr_y) > px (10))) {
                cancelar_mantener ();       // se movió antes de tiempo: es un deslizamiento de página, no un arrastre de ícono
            }
            return false;
        }

        void empezar_arrastre () {
            arrastrando = true;
            hay_arrastre = false;
            arr_el = pulsado;
            pulsado = null;
            sobre = null;
            destino = carpeta != null ? carpeta.apps.index ((App) arr_el) : elementos.index (arr_el);
            calcular_destino ();
            queue_draw ();
        }

        /** La posición de la rejilla (de 0 a `cuantos`) más cercana al puntero. */
        int lugar_mas_cercano (int cuantos, double primera) {
            int mejor = 0;
            double dmin = double.MAX;
            for (int i = 0; i <= int.min (cuantos, (carpeta != null ? PANEL_FILAS * COLUMNAS : por_pagina) - 1); i++) {
                double cx, y;
                celda (i, out cx, out y, primera);
                double dd = Math.hypot (ptr_x - cx, ptr_y - (y + px (ICONO) / 2));
                if (dd < dmin) {
                    dmin = dd;
                    mejor = i;
                }
            }
            return mejor;
        }

        void calcular_destino () {
            sobre = null;
            fuera_de_carpeta = false;
            if (carpeta != null) {
                double yy, aa;
                geom_carpeta (out yy, out aa);
                double x = dx + px (PANEL_X);
                fuera_de_carpeta = !(x <= ptr_x && ptr_x <= x + px (PANEL_ANCHO) && px (yy) <= ptr_y && ptr_y <= px (yy + aa));
                if (!fuera_de_carpeta) {
                    int cuantos = (int) vista_carpeta_sin_hueco ();
                    destino = pag_carpeta * PANEL_FILAS * COLUMNAS + lugar_mas_cercano (cuantos, yy + PANEL_PRIMERA);
                }
                return;
            }
            // la rejilla: ¿sobre el centro de otro elemento? (se espera un momento: así se juntan en una carpeta)
            var sin = new GenericArray<Elemento> ();
            foreach (var e in elementos) {
                if (e != arr_el) {
                    sin.add (e);
                }
            }
            int base_ = pagina * por_pagina;
            int en_pagina = int.max (0, int.min (por_pagina, (int) sin.length - base_));
            Elemento? cand = null;
            for (int i = 0; i < en_pagina; i++) {
                double cx, y;
                celda (i, out cx, out y);
                if (Math.fabs (ptr_x - cx) < px (PASO_X) * 0.26 && Math.fabs (ptr_y - (y + px (ICONO) / 2)) < px (PASO_Y) * 0.28) {
                    cand = sin[base_ + i];
                    break;
                }
            }
            if (cand != null && arr_el is App && (cand is App || (cand is Carpeta && !((Carpeta) cand).es_otros))) {
                sobre = cand;
                if (t_sobre == 0 || sobre_anterior != cand) {
                    t_sobre = ahora ();
                }
                sobre_anterior = cand;
                return;            // sobre un elemento: el hueco no se mueve
            }
            sobre_anterior = null;
            t_sobre = 0;
            if (cand == null) {
                destino = base_ + lugar_mas_cercano (en_pagina, FILA0_Y);
            }
        }

        Elemento? sobre_anterior = null;

        uint vista_carpeta_sin_hueco () {
            uint n = 0;
            foreach (var a in apps_carpeta ()) {
                if (a != arr_el) {
                    n++;
                }
            }
            return n;
        }

        /** Llevando un ícono hasta el borde, pasa de página (tras 0,7 s). */
        void revisar_borde () {
            if (carpeta != null || consulta != "") {
                return;
            }
            int dir = ptr_x < px (60) ? -1 : (ptr_x > W - px (60) ? 1 : 0);
            if (dir == 0) {
                borde_dir = 0;
                return;
            }
            if (borde_dir != dir) {
                borde_dir = dir;
                t_borde = ahora ();
            } else if (ahora () - t_borde > 0.7) {
                ir_pagina (pagina + dir);
                t_borde = ahora ();
                calcular_destino ();
            }
        }

        void soltar_arrastre (bool aplicar) {
            var el = arr_el;
            arrastrando = false;
            arr_el = null;
            cancelar_mantener ();
            if (!aplicar || el == null) {
                sobre = null;
                queue_draw ();
                return;
            }
            if (carpeta != null) {
                if (fuera_de_carpeta) {
                    sacar_de_carpeta ((App) el);
                } else {
                    var app = (App) el;
                    carpeta.apps.remove (app);
                    carpeta.apps.insert (app, int.max (0, int.min ((int) carpeta.apps.length (), destino)));
                }
            } else if (sobre != null && ahora () - t_sobre > 0.25 && el is App) {
                juntar ((App) el, sobre);
            } else {
                elementos.remove (el);
                elementos.insert (el, int.max (0, int.min ((int) elementos.length (), destino)));
            }
            sobre = null;
            sobre_anterior = null;
            t_sobre = 0;
            guardar_diseno (elementos);
            recalcular_paginas ();
            pagina = int.max (0, int.min (paginas - 1, pagina));
            queue_draw ();
        }

        /** Una app que se lleva fuera de su carpeta vuelve a la rejilla; una carpeta que queda con una sola app se deshace. */
        void sacar_de_carpeta (App app) {
            var c = carpeta;
            c.apps.remove (app);
            elementos.append (app);
            if (c.apps.length () <= 1) {
                int pos = elementos.index (c);
                App? resto = c.apps.length () == 1 ? c.apps.nth_data (0) : null;
                elementos.remove (c);
                if (resto != null) {
                    elementos.insert (resto, pos);
                }
            }
            carpeta = null;
            recalcular_paginas ();
            pagina = int.max (0, (int) (elementos.length () - 1) / por_pagina);
            pos = pagina;
        }

        string id_nuevo_de_carpeta () {
            int mayor = 0;
            foreach (var e in elementos) {
                if (e is Carpeta && ((Carpeta) e).id.has_prefix ("c")) {
                    mayor = int.max (mayor, int.parse (((Carpeta) e).id.substring (1)));
                }
            }
            return "c%d".printf (mayor + 1);
        }

        /** Una app encima de otra arma una carpeta «Untitled» (con el nombre listo para escribir); encima de una carpeta, entra. */
        void juntar (App app, Elemento destino_el) {
            elementos.remove (app);
            if (destino_el is Carpeta) {
                ((Carpeta) destino_el).apps.append (app);
                return;
            }
            var otro = (App) destino_el;
            int idx = elementos.index (otro);
            elementos.remove (otro);
            var apps = new List<App> ();
            apps.append (otro);
            apps.append (app);
            var nueva = new Carpeta ("Untitled", (owned) apps);
            nueva.id = id_nuevo_de_carpeta ();
            elementos.insert (nueva, idx);
            carpeta = nueva;
            pag_carpeta = 0;
            t0 = ahora ();
            renombrando = true;
            nombre_edit = "Untitled";
            nombre_reemplaza = true;
        }

        void terminar_nombre (bool confirmar) {
            if (confirmar && carpeta != null) {
                var n = nombre_edit.strip ();
                if (n != "") {
                    carpeta.nombre = n;
                    carpeta.clave = n.casefold ();
                }
                guardar_diseno (elementos);
            }
            renombrando = false;
            nombre_reemplaza = false;
            queue_draw ();
        }

        bool tecla_nombre (Gdk.EventKey ev) {
            uint k = ev.keyval;
            if (k == Gdk.Key.Return || k == Gdk.Key.KP_Enter) {
                terminar_nombre (true);
            } else if (k == Gdk.Key.Escape) {
                terminar_nombre (false);
            } else if (k == Gdk.Key.BackSpace) {
                if (nombre_reemplaza) {
                    nombre_edit = "";
                    nombre_reemplaza = false;
                } else if (nombre_edit.length > 0) {
                    nombre_edit = nombre_edit.substring (0, nombre_edit.index_of_nth_char (nombre_edit.char_count () - 1));
                }
            } else {
                unichar u = Gdk.keyval_to_unicode (k);
                if (u >= 32 && u != 127) {
                    if (nombre_reemplaza) {
                        nombre_edit = "";
                        nombre_reemplaza = false;
                    }
                    nombre_edit += u.to_string ();
                }
            }
            queue_draw ();
            return true;
        }

        bool al_soltar (Gdk.EventButton ev) {
            if (ev.button == 1 && arrastrando) {
                soltar_arrastre (true);
                return true;
            }
            cancelar_mantener ();
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
                if (!carpeta.es_otros) {
                    double ty, ta;
                    geom_carpeta (out ty, out ta);
                    if (Math.fabs (ev.x - W / 2.0) < px (260) && ev.y < px (ty) && ev.y > px (ty) - px (70)) {
                        renombrando = true;
                        nombre_edit = carpeta.nombre;
                        nombre_reemplaza = false;
                        queue_draw ();
                        return true;
                    }
                }
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
