/*
 * El App Store (Catalina): barra lateral con Discover, Create, Work, Play, Develop, Categories y Updates; búsqueda en la
 * barra de título; estantes, listas, fichas con GET y progreso. Todo lo que muestra lo da el motor (org.mintmacos.Tienda1);
 * lo que el motor no trae no se dibuja. Primera versión: el aspecto fino espera las capturas de Catalina.
 */
namespace Tienda {
    const string CSS = """
window.tienda-ventana label { font-family: ".SF NS"; }
list.tienda-barra { background: transparent; }
list.tienda-barra row { padding: 5px 10px; border-radius: 6px; margin: 1px 8px; }
list.tienda-barra row:selected { background-color: rgba(120,120,128,0.28); color: inherit; }
.tienda-barra-titulo { font-size: 13px; }
.tienda-insignia { background-color: #ff3b30; color: #ffffff; border-radius: 9px; padding: 0 6px; font-size: 11px; font-weight: bold; }
.tienda-pagina-titulo { font-size: 28px; font-weight: bold; }
.tienda-estante-titulo { font-size: 20px; font-weight: bold; }
.tienda-fila-nombre { font-size: 13px; font-weight: 600; }
.tienda-fila-resumen { font-size: 12px; opacity: 0.6; }
.tienda-numero { font-size: 15px; font-weight: bold; }
.tienda-fila:hover { background-color: rgba(120,120,128,0.10); border-radius: 8px; }
button.tienda-get { background-image: none; background-color: rgba(120,120,128,0.18); color: #0a60ff; border: none; box-shadow: none;
  border-radius: 13px; padding: 2px 14px; min-height: 0; min-width: 0; }
button.tienda-get label { font-size: 12px; font-weight: bold; }
button.tienda-get:hover { background-color: rgba(120,120,128,0.30); }
button.tienda-enlace { background: none; border: none; box-shadow: none; padding: 0; min-height: 0; color: #0a60ff; }
button.tienda-enlace label { font-size: 12px; }
.tienda-destacada { background-color: rgba(120,120,128,0.10); border-radius: 12px; }
.tienda-destacada-nombre { font-size: 22px; font-weight: bold; }
.tienda-ficha-nombre { font-size: 28px; font-weight: bold; }
.tienda-ficha-dev { font-size: 14px; opacity: 0.6; }
.tienda-ficha-nota { font-size: 12px; opacity: 0.7; }
.tienda-seccion { font-size: 18px; font-weight: bold; }
.tienda-texto { font-size: 13px; font-weight: normal; }
.tienda-info-clave { font-size: 12px; opacity: 0.55; }
.tienda-info-valor { font-size: 12px; }
.tienda-resena-titulo { font-size: 13px; font-weight: bold; }
.tienda-resena-autor { font-size: 11px; opacity: 0.55; }
.tienda-categoria { font-size: 14px; padding: 12px 16px; }
.tienda-vacio { font-size: 14px; opacity: 0.6; }
""";

    class Pagina : Object {
        public string tipo = "";      // seccion | categorias | categoria | actualizaciones | busqueda | ficha
        public string arg = "";
        public string titulo = "";
    }

    public class Ventana : Gtk.ApplicationWindow {
        struct Entrada { string id; string titulo; string icono; }

        Motor motor = Motor.instancia;
        Gtk.ListBox barra;
        Gtk.Stack contenido;
        Gtk.Button atras;
        Gtk.SearchEntry busqueda;
        Gtk.InfoBar aviso;
        Gtk.Label aviso_texto;
        Gtk.Label insignia;
        GenericArray<Pagina> historial = new GenericArray<Pagina> ();
        GenericArray<Grupo>? secciones = null;
        GenericArray<Grupo>? categorias = null;
        HashTable<string, Gtk.ListBoxRow> filas = new HashTable<string, Gtk.ListBoxRow> (str_hash, str_equal);
        int generacion = 0;
        bool selecciono_codigo = false;
        uint t_busqueda = 0;

