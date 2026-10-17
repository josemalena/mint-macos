/*
 * Desktop & Screen Saver: el panel de Catalina con sus dos pestañas (port de settings/escritorio.py).
 *
 * Capturas: Screen Shot 2026-10-14 at 12.12.20 AM (Desktop), 12.12.26 AM (Screen Saver), 12.12.31 AM (Screen Saver Options) y 12.12.36 AM
 * (Hot Corners).
 *
 * Desktop: la vista previa, la lista Apple ▸ Desktop Pictures / Colors y Folders, y la cuadrícula de miniaturas. Escoger una foto
 * escribe picture-uri de org.cinnamon.desktop.background. Las fotos y los colores de Apple salen del disco de la Mac con `fondos.py` a
 * ~/.local/share/mint-macos/fondos (arte de Apple: nunca va al repo). Change picture y Random order son el slideshow de Cinnamon con
 * la carpeta que se escogió. El popup de Dynamic Desktop (Light / Dark / Dynamic) va en gris: Cinnamon no cambia el fondo por la hora.
 * Screen Saver: Start after es idle-delay de org.cinnamon.desktop.session, Show with clock es org.cinnamon.desktop.screensaver
 * show-clock y Hot Corners… abre la hoja del panel Mission Control. Los protectores de Apple (Classic, Drift, Flurry…) y Screen Saver
 * Options… no existen aquí: se dibujan como en la captura, en gris. Las opciones de los popups Start after y Change picture, salvo
 * «20 Minutes» y «Every 30 minutes», no tienen captura.
 */
namespace Preferencias {

    class HijoFondo : Gtk.FlowBoxChild {
        public string ruta = "";
    }

    class ElementoFondo {
        public string rotulo;
        public string ruta;
        public string mini;
    }

    public class PanelDesktopScreenSaver : Panel {
        const string BG = "org.cinnamon.desktop.background";
        const int[] INTERVALOS_MIN = { 1, 5, 15, 30, 60 };
        const string[] INTERVALOS_TXT = { "Every minute", "Every 5 minutes", "Every 15 minutes", "Every 30 minutes", "Every hour" };
        const int[] INACTIVIDAD_S = { 60, 120, 300, 600, 1200, 1800, 3600, 0 };
        const string[] INACTIVIDAD_TXT = { "1 Minute", "2 Minutes", "5 Minutes", "10 Minutes", "20 Minutes", "30 Minutes", "1 Hour", "Never" };
        const string[] PROTECTORES = { "Classic", "Drift", "Flurry", "Arabesque", "Shell" };      // los que se ven en la captura

        // MINT_ESCRITORIO_PRUEBA: no cambia el fondo ni la configuración.
        bool prueba = Environment.get_variable ("MINT_ESCRITORIO_PRUEBA") != null;
        bool cargando = false;
        Settings? bg = null;
        Settings? cfg_dia = null;
        Gtk.Image vista;
        Gtk.Label nombre_l;
        Gtk.TreeStore arbol;
        Gtk.TreeView lateral;
        Gtk.FlowBox rejilla;
        Gtk.CheckButton cambiar;
        Gtk.ComboBoxText intervalo;
        Gtk.CheckButton azar;
        string? fuente_tipo = null;
        string? fuente_dato = null;
        Gtk.ComboBoxText inactividad;

        public PanelDesktopScreenSaver () {
            id = "com.apple.preference.desktopscreeneffect";
            nombre = "Desktop & Screen Saver";
            palabras = "desktop, wallpaper, background, screen saver, screensaver, picture, start after, clock, hot corners";
        }

        static string fondos () {
            return Path.build_filename (Environment.get_home_dir (), ".local", "share", "mint-macos", "fondos");
        }

        static string archivo_carpetas () {
            return Path.build_filename (Environment.get_home_dir (), ".config", "mint-macos", "fondos-carpetas.json");
        }

        static string[] carpetas () {
            string[] salida = {};
            try {
                var p = new Json.Parser ();
                p.load_from_file (archivo_carpetas ());
                var raiz = p.get_root ();
                if (raiz != null && raiz.get_node_type () == Json.NodeType.ARRAY) {
                    var a = raiz.get_array ();
                    for (uint i = 0; i < a.get_length (); i++) {
                        var n = a.get_element (i);
                        if (n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (string)) {
                            salida += n.get_string ();
                        }
                    }
                }
            } catch (Error e) {
            }
            return salida;
        }

