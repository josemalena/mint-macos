/*
 * La ventana de System Preferences con el diseño de Catalina: barra de herramientas (atrás, adelante, Show All y búsqueda),
 * la cuadrícula de paneles por grupos y, al abrir uno, su página. Port de settings/preferencias.py (la ventana; los paneles
 * que todavía no están en Vala se abren con el de Python, ver PanelPython).
 */
namespace Preferencias {

    /** La caja de resultados de la búsqueda, pegada debajo del campo y del mismo ancho. */
    class ListaResultados : Gtk.Window {
        Gtk.Widget campo;

        public ListaResultados (Gtk.Widget campo) {
            Object (type: Gtk.WindowType.POPUP);
            this.campo = campo;
            set_decorated (false);
            set_resizable (false);
            set_skip_taskbar_hint (true);
            get_style_context ().add_class ("mp-resultados");
        }

        public void emerger () {
            var ventana = campo.get_window ();
            if (ventana == null) {
                return;
            }
            int x, y;
            ventana.get_origin (out x, out y);
            Gtk.Allocation a;
            campo.get_allocation (out a);
            set_size_request (a.width, -1);
            resize (a.width, 1);
            move (x + a.x, y + a.y + a.height);
            show_all ();
        }

        public void esconder () {
            hide ();
        }
    }

    class FilaResultado : Gtk.ListBoxRow {
        public Panel? panel;
    }

    public class Ventana : Gtk.ApplicationWindow {
        // La cuadrícula es el primer paso del historial (null): de un panel se vuelve a ella.
        GenericArray<string?> historial = new GenericArray<string?> ();
        int pos = 0;
        public Panel? actual = null;               // el panel abierto, o null en la cuadrícula
        public GenericArray<Panel> todos = new GenericArray<Panel> ();
        List<GrupoPaneles> grupos = new List<GrupoPaneles> ();
        Panel panel_apple;
        string? apple_id_conocido = null;
        /** Lo último que dijo el servicio de Apple ID (null si no contestó); el panel de Apple ID lo lee. */
        public EstadoAppleID? estado_apple = null;

        Gtk.Stack pila;
        Gtk.Box content_box;
        Gtk.Box cuadricula;
        Gtk.Overlay overlay_cuadricula;
        Gtk.ScrolledWindow sw_contenido;
        Gtk.Box banner;
        Gtk.Button b_atras;
        Gtk.Button b_adelante;
        Gtk.Image i_atras;
        Gtk.Image i_adelante;
        public Gtk.SearchEntry buscar;
        ListaResultados resultados;
        Gtk.ListBox lista;
        Gtk.DrawingArea velo;
        List<Panel> hallados_velo = new List<Panel> ();

        public Ventana (Aplicacion app) {
            Object (application: app, title: TITULO);
            set_default_size (ANCHO, 540);
            set_icon_name ("preferences-system");
            get_style_context ().add_class ("mp-ventana");
            historial.add (null);
            // Como en la Mac, cerrar la ventana no cierra el programa: se esconde y el siguiente clic en el ítem del menú o el
            // atajo la vuelve a enseñar sin cargar nada otra vez.
            delete_event.connect (() => {
                var a = application as Aplicacion;
                if (a != null && a.residente) {
                    hide ();
                    return true;
                }
                return false;
            });

            cargar_css ();
            var raiz = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            add (raiz);
            set_titlebar (barra ());

            pila = new Gtk.Stack ();
            pila.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
            pila.set_transition_duration (120);
            pila.vhomogeneous = false;             // el alto lo manda la página visible: la cuadrícula no hereda el de un panel
            raiz.pack_start (pila, true, true, 0);

            content_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            content_box.get_style_context ().add_class ("mp-contenido");

            grupos = armar_paneles ();
            foreach (var g in grupos) {
                foreach (var p in g.paneles) {
                    todos.add (p);
                }
            }
            // Apple ID no está en la cuadrícula: se abre desde la franja de arriba.
            panel_apple = new PanelAppleID ();
            todos.add (panel_apple);
            for (int i = 0; i < todos.length; i++) {
                todos[i].ventana = this;
            }

            pila.add_named (cuadricula_nueva (), "cuadricula");
            set_default_size (ANCHO, alto_cuadricula ());
            pila.add_named (pagina (), "pagina");
            // Solo los hijos: la ventana se enseña cuando alguien la pide (el residente nace escondido).
            raiz.show_all ();
            get_titlebar ().show_all ();
            mostrar_todo (false);
        }