        public Ventana (Gtk.Application app) {
            Object (application: app);
            show_menubar = false;       // el menú va al panel (menú global), no dentro de la ventana
            title = "App Store";
            set_default_size (1120, 740);
            window_position = Gtk.WindowPosition.CENTER;
            get_style_context ().add_class ("tienda-ventana");
            MacOS.aplicar_css (CSS);

            var cabecera = new Gtk.HeaderBar ();
            cabecera.show_close_button = true;
            cabecera.decoration_layout = "close,minimize,maximize:";
            cabecera.title = "App Store";
            atras = new Gtk.Button.from_icon_name ("go-previous-symbolic", Gtk.IconSize.BUTTON);
            atras.no_show_all = true;
            atras.clicked.connect (volver);
            cabecera.pack_start (atras);
            busqueda = new Gtk.SearchEntry ();
            busqueda.width_chars = 22;
            busqueda.placeholder_text = "Search";
            busqueda.search_changed.connect (al_buscar);
            cabecera.pack_end (busqueda);
            set_titlebar (cabecera);

            barra = new Gtk.ListBox ();
            barra.selection_mode = Gtk.SelectionMode.SINGLE;
            barra.get_style_context ().add_class ("tienda-barra");
            barra.row_selected.connect (al_elegir_fila);
            Entrada[] entradas = {
                { "discover", "Discover", "starred-symbolic" },
                { "create", "Create", "document-edit-symbolic" },
                { "work", "Work", "mail-send-symbolic" },
                { "play", "Play", "applications-games-symbolic" },
                { "develop", "Develop", "applications-engineering-symbolic" },
                { "categories", "Categories", "view-grid-symbolic" },
                { "updates", "Updates", "software-update-available-symbolic" }
            };
            foreach (var e in entradas) agregar_fila (e.id, e.titulo, e.icono);
            var lateral = new Gtk.ScrolledWindow (null, null);
            lateral.hscrollbar_policy = Gtk.PolicyType.NEVER;
            lateral.set_size_request (200, -1);
            lateral.margin_top = 8;
            lateral.add (barra);

            contenido = new Gtk.Stack ();
            contenido.transition_type = Gtk.StackTransitionType.NONE;

            aviso = new Gtk.InfoBar ();
            aviso.message_type = Gtk.MessageType.ERROR;
            aviso.show_close_button = true;
            aviso.no_show_all = true;
            aviso.response.connect (() => { aviso.hide (); });
            aviso_texto = new Gtk.Label ("");
            aviso_texto.wrap = true;
            aviso_texto.xalign = 0;
            ((Gtk.Container) aviso.get_content_area ()).add (aviso_texto);

            var derecha = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            derecha.pack_start (aviso, false, false, 0);
            derecha.pack_start (contenido, true, true, 0);

            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            cuerpo.pack_start (lateral, false, false, 0);
            cuerpo.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);
            cuerpo.pack_start (derecha, true, true, 0);
            add (cuerpo);

            string e;
            if (!motor.conectar (out e)) warning ("sin motor: %s", e);
            motor.abrir_ficha.connect ((id) => { abrir_ficha (id); });
            motor.terminado.connect (al_terminar_trabajo);
            motor.actualizaciones_cambiaron.connect (contar_actualizaciones);
            motor.instaladas_cambiaron.connect (() => { contar_actualizaciones (); });

            key_press_event.connect ((ev) => {
                bool ctrl = (ev.state & Gdk.ModifierType.CONTROL_MASK) != 0;
                if (ctrl && ev.keyval == Gdk.Key.f) { busqueda.grab_focus (); return true; }
                if (ctrl && ev.keyval == Gdk.Key.bracketleft) { volver (); return true; }
                return false;
            });
            registrar_acciones ();
            show_all ();
            atras.hide ();
            contar_actualizaciones ();
        }