        /** Como json.dump de una lista de textos en Python: ["a", "b"]. */
        static void guardar_carpetas (string[] lista) {
            var sb = new StringBuilder ("[");
            for (int i = 0; i < lista.length; i++) {
                if (i > 0) {
                    sb.append (", ");
                }
                escribir_cadena (sb, lista[i]);
            }
            sb.append ("]");
            try {
                DirUtils.create_with_parents (Path.get_dirname (archivo_carpetas ()), 0755);
                FileUtils.set_contents (archivo_carpetas (), sb.str);
            } catch (Error e) {
            }
        }

        static Gtk.Widget gris_motivo (Gtk.Widget w, string motivo = "Not available on this computer.") {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        // ── la página ────────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            cargando = true;
            bg = abrir_settings (BG);
            cfg_dia = abrir_settings ("org.cinnamon.desktop.background.slideshow");
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 12;
            var stack = new Gtk.Stack ();
            stack.add_titled (pagina_escritorio (), "desktop", "Desktop");
            stack.add_titled (pagina_protector (), "screensaver", "Screen Saver");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_ESCRITORIO_PESTANA");        // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            cargando = false;
            return caja;
        }

        // ── Desktop ──────────────────────────────────────────────────────
        Gtk.Widget pagina_escritorio () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            margenes (pagina, 14, 14, 18, 18);

            var arriba = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            vista = new Gtk.Image ();
            var marco_v = marco_lista ();
            marco_v.add (vista);
            arriba.pack_start (marco_v, false, false, 0);
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            nombre_l = new Gtk.Label (null);
            nombre_l.xalign = 0;
            nombre_l.margin_top = 4;
            nombre_l.margin_bottom = 4;
            der.pack_start (nombre_l, false, false, 0);
            var din = new Gtk.ComboBoxText ();
            din.append ("d", "Dark (Still)");
            din.set_active (0);
            der.pack_start (gris_motivo (din, "The desktop does not change with the time of day on this computer."), false, false, 0);
            arriba.pack_start (der, false, false, 0);
            pagina.pack_start (arriba, false, false, 0);

            var medio = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            arbol = new Gtk.TreeStore (3, typeof (string), typeof (string), typeof (string));       // texto, tipo, dato
            Gtk.TreeIter apple, carpetas_it, hijo;
            arbol.append (out apple, null);
            arbol.set (apple, 0, "Apple", 1, "grupo", 2, "", -1);
            arbol.append (out hijo, apple);
            arbol.set (hijo, 0, "Desktop Pictures", 1, "fotos", 2, "", -1);
            arbol.append (out hijo, apple);
            arbol.set (hijo, 0, "Colors", 1, "colores", 2, "", -1);
            arbol.append (out carpetas_it, null);
            arbol.set (carpetas_it, 0, "Folders", 1, "grupo", 2, "", -1);
            var pics = Path.build_filename (Environment.get_home_dir (), "Pictures");
            arbol.append (out hijo, carpetas_it);
            arbol.set (hijo, 0, "Pictures", 1, "carpeta", 2, pics, -1);
            foreach (var c in carpetas ()) {
                arbol.append (out hijo, carpetas_it);
                var sin_barra = c.has_suffix ("/") ? c.substring (0, c.length - 1) : c;
                var b = Path.get_basename (sin_barra);
                arbol.set (hijo, 0, b != "" ? b : c, 1, "carpeta", 2, c, -1);
            }
            lateral = new Gtk.TreeView.with_model (arbol);
            lateral.headers_visible = false;
            lateral.append_column (new Gtk.TreeViewColumn.with_attributes ("", new Gtk.CellRendererText (), "text", 0, null));
            lateral.expand_all ();
            lateral.get_selection ().changed.connect (() => fuente (lateral.get_selection ()));
            var pl = new Gtk.ScrolledWindow (null, null);
            pl.set_size_request (170, 230);
            pl.add (lateral);
            var ml = marco_lista ();
            ml.add (pl);
            medio.pack_start (ml, false, false, 0);
            rejilla = new Gtk.FlowBox ();
            rejilla.set_selection_mode (Gtk.SelectionMode.SINGLE);
            rejilla.set_max_children_per_line (4);
            rejilla.set_homogeneous (true);
            rejilla.child_activated.connect ((h) => escoger (h as HijoFondo));
            var pr = new Gtk.ScrolledWindow (null, null);
            pr.add (rejilla);
            var mr = marco_lista ();
            mr.add (pr);
            medio.pack_start (mr, true, true, 0);
            pagina.pack_start (medio, true, true, 0);