        Gtk.CssProvider? css_claro = null;
        bool claro_aplicado = false;

        void cargar_css () {
            var proveedor = new Gtk.CssProvider ();
            try {
                proveedor.load_from_path (Path.build_filename (carpeta_python (), "estilo", "catalina.css"));
            } catch (Error e) {
                warning ("CSS: %s", e.message);
            }
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), proveedor, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            // catalina.css es el oscuro; con un tema claro se le pone encima catalina-claro.css (y se suelta al volver al oscuro).
            css_claro = new Gtk.CssProvider ();
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_claro, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
            Gtk.Settings.get_default ().notify["gtk-theme-name"].connect (() => {
                // El tema nuevo se carga justo después de la señal: se espera un momento para leer sus colores.
                Timeout.add (250, () => { aplicar_claro (); return false; });
            });
            Idle.add (() => { aplicar_claro (); return false; });
        }

        /** ¿Los colores del tema puesto son claros? (el fondo de las ventanas, por luminancia) */
        bool tema_claro () {
            Gdk.RGBA c;
            if (!get_style_context ().lookup_color ("theme_bg_color", out c)) {
                return false;
            }
            return 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue > 0.5;
        }

        void aplicar_claro () {
            bool claro = tema_claro ();
            if (claro == claro_aplicado) {
                return;
            }
            claro_aplicado = claro;
            try {
                if (claro) {
                    css_claro.load_from_path (Path.build_filename (carpeta_python (), "estilo", "catalina-claro.css"));
                } else {
                    css_claro.load_from_data ("");
                }
            } catch (Error e) {
                warning ("CSS claro: %s", e.message);
            }
        }

        // ── barra de herramientas ────────────────────────────────────────
        /**
         * Barra unificada: los semáforos, los botones y el buscador en la misma franja, como en Catalina. Es un GtkHeaderBar
         * (CSD); Muffin solo mueve la ventana. Los semáforos los pinta el tema (headerbar button.titlebutton).
         */
        Gtk.Widget barra () {
            var barra = new Gtk.HeaderBar ();
            barra.show_close_button = true;
            barra.decoration_layout = "close,minimize,maximize:";
            var titulo = new Gtk.Label (TITULO);
            titulo.get_style_context ().add_class ("mp-titulo");
            barra.custom_title = titulo;
            // El título de la barra sigue al de la ventana (el nombre del panel abierto).
            notify["title"].connect (() => titulo.set_text (get_title () ?? TITULO));
            barra.get_style_context ().add_class ("mp-barra");

            var flechas = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            flechas.get_style_context ().add_class ("linked");
            b_atras = new Gtk.Button ();
            b_adelante = new Gtk.Button ();
            var b_todo = new Gtk.Button ();
            i_atras = glifo ("GoBack", "go-previous-symbolic");
            i_adelante = glifo ("GoForward", "go-next-symbolic");
            b_atras.add (i_atras);
            b_adelante.add (i_adelante);
            b_atras.set_tooltip_text ("Back");
            b_adelante.set_tooltip_text ("Forward");
            b_atras.clicked.connect (() => ir (-1));
            b_adelante.clicked.connect (() => ir (1));
            flechas.pack_start (b_atras, false, false, 0);
            flechas.pack_start (b_adelante, false, false, 0);
            barra.pack_start (flechas);

            b_todo.add (glifo ("ToolbarTopSites", "view-grid-symbolic"));
            b_todo.set_tooltip_text ("Show All");
            b_todo.clicked.connect (() => mostrar_todo ());
            barra.pack_start (b_todo);

            buscar = new Gtk.SearchEntry ();
            buscar.set_placeholder_text ("Search");
            buscar.set_size_request (BUSCADOR_ANCHO, -1);
            buscar.search_changed.connect (buscando);
            buscar.activate.connect (buscar_enter);
            barra.pack_end (buscar);

            // La lista de resultados: una caja plana pegada al campo (captura 1.27.39 PM), sin la flecha ni las esquinas de un
            // popover. Es una ventana POPUP sin decorar, que no toma el foco: se sigue escribiendo.
            resultados = new ListaResultados (buscar);
            hide.connect (() => resultados.esconder ());
            lista = new Gtk.ListBox ();
            lista.set_selection_mode (Gtk.SelectionMode.SINGLE);
            lista.row_activated.connect ((fila) => abrir_desde_busqueda (fila as FilaResultado));
            resultados.add (lista);
            actualizar_flechas ();
            return barra;
        }