        /** Las acciones win.* de la barra de menús (tienda_menus.vala): edición del campo con el foco y ventana. */
        void registrar_acciones () {
            var cerrar = new SimpleAction ("cerrar", null);
            cerrar.activate.connect (() => { close (); });
            add_action (cerrar);
            var minimizar = new SimpleAction ("minimizar", null);
            minimizar.activate.connect (() => { iconify (); });
            add_action (minimizar);
            var zoom = new SimpleAction ("zoom", null);
            zoom.activate.connect (() => { if (is_maximized) unmaximize (); else maximize (); });
            add_action (zoom);
            var completa = new SimpleAction ("pantalla-completa", null);
            completa.activate.connect (() => {
                if ((get_window ().get_state () & Gdk.WindowState.FULLSCREEN) != 0) unfullscreen (); else fullscreen ();
            });
            add_action (completa);
            var cortar = new SimpleAction ("cortar", null);
            cortar.activate.connect (() => { var e = get_focus () as Gtk.Editable; if (e != null) e.cut_clipboard (); });
            add_action (cortar);
            var copiar = new SimpleAction ("copiar", null);
            copiar.activate.connect (() => { var e = get_focus () as Gtk.Editable; if (e != null) e.copy_clipboard (); });
            add_action (copiar);
            var pegar = new SimpleAction ("pegar", null);
            pegar.activate.connect (() => { var e = get_focus () as Gtk.Editable; if (e != null) e.paste_clipboard (); });
            add_action (pegar);
            var borrar = new SimpleAction ("borrar", null);
            borrar.activate.connect (() => { var e = get_focus () as Gtk.Editable; if (e != null) e.delete_selection (); });
            add_action (borrar);
            var todo = new SimpleAction ("todo", null);
            todo.activate.connect (() => { var e = get_focus () as Gtk.Editable; if (e != null) e.select_region (0, -1); });
            add_action (todo);
            application.set_accels_for_action ("win.cerrar", { "<Primary>w" });
            application.set_accels_for_action ("win.minimizar", { "<Primary>m" });
        }

        void agregar_fila (string id, string texto, string icono) {
            var fila = new Gtk.ListBoxRow ();
            fila.set_data<string> ("tienda-id", id);
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var tema = Gtk.IconTheme.get_default ();
            caja.pack_start (new Gtk.Image.from_icon_name (tema.has_icon (icono) ? icono : "applications-other-symbolic",
                                                           Gtk.IconSize.MENU), false, false, 0);
            var l = new Gtk.Label (texto);
            l.xalign = 0;
            l.get_style_context ().add_class ("tienda-barra-titulo");
            caja.pack_start (l, true, true, 0);
            if (id == "updates") {
                insignia = new Gtk.Label ("");
                insignia.no_show_all = true;
                insignia.get_style_context ().add_class ("tienda-insignia");
                caja.pack_end (insignia, false, false, 0);
            }
            fila.add (caja);
            barra.add (fila);
            filas.replace (id, fila);
        }

        void al_elegir_fila (Gtk.ListBoxRow? fila) {
            if (fila == null || selecciono_codigo) return;
            ir_a_seccion (fila.get_data<string> ("tienda-id"));
        }

        // ---- navegación ---------------------------------------------------------------------------------------

        public void ir_a_seccion (string id) {
            var fila = filas.lookup (id);
            if (fila == null) fila = filas.lookup ("discover");
            selecciono_codigo = true;
            barra.select_row (fila);
            selecciono_codigo = false;
            if (busqueda.text != "") { busqueda.text = ""; }
            historial.remove_range (0, historial.length);
            var p = new Pagina ();
            p.tipo = id == "categories" ? "categorias" : id == "updates" ? "actualizaciones" : "seccion";
            p.arg = id;
            historial.add (p);
            mostrar (p);
        }

        public void abrir_ficha (string id) {
            empujar ("ficha", id, "");
        }

        public void buscar (string texto) {
            busqueda.text = texto;
        }

        void empujar (string tipo, string arg, string titulo) {
            var p = new Pagina ();
            p.tipo = tipo;
            p.arg = arg;
            p.titulo = titulo;
            historial.add (p);
            mostrar (p);
        }

        void volver () {
            if (historial.length < 2) return;
            historial.remove_index (historial.length - 1);
            var p = historial[historial.length - 1];
            if (p.tipo != "busqueda" && busqueda.text != "") busqueda.text = "";
            mostrar (p);
        }