            var pie = new Gtk.Grid ();
            pie.column_spacing = 10;
            pie.row_spacing = 6;
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            var mas = new Gtk.Button.with_label ("+");
            mas.clicked.connect (() => agregar_carpeta ());
            var menos = new Gtk.Button.with_label ("−");
            menos.clicked.connect (() => quitar_carpeta ());
            botones.pack_start (mas, false, false, 0);
            botones.pack_start (menos, false, false, 0);
            pie.attach (botones, 0, 0, 1, 2);
            cambiar = new Gtk.CheckButton.with_label ("Change picture:");
            intervalo = new Gtk.ComboBoxText ();
            for (int i = 0; i < INTERVALOS_MIN.length; i++) {
                intervalo.append (INTERVALOS_MIN[i].to_string (), INTERVALOS_TXT[i]);
            }
            string retraso = cfg_dia != null ? cfg_dia.get_int ("delay").to_string () : "30";
            bool conocido = false;
            foreach (var m in INTERVALOS_MIN) {
                if (m.to_string () == retraso) {
                    conocido = true;
                }
            }
            intervalo.set_active_id (conocido ? retraso : "30");
            azar = new Gtk.CheckButton.with_label ("Random order");
            cambiar.active = cfg_dia != null && cfg_dia.get_boolean ("slideshow-enabled");
            azar.active = cfg_dia != null && cfg_dia.get_boolean ("random-order");
            pie.attach (cambiar, 1, 0, 1, 1);
            pie.attach (intervalo, 2, 0, 1, 1);
            pie.attach (azar, 1, 1, 2, 1);
            cambiar.toggled.connect (() => slideshow ());
            azar.toggled.connect (() => slideshow ());
            intervalo.changed.connect (() => slideshow ());
            pagina.pack_start (pie, false, false, 0);

            mostrar_actual ();
            lateral.get_selection ().select_path (new Gtk.TreePath.from_string ("0:0"));
            return pagina;
        }

        void mostrar_actual () {
            string? ruta = null;
            if (bg != null) {
                var uri = bg.get_string ("picture-uri");
                if (uri != "") {
                    ruta = File.new_for_uri (uri).get_path ();
                }
            }
            try {
                vista.set_from_pixbuf (new Gdk.Pixbuf.from_file_at_scale (ruta, 118, 74, false));
            } catch (Error e) {
                vista.clear ();
            }
            string nombre_f = "";
            if (ruta != null) {
                var base_ = Path.get_basename (ruta);
                int punto = base_.last_index_of (".");
                nombre_f = punto > 0 ? base_.substring (0, punto) : base_;
            }
            nombre_l.set_text (titulo_python (nombre_f.replace ("-", " ")));
        }