        // ── la cuadrícula ────────────────────────────────────────────────
        Gtk.Widget cuadricula_nueva () {
            cuadricula = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            cuadricula.get_style_context ().add_class ("mp-cuadricula");
            cuadricula.pack_start (banner_nuevo (), false, false, 0);
            foreach (var g in grupos) {
                var raya = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
                raya.get_style_context ().add_class ("mp-raya");
                cuadricula.pack_start (raya, false, false, 0);
                var fila = new Gtk.Grid ();
                fila.column_homogeneous = true;
                fila.halign = Gtk.Align.START;
                fila.get_style_context ().add_class ("mp-grupo");
                int n = 0;
                foreach (var pv in g.paneles) {
                    fila.attach (celda_de (pv), n % COLUMNAS, n / COLUMNAS, 1, 1);
                    n++;
                }
                // Las columnas que sobran se rellenan para que las filas cortas queden a la izquierda, con las celdas del mismo
                // ancho que las de arriba.
                int total = n < COLUMNAS ? COLUMNAS : n;
                for (int i = n; i < total; i++) {
                    var hueco = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                    hueco.set_size_request (80, 1);
                    fila.attach (hueco, i % COLUMNAS, i / COLUMNAS, 1, 1);
                }
                cuadricula.pack_start (fila, false, false, 0);
            }
            var sw = new Gtk.ScrolledWindow (null, null);
            sw.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            sw.set_shadow_type (Gtk.ShadowType.NONE);
            sw.add (cuadricula);
            // El velo de la búsqueda (captura 1.27.39 PM): oscurece la cuadrícula y deja con halo los paneles que coinciden.
            // Va encima, sin recibir clics.
            velo = new Gtk.DrawingArea ();
            velo.set_can_focus (false);
            velo.draw.connect (pintar_velo);
            velo.no_show_all = true;
            overlay_cuadricula = new Gtk.Overlay ();
            overlay_cuadricula.add (sw);
            overlay_cuadricula.add_overlay (velo);
            overlay_cuadricula.set_overlay_pass_through (velo, true);
            return overlay_cuadricula;
        }

        /** Un velo oscuro con un hueco suave (y un halo claro) sobre cada panel que coincide. */
        bool pintar_velo (Cairo.Context cr) {
            // Todo en un grupo aparte: DEST_OUT sobre la ventana misma borraría también lo que hay debajo.
            cr.push_group ();
            cr.set_operator (Cairo.Operator.OVER);
            cr.set_source_rgba (0.07, 0.07, 0.07, 0.80);
            cr.paint ();
            foreach (var pv in hallados_velo) {
                var celda = pv.celda;
                if (celda == null || !celda.get_mapped ()) {
                    continue;
                }
                int x, y;
                if (!celda.translate_coordinates (velo, 0, 0, out x, out y)) {
                    continue;
                }
                double cx = x + celda.get_allocated_width () / 2.0;
                double cy = y + celda.get_allocated_height () / 2.0 - 4;
                // El halo: un disco claro y suave; encima se destapa el ícono.
                var halo = new Cairo.Pattern.radial (cx, cy, 8, cx, cy, 46);
                halo.add_color_stop_rgba (0, 1, 1, 1, 0.16);
                halo.add_color_stop_rgba (0.75, 1, 1, 1, 0.10);
                halo.add_color_stop_rgba (1, 1, 1, 1, 0.0);
                cr.set_operator (Cairo.Operator.DEST_OUT);
                var hueco = new Cairo.Pattern.radial (cx, cy, 20, cx, cy, 58);
                hueco.add_color_stop_rgba (0, 0, 0, 0, 1);
                hueco.add_color_stop_rgba (1, 0, 0, 0, 0);
                cr.set_source (hueco);
                cr.arc (cx, cy, 58, 0, 6.2832);
                cr.fill ();
                cr.set_operator (Cairo.Operator.OVER);
                cr.set_source (halo);
                cr.arc (cx, cy, 46, 0, 6.2832);
                cr.fill ();
            }
            cr.pop_group_to_source ();
            cr.set_operator (Cairo.Operator.OVER);
            cr.paint ();
            return false;
        }