        void al_buscar () {
            if (t_busqueda != 0) { Source.remove (t_busqueda); t_busqueda = 0; }
            var texto = busqueda.text.strip ();
            t_busqueda = Timeout.add (300, () => {
                t_busqueda = 0;
                if (texto.length < 2) {
                    if (historial.length > 0 && historial[historial.length - 1].tipo == "busqueda") {
                        historial.remove_index (historial.length - 1);
                        if (historial.length > 0) mostrar (historial[historial.length - 1]);
                    }
                    return false;
                }
                if (historial.length > 0 && historial[historial.length - 1].tipo == "busqueda") {
                    historial[historial.length - 1].arg = texto;
                    mostrar (historial[historial.length - 1]);
                } else {
                    empujar ("busqueda", texto, "");
                }
                return false;
            });
        }

        void mostrar (Pagina p) {
            generacion++;
            int gen = generacion;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 28);
            caja.margin = 28;
            var sw = new Gtk.ScrolledWindow (null, null);
            sw.hscrollbar_policy = Gtk.PolicyType.NEVER;
            sw.add (caja);
            sw.show_all ();
            contenido.add (sw);
            contenido.visible_child = sw;
            foreach (var hijo in contenido.get_children ())
                if (hijo != sw) contenido.remove (hijo);
            atras.visible = historial.length > 1;
            llenar.begin (p, caja, gen);
        }

        Gtk.Spinner girando (Gtk.Box caja) {
            var s = new Gtk.Spinner ();
            s.set_size_request (32, 32);
            s.halign = Gtk.Align.CENTER;
            s.margin_top = 80;
            s.start ();
            caja.pack_start (s, false, false, 0);
            s.show ();
            return s;
        }

        void vacio (Gtk.Box caja, string texto) {
            var l = etiqueta (texto, "tienda-vacio", true);
            l.halign = Gtk.Align.CENTER;
            l.margin_top = 80;
            caja.pack_start (l, false, false, 0);
            l.show ();
        }

        // ---- las pantallas --------------------------------------------------------------------------------------

        async void llenar (Pagina p, Gtk.Box caja, int gen) {
            var spin = girando (caja);
            try {
                switch (p.tipo) {
                case "seccion": yield pagina_seccion (p, caja, gen, spin); break;
                case "categorias": yield pagina_categorias (caja, gen, spin); break;
                case "categoria": yield pagina_categoria (p, caja, gen, spin); break;
                case "actualizaciones": yield pagina_actualizaciones (caja, gen, spin); break;
                case "busqueda": yield pagina_busqueda (p, caja, gen, spin); break;
                case "ficha": yield pagina_ficha (p, caja, gen, spin); break;
                }
            } catch (Error e) {
                if (gen != generacion) return;
                caja.remove (spin);
                vacio (caja, "Can’t load the App Store right now.\n%s".printf (e.message));
            }
        }

        Gtk.Label titulo_pagina (string texto) {
            return etiqueta (texto, "tienda-pagina-titulo");
        }

        async void asegurar_secciones () throws Error {
            if (secciones == null) secciones = yield motor.grupos ("Secciones");
        }

        async void pagina_seccion (Pagina p, Gtk.Box caja, int gen, Gtk.Spinner spin) throws Error {
            var estantes = yield motor.estantes (p.arg);
            if (gen != generacion) return;
            caja.remove (spin);
            var fila = filas.lookup (p.arg);
            string nombre = p.arg;
            if (fila != null) nombre = ((Gtk.Label) ((Gtk.Box) fila.get_child ()).get_children ().nth_data (1)).label;
            caja.pack_start (titulo_pagina (nombre), false, false, 0);
            if (estantes.length > 0) {
                for (int i = 0; i < estantes.length; i++) caja.pack_start (widget_estante (estantes[i]), false, false, 0);
                caja.show_all ();
                return;
            }
            // Sin estantes (sin red, o la sección no tiene): las apps de sus categorías de AppStream.
            yield asegurar_secciones ();
            if (gen != generacion) return;
            var vistas = new HashTable<string, bool> (str_hash, str_equal);
            var apps = new GenericArray<Resumen> ();
            for (int i = 0; i < secciones.length; i++) {
                if (secciones[i].id != p.arg) continue;
                foreach (var c in secciones[i].categorias) {
                    var lista = yield motor.listar_categoria (c, 0, 18);
                    if (gen != generacion) return;
                    for (int k = 0; k < lista.length; k++) {
                        if (vistas.contains (lista[k].id) || apps.length >= 60) continue;
                        vistas.replace (lista[k].id, true);
                        apps.add (lista[k]);
                    }
                }
            }
            if (apps.length == 0) vacio (caja, "Nothing here yet.");
            else caja.pack_start (cuadricula (apps, false), false, false, 0);
            caja.show_all ();
        }

        async void pagina_categorias (Gtk.Box caja, int gen, Gtk.Spinner spin) throws Error {
            if (categorias == null) categorias = yield motor.grupos ("Categorias");
            if (gen != generacion) return;
            caja.remove (spin);
            caja.pack_start (titulo_pagina ("Categories"), false, false, 0);
            var flujo = new Gtk.FlowBox ();
            flujo.selection_mode = Gtk.SelectionMode.NONE;
            flujo.min_children_per_line = 2;
            flujo.max_children_per_line = 4;
            flujo.homogeneous = true;
            flujo.column_spacing = 12;
            flujo.row_spacing = 12;
            for (int i = 0; i < categorias.length; i++) {
                var g = categorias[i];
                var b = new Gtk.Button.with_label (g.titulo);
                b.get_style_context ().add_class ("tienda-categoria");
                b.clicked.connect (() => { empujar ("categoria", g.id, g.titulo); });
                flujo.add (b);
            }
            caja.pack_start (flujo, false, false, 0);
            caja.show_all ();
        }

        async void pagina_categoria (Pagina p, Gtk.Box caja, int gen, Gtk.Spinner spin) throws Error {
            var apps = yield motor.listar_categoria (p.arg, 0, 60);
            if (gen != generacion) return;
            caja.remove (spin);
            caja.pack_start (titulo_pagina (p.titulo != "" ? p.titulo : p.arg), false, false, 0);
            if (apps.length == 0) vacio (caja, "Nothing here yet.");
            else caja.pack_start (cuadricula (apps, false), false, false, 0);
            caja.show_all ();
        }

        async void pagina_busqueda (Pagina p, Gtk.Box caja, int gen, Gtk.Spinner spin) throws Error {
            var apps = yield motor.buscar (p.arg, 60);
            if (gen != generacion) return;
            caja.remove (spin);
            caja.pack_start (titulo_pagina ("Results for “%s”".printf (p.arg)), false, false, 0);
            if (apps.length == 0) vacio (caja, "No results.");
            else caja.pack_start (cuadricula (apps, false), false, false, 0);
            caja.show_all ();
        }

        async void pagina_actualizaciones (Gtk.Box caja, int gen, Gtk.Spinner spin) throws Error {
            var apps = yield motor.actualizaciones ("apps");
            if (gen != generacion) return;
            caja.remove (spin);
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            cab.pack_start (titulo_pagina ("Updates"), true, true, 0);
            if (apps.length > 0) {
                var todo = new Gtk.Button.with_label ("Update All");
                todo.get_style_context ().add_class ("tienda-get");
                todo.valign = Gtk.Align.CENTER;
                todo.clicked.connect (() => {
                    todo.sensitive = false;
                    motor.actualizar.begin ("apps", new string[0], (o, res) => {
                        try { motor.actualizar.end (res); } catch (Error e) { mostrar_aviso (e.message); }
                    });
                });
                cab.pack_end (todo, false, false, 0);
            }
            caja.pack_start (cab, false, false, 0);
            if (apps.length == 0) vacio (caja, "No updates available.");
            else caja.pack_start (cuadricula (apps, false, 1), false, false, 0);
            caja.show_all ();
        }

        async void pagina_ficha (Pagina p, Gtk.Box caja, int gen, Gtk.Spinner spin) throws Error {
            var d = yield motor.ficha (p.arg);
            if (gen != generacion) return;
            caja.remove (spin);
            var r = Resumen.desde (d);

            // Cabecera: ícono grande, nombre, desarrollador, nota y GET.
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            cab.pack_start (new IconoApp (r, 128), false, false, 0);
            var datos = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            datos.valign = Gtk.Align.CENTER;
            datos.pack_start (etiqueta (r.nombre, "tienda-ficha-nombre", true), false, false, 0);
            if (r.desarrollador != "") datos.pack_start (etiqueta (r.desarrollador, "tienda-ficha-dev"), false, false, 0);
            var nota_v = d.lookup_value ("nota", VariantType.DOUBLE);
            var votos_v = d.lookup_value ("votos", VariantType.UINT32);
            if (nota_v != null && nota_v.get_double () > 0) {
                string txt = "%s  %.1f".printf (estrellas (nota_v.get_double ()), nota_v.get_double ());
                if (votos_v != null) txt += "  ·  %u ratings".printf (votos_v.get_uint32 ());
                datos.pack_start (etiqueta (txt, "tienda-ficha-nota"), false, false, 0);
            }
            var acciones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            acciones.margin_top = 8;
            var obtener = new BotonGet (r);
            acciones.pack_start (obtener, false, false, 0);
            var quitar = new Gtk.Button.with_label ("Remove");
            quitar.get_style_context ().add_class ("tienda-enlace");
            quitar.no_show_all = true;
            quitar.visible = r.instalada;
            quitar.clicked.connect (() => {
                motor.quitar.begin (r.id, (o, res) => {
                    try { motor.quitar.end (res); } catch (Error e) { mostrar_aviso (e.message); }
                });
            });
            obtener.cambio.connect (() => { quitar.visible = r.instalada; });
            acciones.pack_start (quitar, false, false, 0);
            datos.pack_start (acciones, false, false, 0);
            cab.pack_start (datos, true, true, 0);
            caja.pack_start (cab, false, false, 0);

            // Capturas.
            var caps = d.lookup_value ("capturas", new VariantType ("a(sss)"));
            if (caps != null && caps.n_children () > 0) {
                var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
                for (size_t i = 0; i < caps.n_children (); i++) {
                    var c = caps.get_child_value (i);
                    var url = c.get_child_value (1).get_string ();
                    if (url == "") url = c.get_child_value (0).get_string ();
                    fila.pack_start (new CapturaImagen (url, 300), false, false, 0);
                }
                var sw = new Gtk.ScrolledWindow (null, null);
                sw.vscrollbar_policy = Gtk.PolicyType.NEVER;
                sw.min_content_height = 320;
                sw.add (fila);
                caja.pack_start (sw, false, false, 0);
            }

            // Descripción y novedades.
            var desc = Resumen.texto (d, "descripcion");
            if (desc != "") caja.pack_start (texto_largo (markup_a_pango (desc)), false, false, 0);
            var notas = Resumen.texto (d, "notas_version");
            if (notas != "") {
                var bloque = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
                bloque.pack_start (etiqueta ("What’s New", "tienda-seccion"), false, false, 0);
                var ver = Resumen.texto (d, "version");
                if (ver != "") bloque.pack_start (etiqueta ("Version %s".printf (ver), "tienda-ficha-nota"), false, false, 0);
                bloque.pack_start (texto_largo (markup_a_pango (notas)), false, false, 0);
                caja.pack_start (bloque, false, false, 0);
            }

            caja.pack_start (informacion (d, r), false, false, 0);
            caja.show_all ();

            // Reseñas: llegan aparte (red); la ficha ya está en pantalla.
            if (r.appstream_id == "") return;
            try {
                var rs = yield motor.resenas (r.appstream_id, 6);
                if (gen != generacion || rs.length == 0) return;
                var bloque = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
                bloque.pack_start (etiqueta ("Ratings & Reviews", "tienda-seccion"), false, false, 0);
                for (int i = 0; i < rs.length; i++) bloque.pack_start (widget_resena (rs[i]), false, false, 0);
                var fuente = Resumen.texto (d, "fuente_nota");
                if (fuente != "")
                    bloque.pack_start (etiqueta ("From ODRS (odrs.gnome.org)", "tienda-resena-autor"), false, false, 0);
                bloque.show_all ();
                caja.pack_start (bloque, false, false, 0);
            } catch (Error e) {
                // sin red: no hay reseñas, y no se inventan
            }
        }

        // ---- piezas -------------------------------------------------------------------------------------------

        static string estrellas (double n) {
            int llenas = (int) Math.round (n);
            var sb = new StringBuilder ();
            for (int i = 0; i < 5; i++) sb.append (i < llenas ? "★" : "☆");
            return sb.str;
        }

        Gtk.Label texto_largo (string markup) {
            var l = new Gtk.Label (null);
            l.set_markup (markup);
            l.wrap = true;
            l.xalign = 0;
            l.halign = Gtk.Align.START;
            l.selectable = true;
            l.max_width_chars = 100;
            l.get_style_context ().add_class ("tienda-texto");
            return l;
        }

        Gtk.Widget widget_resena (Variant v) {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            var nota = v.lookup_value ("nota", VariantType.DOUBLE);
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            if (nota != null) cab.pack_start (etiqueta (estrellas (nota.get_double ()), "tienda-ficha-nota"), false, false, 0);
            cab.pack_start (etiqueta (Resumen.texto (v, "resumen"), "tienda-resena-titulo"), false, false, 0);
            caja.pack_start (cab, false, false, 0);
            var texto = Resumen.texto (v, "texto");
            if (texto != "") {
                var l = etiqueta (texto, "tienda-texto", true);
                l.max_width_chars = 100;
                caja.pack_start (l, false, false, 0);
            }
            var autor = Resumen.texto (v, "autor");
            if (autor != "") caja.pack_start (etiqueta (autor, "tienda-resena-autor"), false, false, 0);
            return caja;
        }

        Gtk.Widget informacion (Variant d, Resumen r) {
            var bloque = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            bloque.pack_start (etiqueta ("Information", "tienda-seccion"), false, false, 0);
            var rejilla = new Gtk.Grid ();
            rejilla.column_spacing = 24;
            rejilla.row_spacing = 6;
            int fila = 0;
            void dato (string clave, string valor) {
                if (valor == "") return;
                var k = etiqueta (clave, "tienda-info-clave");
                k.yalign = 0;
                rejilla.attach (k, 0, fila, 1, 1);
                rejilla.attach (etiqueta (valor, "tienda-info-valor", true), 1, fila, 1, 1);
                fila++;
            }
            dato ("Developer", r.desarrollador);
            var tam = d.lookup_value ("tamano_descarga", VariantType.UINT64);
            if (tam != null) dato ("Size", tamano_texto (tam.get_uint64 ()));
            var cats = d.lookup_value ("categorias", VariantType.STRING_ARRAY);
            if (cats != null) {
                var lista = cats.dup_strv ();
                if (lista.length > 0) dato ("Category", string.joinv (", ", lista[0:int.min (3, lista.length)]));
            }
            dato ("Version", Resumen.texto (d, "version"));
            dato ("License", Resumen.texto (d, "licencia"));
            dato ("Source", r.origen == "flatpak" ? "Flathub (Flatpak)" : r.origen == "apt" ? "APT" : r.origen);
            var inst = d.lookup_value ("instalaciones_mes", VariantType.UINT64);
            if (inst != null) dato ("Installs per month", "%s".printf (inst.get_uint64 ().to_string ()));
            rejilla.show_all ();
            bloque.pack_start (rejilla, false, false, 0);
            var web = Resumen.texto (d, "web");
            if (web != "") {
                var b = new Gtk.Button.with_label (web);
                b.get_style_context ().add_class ("tienda-enlace");
                b.halign = Gtk.Align.START;
                b.clicked.connect (() => {
                    try { AppInfo.launch_default_for_uri (web, null); } catch (Error e) { warning ("%s", e.message); }
                });
                bloque.pack_start (b, false, false, 0);
            }
            return bloque;
        }

        Gtk.Widget widget_estante (Estante e) {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            caja.pack_start (etiqueta (e.titulo, "tienda-estante-titulo"), false, false, 0);
            if (e.tipo == "destacada") caja.pack_start (tarjeta_destacada (e.apps[0]), false, false, 0);
            else caja.pack_start (cuadricula (e.apps, e.tipo == "lista-numerada"), false, false, 0);
            return caja;
        }

        Gtk.Widget tarjeta_destacada (Resumen r) {
            var tarjeta = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            tarjeta.get_style_context ().add_class ("tienda-destacada");
            tarjeta.margin_bottom = 4;
            var izq = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            izq.margin = 24;
            izq.pack_start (new IconoApp (r, 96), false, false, 0);
            var t = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            t.valign = Gtk.Align.CENTER;
            t.pack_start (etiqueta (r.nombre, "tienda-destacada-nombre"), false, false, 0);
            if (r.resumen != "") t.pack_start (etiqueta (r.resumen, "tienda-fila-resumen", true), false, false, 0);
            if (r.desarrollador != "") t.pack_start (etiqueta (r.desarrollador, "tienda-fila-resumen"), false, false, 0);
            var b = new BotonGet (r);
            b.halign = Gtk.Align.START;
            b.margin_top = 6;
            t.pack_start (b, false, false, 0);
            izq.pack_start (t, false, false, 0);
            var ev = new Gtk.EventBox ();
            ev.add (izq);
            ev.button_release_event.connect ((x) => { if (x.button == 1) motor.abrir_ficha (r.id); return false; });
            tarjeta.pack_start (ev, false, false, 0);
            // La primera captura de su ficha, si la tiene.
            motor.ficha.begin (r.id, (o, res) => {
                try {
                    var d = motor.ficha.end (res);
                    var caps = d.lookup_value ("capturas", new VariantType ("a(sss)"));
                    if (caps == null || caps.n_children () == 0) return;
                    var c = caps.get_child_value (0);
                    var url = c.get_child_value (1).get_string ();
                    if (url == "") url = c.get_child_value (0).get_string ();
                    var img = new CapturaImagen (url, 220);
                    img.margin = 12;
                    img.halign = Gtk.Align.END;
                    tarjeta.pack_end (img, false, false, 0);
                } catch (Error e) {
                    // sin ficha: la tarjeta queda sin captura
                }
            });
            tarjeta.show_all ();
            return tarjeta;
        }

        /** Filas en tres columnas, como las listas de Apple: se lee de arriba abajo y luego a la siguiente columna. */
        Gtk.Widget cuadricula (GenericArray<Resumen> apps, bool numerada, int columnas = 3) {
            var rejilla = new Gtk.Grid ();
            rejilla.column_spacing = 16;
            rejilla.row_spacing = 2;
            rejilla.column_homogeneous = true;
            int n = (int) apps.length;
            int filas_n = (n + columnas - 1) / columnas;
            var nombres = new HashTable<string, int> (str_hash, str_equal);
            for (int i = 0; i < n; i++) nombres.replace (apps[i].nombre, (nombres.lookup (apps[i].nombre)) + 1);
            for (int i = 0; i < n; i++) {
                bool por_columna = numerada || n <= 12;
                int col = por_columna ? i / filas_n : i % columnas;
                int fil = por_columna ? i % filas_n : i / columnas;
                var f = fila_app (apps[i], numerada ? i + 1 : 0, nombres.lookup (apps[i].nombre) > 1);
                f.hexpand = true;
                rejilla.attach (f, col, fil, 1, 1);
            }
            rejilla.show_all ();
            return rejilla;
        }

        // ---- avisos y cuenta de actualizaciones -------------------------------------------------------------------

        void mostrar_aviso (string texto) {
            aviso_texto.label = texto;
            aviso.show_all ();
        }

        void al_terminar_trabajo (string trabajo, string id, string tipo, bool ok, string codigo, string mensaje) {
            if (!ok && codigo != "cancelado" && codigo != "sin-autorizacion") mostrar_aviso (mensaje != "" ? mensaje : codigo);
            contar_actualizaciones ();
            // Update All terminó: la lista de Updates se vuelve a pedir.
            if (ok && tipo == "actualizar" && id == "" && historial.length > 0
                && historial[historial.length - 1].tipo == "actualizaciones")
                mostrar (historial[historial.length - 1]);
        }

        void contar_actualizaciones () {
            motor.actualizaciones.begin ("apps", (o, res) => {
                try {
                    var lista = motor.actualizaciones.end (res);
                    if (insignia == null) return;
                    insignia.label = "%u".printf (lista.length);
                    insignia.visible = lista.length > 0;
                } catch (Error e) {
                    // sin motor: sin cuenta
                }
            });
        }
    }
}