        /** str.title() de Python para texto sencillo: cada palabra, con la primera letra en mayúscula y el resto en minúscula. */
        static string titulo_python (string s) {
            var sb = new StringBuilder ();
            bool inicio = true;
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                if (c.isalpha ()) {
                    sb.append_unichar (inicio ? c.toupper () : c.tolower ());
                    inicio = false;
                } else {
                    sb.append_unichar (c);
                    inicio = true;
                }
            }
            return sb.str;
        }

        void fuente (Gtk.TreeSelection sel) {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!sel.get_selected (out modelo, out it)) {
                return;
            }
            string tipo, dato;
            modelo.get (it, 1, out tipo, 2, out dato, -1);
            if (tipo == "grupo") {
                return;
            }
            foreach (var h in rejilla.get_children ()) {
                rejilla.remove (h);
            }
            fuente_tipo = tipo;
            fuente_dato = dato;
            var elementos = new List<ElementoFondo> ();
            if (tipo == "fotos") {
                try {
                    var p = new Json.Parser ();
                    p.load_from_file (Path.build_filename (fondos (), "orden.json"));
                    var arr = p.get_root ().get_object ().get_array_member ("fotos");
                    for (uint i = 0; i < arr.get_length (); i++) {
                        var n = arr.get_string_element (i);
                        var e = new ElementoFondo ();
                        e.rotulo = n;
                        e.ruta = Path.build_filename (fondos (), "fotos", n + ".jpg");
                        e.mini = Path.build_filename (fondos (), "miniaturas", n + ".jpg");
                        elementos.append (e);
                    }
                } catch (Error e) {
                }
            } else if (tipo == "colores") {
                var colores = Path.build_filename (fondos (), "colores");
                var nombres = listar (colores, false);
                foreach (var f in nombres) {
                    var e = new ElementoFondo ();
                    int punto = f.last_index_of (".");
                    e.rotulo = punto > 0 ? f.substring (0, punto) : f;
                    e.ruta = Path.build_filename (colores, f);
                    e.mini = e.ruta;
                    elementos.append (e);
                }
            } else {
                var archivos = listar (dato, true);
                int n = 0;
                foreach (var f in archivos) {
                    if (n++ >= 80) {
                        break;
                    }
                    var e = new ElementoFondo ();
                    e.rotulo = f;
                    e.ruta = Path.build_filename (dato, f);
                    e.mini = e.ruta;
                    elementos.append (e);
                }
            }
            foreach (var e in elementos) {
                Gdk.Pixbuf pb;
                try {
                    pb = new Gdk.Pixbuf.from_file_at_scale (e.mini, 96, 60, true);
                } catch (Error er) {
                    continue;
                }
                var h = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                h.margin = 4;
                h.pack_start (new Gtk.Image.from_pixbuf (pb), false, false, 0);
                var hijo = new HijoFondo ();
                hijo.add (h);
                hijo.ruta = e.ruta;
                hijo.set_tooltip_text (e.rotulo);
                rejilla.add (hijo);
            }
            rejilla.show_all ();
        }

        /** Los nombres de una carpeta ordenados; solo imágenes (.jpg, .jpeg, .png) si se pide. */
        static GenericArray<string> listar (string carpeta, bool solo_imagenes) {
            var lista = new GenericArray<string> ();
            try {
                var dir = Dir.open (carpeta);
                string? n;
                while ((n = dir.read_name ()) != null) {
                    var m = n.down ();
                    if (!solo_imagenes || m.has_suffix (".jpg") || m.has_suffix (".jpeg") || m.has_suffix (".png")) {
                        lista.add (n);
                    }
                }
            } catch (Error e) {
            }
            lista.sort ((a, b) => strcmp (a, b));
            return lista;
        }

        void escoger (HijoFondo? hijo) {
            if (cargando || prueba || hijo == null || bg == null) {
                return;
            }
            bg.set_string ("picture-uri", File.new_for_path (hijo.ruta).get_uri ());
            bg.set_string ("picture-options", "zoom");
            mostrar_actual ();
        }

        /** Change picture / Random order: el slideshow de Cinnamon sobre la carpeta escogida. */
        void slideshow () {
            if (cargando || prueba || cfg_dia == null) {
                return;
            }
            if (cambiar.active && fuente_tipo != null) {
                string? carpeta = null;
                if (fuente_tipo == "fotos") {
                    carpeta = Path.build_filename (fondos (), "fotos");
                } else if (fuente_tipo == "carpeta") {
                    carpeta = fuente_dato;
                }
                if (carpeta != null && FileUtils.test (carpeta, FileTest.IS_DIR)) {
                    var uri = File.new_for_path (carpeta).get_uri ();
                    cfg_dia.set_string ("image-source", uri.has_prefix ("file://") ? "directory://" + uri.substring (7) : uri);
                }
            }
            int minutos = int.parse (intervalo.get_active_id () ?? "30");
            cfg_dia.set_int ("delay", minutos != 0 ? minutos : 30);
            cfg_dia.set_boolean ("random-order", azar.active);
            cfg_dia.set_boolean ("slideshow-enabled", cambiar.active);
        }

        void agregar_carpeta () {
            var d = new Gtk.FileChooserDialog ("Choose a folder", ventana, Gtk.FileChooserAction.SELECT_FOLDER);
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            d.add_button ("Choose", Gtk.ResponseType.OK);
            if (d.run () == Gtk.ResponseType.OK) {
                var ruta = d.get_filename ();
                var lista = carpetas ();
                bool ya = false;
                foreach (var c in lista) {
                    if (c == ruta) {
                        ya = true;
                    }
                }
                if (!ya && !prueba) {
                    lista += ruta;
                    guardar_carpetas (lista);
                    Gtk.TreeIter padre, hijo;
                    arbol.get_iter (out padre, new Gtk.TreePath.from_string ("1"));
                    arbol.append (out hijo, padre);
                    var sin_barra = ruta.has_suffix ("/") ? ruta.substring (0, ruta.length - 1) : ruta;
                    var b = Path.get_basename (sin_barra);
                    arbol.set (hijo, 0, b != "" ? b : ruta, 1, "carpeta", 2, ruta, -1);
                    lateral.expand_all ();
                }
            }
            d.destroy ();
        }

        void quitar_carpeta () {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!lateral.get_selection ().get_selected (out modelo, out it)) {
                return;
            }
            string tipo, ruta;
            modelo.get (it, 1, out tipo, 2, out ruta, -1);
            if (tipo != "carpeta" || ruta == Path.build_filename (Environment.get_home_dir (), "Pictures")) {
                return;
            }
            if (!prueba) {
                string[] resto = {};
                foreach (var c in carpetas ()) {
                    if (c != ruta) {
                        resto += c;
                    }
                }
                guardar_carpetas (resto);
            }
            arbol.remove (ref it);
        }

        // ── Screen Saver ─────────────────────────────────────────────────
        Gtk.Widget pagina_protector () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            margenes (pagina, 14, 14, 18, 18);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var lista = new Gtk.ListBox ();
            lista.set_size_request (200, 230);
            foreach (var n in PROTECTORES) {
                var fila = new Gtk.ListBoxRow ();
                var l = new Gtk.Label (n);
                l.margin = 14;
                fila.add (l);
                lista.add (fila);
            }
            var ml = marco_lista ();
            ml.add (gris_motivo (lista, "Apple’s screen savers are not available on this computer."));
            cuerpo.pack_start (ml, false, false, 0);
            var vista_p = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            vista_p.halign = Gtk.Align.CENTER;
            vista_p.valign = Gtk.Align.CENTER;
            vista_p.pack_start (gris (new Gtk.Button.with_label ("Screen Saver Options…")), false, false, 0);
            var mv = marco_lista ();
            mv.add (vista_p);
            cuerpo.pack_start (mv, true, true, 8);
            pagina.pack_start (cuerpo, true, true, 0);

            var pie = new Gtk.Grid ();
            pie.column_spacing = 10;
            pie.row_spacing = 6;
            var sa = new Gtk.Label ("Start after:");
            sa.xalign = 1.0f;
            pie.attach (sa, 0, 0, 1, 1);
            var sesion = abrir_settings ("org.cinnamon.desktop.session");
            inactividad = new Gtk.ComboBoxText ();
            for (int i = 0; i < INACTIVIDAD_S.length; i++) {
                inactividad.append (INACTIVIDAD_S[i].to_string (), INACTIVIDAD_TXT[i]);
            }
            uint actual = 0;
            if (sesion != null && "idle-delay" in sesion.list_keys ()) {
                actual = sesion.get_uint ("idle-delay");
            }
            if (!inactividad.set_active_id (actual.to_string ())) {
                inactividad.append (actual.to_string (), "%u Minutes".printf (actual / 60));
                inactividad.set_active_id (actual.to_string ());
            }
            inactividad.changed.connect (() => {
                if (!cargando && !prueba && sesion != null) {
                    sesion.set_uint ("idle-delay", (uint) int.parse (inactividad.get_active_id ()));
                }
            });
            pie.attach (inactividad, 1, 0, 1, 1);
            var salvapantallas = abrir_settings ("org.cinnamon.desktop.screensaver");
            var reloj = new Gtk.CheckButton.with_label ("Show with clock");
            reloj.active = salvapantallas != null && salvapantallas.get_boolean ("show-clock");
            reloj.toggled.connect (() => {
                if (!cargando && !prueba && salvapantallas != null) {
                    salvapantallas.set_boolean ("show-clock", reloj.active);
                }
            });
            pie.attach (reloj, 2, 0, 1, 1);
            pie.attach (gris (new Gtk.CheckButton.with_label ("Use random screen saver")), 2, 1, 1, 1);
            var esquinas = new Gtk.Button.with_label ("Hot Corners…");
            esquinas.clicked.connect (() => {
                var mc = new PanelMissionControl ();
                mc.ventana = ventana;
                mc.hoja ();
            });
            pie.attach (esquinas, 3, 0, 1, 1);
            pagina.pack_start (pie, false, false, 0);
            return pagina;
        }
    }
}