        /**
         * La franja de arriba: el Apple ID, como en Catalina. Sin sesión, «Sign in to your Apple ID» con su botón; con sesión,
         * el nombre y el Apple ID. La hoja de Sign In y el panel hablan con org.mintmacos.AppleID1 (appleid.vala).
         */
        Gtk.Widget banner_nuevo () {
            banner = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            banner.get_style_context ().add_class ("mp-banner");
            pintar_banner (null);
            Idle.add (() => { leer_apple_id.begin (); return false; });
            AppleID.vigilar (() => leer_apple_id.begin ());
            return banner;
        }

        /** El servicio puede tardar (activarse, rclone): se pregunta aparte y la franja se rehace. */
        async void leer_apple_id () {
            estado_apple = yield AppleID.estado ();
            string? actual = (estado_apple != null && estado_apple.apple_id != "") ? estado_apple.apple_id : null;
            pintar_banner (actual);
            // Con el panel de Apple ID abierto, se rehace con lo nuevo.
            if (this.actual == panel_apple) {
                abrir (panel_apple, false);
            }
        }

        /** La hoja de Sign In; con solo_mail (el «Set Up…» del panel) la sesión ya está y va directo a Mail y Calendar. */
        public void hoja_apple_id (bool solo_mail) {
            var hoja = new HojaAppleID (this, apple_id_conocido);
            hoja.terminado.connect (() => leer_apple_id.begin ());
            if (solo_mail) hoja.ir_a_mail ();
            hoja.show_all ();
        }

        public void cerrar_sesion_apple_id () {
            var d = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE,
                                           "Sign out of your Apple ID?");
            d.format_secondary_text ("iCloud Drive is unmounted and its session removed. Mail and Calendar settings added to Thunderbird "
                                     + "are removed too. Your files in iCloud are not touched.");
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            d.add_button ("Sign Out", Gtk.ResponseType.OK);
            d.response.connect ((r) => {
                d.destroy ();
                if (r == Gtk.ResponseType.OK) {
                    AppleID.cerrar_sesion.begin ((o, res) => {
                        AppleID.cerrar_sesion.end (res);
                        leer_apple_id.begin ();
                    });
                }
            });
            d.show ();
        }

        void pintar_banner (string? actual) {
            apple_id_conocido = actual;
            foreach (var c in banner.get_children ()) {
                banner.remove (c);
            }
            banner.pack_start (avatar (actual != null ? 56 : 64, actual == null), false, false, 0);
            var textos = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            string t1, t2;
            if (actual != null) {
                t1 = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
                t2 = actual;
            } else {
                t1 = "Sign in to your Apple ID";
                t2 = "Set up iCloud, the App Store, and more.";
            }
            var nombre = new Gtk.Label (t1);
            nombre.xalign = 0;
            nombre.get_style_context ().add_class ("mp-nombre");
            var sub = new Gtk.Label (t2);
            sub.xalign = 0;
            sub.get_style_context ().add_class ("mp-subtitulo");
            textos.pack_start (nombre, false, false, 0);
            textos.pack_start (sub, false, false, 0);
            banner.pack_start (textos, true, true, 0);
            if (actual == null) {
                var b = new Gtk.Button.with_label ("Sign In");
                b.valign = Gtk.Align.CENTER;
                b.clicked.connect (() => hoja_apple_id (false));
                banner.pack_start (b, false, false, 0);
                // Sin sesión Catalina solo enseña la silueta, el texto y Sign In (captura 1.31.45 PM): el ícono de Apple ID, a la
                // derecha, sale únicamente con sesión.
                banner.show_all ();
                return;
            }
            // El ícono de Apple ID, a la derecha como en Catalina: abre su panel.
            var celda = new Gtk.Button ();
            celda.set_relief (Gtk.ReliefStyle.NONE);
            celda.get_style_context ().add_class ("mp-celda");
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            caja.pack_start (imagen_icono (panel_apple.id, "avatar-default", ICONO), false, false, 0);
            caja.pack_start (new Gtk.Label ("Apple ID"), false, false, 0);
            celda.add (caja);
            celda.set_size_request (80, -1);
            celda.clicked.connect (() => abrir (panel_apple));
            banner.pack_start (celda, false, false, 0);
            banner.show_all ();
        }

        Gtk.Widget avatar (int lado, bool generico) {
            var area = new Gtk.DrawingArea ();
            area.set_size_request (lado, lado);
            if (generico) {
                // La silueta gris de Catalina sin sesión: un círculo gris con la cabeza y los hombros en claro.
                area.draw.connect ((cr) => {
                    cr.arc (lado / 2.0, lado / 2.0, lado / 2.0, 0, 2 * Math.PI);
                    cr.clip_preserve ();
                    cr.set_source_rgb (0.62, 0.62, 0.64);
                    cr.fill ();
                    cr.set_source_rgb (0.97, 0.97, 0.98);
                    cr.arc (lado / 2.0, lado * 0.40, lado * 0.20, 0, 2 * Math.PI);
                    cr.fill ();
                    cr.arc (lado / 2.0, lado * 1.02, lado * 0.36, 0, 2 * Math.PI);
                    cr.fill ();
                    return false;
                });
                return area;
            }
            Gdk.Pixbuf? pb = null;
            var rutas = new string[] { Path.build_filename (Environment.get_home_dir (), ".face"),
                                       "/var/lib/AccountsService/icons/" + Environment.get_user_name () };
            foreach (var ruta in rutas) {
                try {
                    if (FileUtils.test (ruta, FileTest.EXISTS)) {
                        pb = new Gdk.Pixbuf.from_file_at_scale (ruta, lado, lado, false);
                        break;
                    }
                } catch (Error e) {
                }
            }
            if (pb == null) {
                pb = pixbuf_icono ("", "avatar-default", lado);
            }
            var foto = pb;
            area.draw.connect ((cr) => {
                cr.arc (lado / 2.0, lado / 2.0, lado / 2.0, 0, 2 * Math.PI);
                cr.clip ();
                if (foto != null) {
                    Gdk.cairo_set_source_pixbuf (cr, foto, 0, 0);
                    cr.paint ();
                } else {
                    cr.set_source_rgb (0.5, 0.5, 0.52);
                    cr.paint ();
                }
                return false;
            });
            return area;
        }

        Gtk.Widget celda_de (Panel pv) {
            var boton = new Gtk.Button ();
            boton.set_relief (Gtk.ReliefStyle.NONE);
            boton.get_style_context ().add_class ("mp-celda");
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            caja.pack_start (imagen_icono (pv.id, pv.icono_tema, ICONO), false, false, 0);
            var et = new Gtk.Label (pv.nombre);
            et.set_line_wrap (true);
            et.set_justify (Gtk.Justification.CENTER);
            et.set_max_width_chars (10);
            et.set_lines (3);
            caja.pack_start (et, false, false, 0);
            boton.add (caja);
            boton.set_size_request (80, -1);
            boton.clicked.connect (() => abrir (pv));
            pv.celda = boton;
            return boton;
        }

        // ── la página de un panel ────────────────────────────────────────
        Gtk.Widget pagina () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            sw_contenido = new Gtk.ScrolledWindow (null, null);
            sw_contenido.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            sw_contenido.add (content_box);
            sw_contenido.vexpand = true;
            caja.pack_start (sw_contenido, true, true, 0);
            return caja;
        }

        bool ajustar_alto () {
            int nat;
            content_box.get_preferred_height (null, out nat);
            int pantalla = Gdk.Screen.get_default ().get_height ();
            int alto = int.max (MIN_PAGINA, int.min (nat + 90, (int) (pantalla * 0.85)));
            int natw;
            content_box.get_preferred_width (null, out natw);
            int ancho = int.max (ANCHO, int.min (natw + 40, 1000));
            resize (ancho, alto);
            return false;
        }

        // ── navegación ───────────────────────────────────────────────────
        public void abrir (Panel pv, bool registrar = true) {
            var pagina = pv.construir ();
            if (pagina == null) {
                // Sin página propia: un programa externo (o el System Preferences de Python); la ventana se queda donde estaba.
                pv.lanzar ();
                return;
            }
            actual = pv;
            set_title (pv.nombre);
            foreach (var hijo in content_box.get_children ()) {
                content_box.remove (hijo);
            }
            content_box.pack_start (pagina, false, false, 0);
            pila.set_visible_child_name ("pagina");
            content_box.show_all ();
            Idle.add (ajustar_alto);
            if (registrar) {
                registrar_paso (pv.id);
            }
        }

        public bool abrir_id (string ident) {
            for (int i = 0; i < todos.length; i++) {
                if (todos[i].id == ident) {
                    abrir (todos[i]);
                    return true;
                }
            }
            return false;
        }

        /** Un panel por su nombre de Catalina o su identificador (o el de Cinnamon, vía ALIAS). */
        public bool abrir_por_nombre (string texto) {
            var t = texto.down ().strip ();
            for (int i = 0; i < todos.length; i++) {
                var pv = todos[i];
                var corto = pv.id.substring (pv.id.last_index_of (".") + 1).down ();
                if (t == pv.id.down () || t == pv.nombre.down () || t == corto) {
                    abrir (pv);
                    return true;
                }
            }
            var destino = alias_de (t);
            if (destino != null) {
                for (int i = 0; i < todos.length; i++) {
                    var pv = todos[i];
                    if (pv.id.substring (pv.id.last_index_of (".") + 1).down () == destino) {
                        abrir (pv);
                        return true;
                    }
                }
            }
            return false;
        }

        /** Después de estar escondida vuelve a la cuadrícula, como recién abierta. */
        public void mostrar_de_nuevo () {
            historial = new GenericArray<string?> ();
            historial.add (null);
            pos = 0;
            mostrar_todo (false);
        }

        public void mostrar_todo (bool registrar = true) {
            actual = null;
            set_title (TITULO);
            pila.set_visible_child_name ("cuadricula");
            foreach (var hijo in content_box.get_children ()) {
                hijo.hide ();
            }
            buscar.set_text ("");
            resize (ANCHO, alto_cuadricula ());
            if (registrar) {
                registrar_paso (null);
            }
        }

        /**
         * El alto justo de la cuadrícula: la ventana termina debajo de la última fila. Con una barra propia (set_titlebar) GTK
         * mide el tamaño de la ventana sin la barra, que se suma aparte.
         */
        int alto_cuadricula () {
            int nat;
            cuadricula.get_preferred_height (null, out nat);
            int tope = (int) (Gdk.Screen.get_default ().get_height () * 0.85);
            return int.max (MIN_ALTO, int.min (nat, tope));
        }

        void registrar_paso (string? ident) {
            if (pos + 1 < (int) historial.length) {
                historial.remove_range (pos + 1, historial.length - (pos + 1));
            }
            if (historial.length == 0 || historial[historial.length - 1] != ident) {
                historial.add (ident);
            }
            pos = (int) historial.length - 1;
            actualizar_flechas ();
        }

        public void ir (int paso) {
            int nuevo = pos + paso;
            if (nuevo < 0 || nuevo >= (int) historial.length) {
                return;
            }
            pos = nuevo;
            var ident = historial[nuevo];
            if (ident == null) {
                mostrar_todo (false);
            } else {
                for (int i = 0; i < todos.length; i++) {
                    if (todos[i].id == ident) {
                        abrir (todos[i], false);
                    }
                }
            }
            actualizar_flechas ();
        }

        void actualizar_flechas () {
            bool hay_atras = pos > 0;
            bool hay_adelante = pos < (int) historial.length - 1;
            b_atras.set_sensitive (hay_atras);
            b_adelante.set_sensitive (hay_adelante);
            // Un glifo pintado no se atenúa solo cuando el botón se desactiva.
            i_atras.set_opacity (hay_atras ? 1.0 : 0.35);
            i_adelante.set_opacity (hay_adelante ? 1.0 : 0.35);
            var app = application as Aplicacion;
            if (app != null) {
                app.actualizar_menu (hay_atras, hay_adelante);
            }
        }

        // ── búsqueda ─────────────────────────────────────────────────────
        // Las frases que Catalina ofrece como subítems de un panel («Dock settings» lleva a Dock). Solo están las que salen en
        // las capturas; se amplía con las que vayan apareciendo.
        string[] anclas_de (string ident) {
            if (ident == "com.apple.preference.dock") {
                return { "Dock settings" };
            }
            if (ident == "com.apple.preference.keyboard") {
                return { "Keyboard shortcuts" };
            }
            return {};
        }

        class Resultado {
            public string rotulo;
            public Panel panel;
        }

        /** Primero los paneles cuyo nombre coincide (con sus subítems) y luego los que coinciden por sus palabras clave. */
        List<Resultado> resultados_de (string texto) {
            var t = texto.strip ().down ();
            var por_nombre = new GenericArray<Panel> ();
            var por_clave = new GenericArray<Panel> ();
            for (int i = 0; i < todos.length; i++) {
                if (t in todos[i].nombre.down ()) {
                    por_nombre.add (todos[i]);
                }
            }
            for (int i = 0; i < todos.length; i++) {
                bool ya = false;
                for (int j = 0; j < por_nombre.length; j++) {
                    if (por_nombre[j] == todos[i]) {
                        ya = true;
                    }
                }
                if (!ya && todos[i].coincide (texto)) {
                    por_clave.add (todos[i]);
                }
            }
            var filas = new List<Resultado> ();
            var vistos = new HashTable<string, bool> (str_hash, str_equal);
            var ordenados = new GenericArray<Panel> ();
            for (int i = 0; i < por_nombre.length; i++) ordenados.add (por_nombre[i]);
            for (int i = 0; i < por_clave.length; i++) ordenados.add (por_clave[i]);
            for (int i = 0; i < ordenados.length; i++) {
                var pv = ordenados[i];
                bool de_nombre = i < por_nombre.length;
                if (de_nombre) agregar (filas, vistos, pv.nombre, pv);
                foreach (var ancla in anclas_de (pv.id)) {
                    if (t in ancla.down ()) agregar (filas, vistos, ancla, pv);
                }
                if (!de_nombre) agregar (filas, vistos, pv.nombre, pv);
            }
            // Un subítem que no coincide por nombre también sale (Keyboard shortcuts), tras los demás.
            for (int i = 0; i < todos.length; i++) {
                foreach (var ancla in anclas_de (todos[i].id)) {
                    if (t in ancla.down ()) agregar (filas, vistos, ancla, todos[i]);
                }
            }
            return filas;
        }

        void agregar (List<Resultado> filas, HashTable<string, bool> vistos, string rotulo, Panel pv) {
            var clave = rotulo + "|" + pv.id;
            if (vistos.contains (clave)) {
                return;
            }
            vistos[clave] = true;
            var r = new Resultado ();
            r.rotulo = rotulo;
            r.panel = pv;
            filas.append (r);
        }

        void buscando () {
            var texto = buscar.get_text ();
            foreach (var fila in lista.get_children ()) {
                lista.remove (fila);
            }
            if (texto.strip () == "") {
                resultados.esconder ();
                hallados_velo = new List<Panel> ();
                velo.hide ();
                return;
            }
            var filas = resultados_de (texto);
            if (actual == null) {            // el velo solo va sobre la cuadrícula
                hallados_velo = new List<Panel> ();
                foreach (var r in filas) {
                    hallados_velo.append (r.panel);
                }
                velo.show ();
                velo.queue_draw ();
            }
            int n = 0;
            foreach (var r in filas) {
                if (n++ >= 12) {
                    break;
                }
                var fila = new FilaResultado ();
                fila.panel = r.panel;
                var etiqueta = new Gtk.Label (r.rotulo);
                etiqueta.xalign = 0;
                etiqueta.margin_top = 3;
                etiqueta.margin_bottom = 3;
                etiqueta.margin_start = 8;
                etiqueta.margin_end = 16;
                fila.add (etiqueta);
                lista.add (fila);
            }
            if (filas.length () > 0) {
                lista.show_all ();
                lista.select_row (lista.get_row_at_index (0));
                resultados.emerger ();
                // El foco vuelve al campo SIN seleccionar el texto: grab_focus() lo selecciona todo y la siguiente letra lo
                // borraba («dock» quedaba en «ck»).
                buscar.grab_focus_without_selecting ();
            } else {
                var fila = new FilaResultado ();
                fila.panel = null;
                var etiqueta = new Gtk.Label ("No results");
                etiqueta.margin_top = 8;
                etiqueta.margin_bottom = 8;
                etiqueta.margin_start = 8;
                etiqueta.margin_end = 8;
                fila.add (etiqueta);
                lista.add (fila);
                lista.show_all ();
                resultados.emerger ();
            }
        }

        void buscar_enter () {
            var fila = lista.get_selected_row () as FilaResultado;
            if (fila != null) {
                abrir_desde_busqueda (fila);
            }
        }

        void abrir_desde_busqueda (FilaResultado? fila) {
            if (fila == null) {
                return;
            }
            var pv = fila.panel;
            resultados.esconder ();
            hallados_velo = new List<Panel> ();
            velo.hide ();
            if (pv != null) {
                abrir (pv);
                buscar.set_text ("");
            }
        }

        // ── teclas y ratón ───────────────────────────────────────────────
        public override bool key_press_event (Gdk.EventKey ev) {
            bool ctrl = (ev.state & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool alt = (ev.state & Gdk.ModifierType.MOD1_MASK) != 0;
            if (ev.keyval == Gdk.Key.Escape && resultados.get_visible ()) {
                resultados.esconder ();
                buscar.set_text ("");
                return true;
            }
            if (ctrl && (ev.keyval == Gdk.Key.f || ev.keyval == Gdk.Key.F)) {
                buscar.grab_focus ();
                return true;
            }
            if (ctrl && (ev.keyval == Gdk.Key.l || ev.keyval == Gdk.Key.L)) {
                mostrar_todo ();
                return true;
            }
            if (ctrl && (ev.keyval == Gdk.Key.w || ev.keyval == Gdk.Key.W || ev.keyval == Gdk.Key.q || ev.keyval == Gdk.Key.Q)) {
                close ();
                return true;
            }
            if (alt && ev.keyval == Gdk.Key.Left) {
                ir (-1);
                return true;
            }
            if (alt && ev.keyval == Gdk.Key.Right) {
                ir (1);
                return true;
            }
            if (resultados.get_visible () && (ev.keyval == Gdk.Key.Down || ev.keyval == Gdk.Key.Up)) {
                var fila = lista.get_selected_row ();
                int i = fila != null ? fila.get_index () : -1;
                i = int.max (0, i + (ev.keyval == Gdk.Key.Down ? 1 : -1));
                var nueva = lista.get_row_at_index (i);
                if (nueva != null) {
                    lista.select_row (nueva);
                }
                return true;
            }
            return base.key_press_event (ev);
        }

        public override bool button_press_event (Gdk.EventButton ev) {
            if (ev.button == 8) {          // el botón «atrás» del ratón
                ir (-1);
                return true;
            }
            if (ev.button == 9) {
                ir (1);
                return true;
            }
            return base.button_press_event (ev);
        }
    }
}
