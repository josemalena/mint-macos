/*
 * Activity Monitor (capturas de High Sierra 10.13.6, que José dio como fuente para Catalina): la barra de herramientas con
 * detener / inspeccionar / engranaje, el control segmentado CPU · Memory · Energy · Disk · Network y el buscador; la lista de
 * procesos y, debajo, el panel de cada pestaña. Una pestaña más, «Resources», con las gráficas de GNOME System Monitor (CPU por
 * núcleo, memoria y swap, red). Los datos vienen de org.mintmacos.Monitor1. Lo que el servicio no mide (Energy, Ports, red por
 * proceso) queda vacío, sin inventar nada. Sin capturas todavía: los menús, el engranaje, el inspector y el diálogo Quit.
 */
namespace Actividad {
    const string CSS = """
window.act-ventana label { font-family: ".SF NS"; }
.act-barra { padding: 6px 10px; }
.act-segmentos button { background-image: none; background-color: #ffffff; color: #262626; border: 1px solid #b8b8b8;
  border-radius: 0; padding: 1px 14px; min-height: 0; box-shadow: none; text-shadow: none; }
.act-segmentos button:first-child { border-radius: 5px 0 0 5px; }
.act-segmentos button:last-child { border-radius: 0 5px 5px 0; }
.act-segmentos button:checked { background-color: #6b6b6b; color: #ffffff; }
.act-segmentos button label { font-size: 13px; }
button.act-redondo { background-image: none; background-color: #f6f6f6; border: 1px solid #b8b8b8; border-radius: 10px;
  padding: 0 6px; min-height: 18px; min-width: 22px; box-shadow: none; }
.act-lista { background-color: #ffffff; }
.act-lista header button { font-size: 11px; padding: 2px 6px; background-image: none; background-color: #ffffff;
  border-width: 0 1px 1px 0; border-radius: 0; border-color: #d4d4d4; box-shadow: none; }
.act-lista:selected, .act-lista row:selected { background-color: #1e62d0; color: #ffffff; }
.act-panel { background-color: #f3f3f3; border-top: 1px solid #c9c9c9; padding: 12px; }
.act-caja { background-color: #ffffff; border: 1px solid #b0b0b0; }
.act-clave { font-size: 11px; }
.act-valor { font-size: 11px; }
.act-rojo { color: #e0201b; }
.act-azul { color: #1f1fd0; }
.act-titulo-grafica { font-size: 9px; font-weight: bold; opacity: 0.6; letter-spacing: 0.5px; }
.act-seccion { font-size: 13px; font-weight: bold; }
.act-leyenda { font-size: 11px; }
""";

    struct Col {
        string clave;
        string titulo;
        bool derecha;
        int ancho;
    }

    public class Ventana : Gtk.ApplicationWindow {
        Motor motor = Motor.instancia;
        Gtk.Stack cuerpo;
        Gtk.TreeView lista;
        Gtk.ListStore almacen;
        Gtk.TreeModelFilter filtro;
        Gtk.TreeModelSort orden;
        Gtk.Stack paneles;
        Gtk.Button detener;
        Gtk.SearchEntry busqueda;
        Gtk.HeaderBar cabecera;
        HashTable<string, Gtk.ToggleButton> botones = new HashTable<string, Gtk.ToggleButton> (str_hash, str_equal);
        HashTable<int, Gtk.TreeIter?> filas = new HashTable<int, Gtk.TreeIter?> (direct_hash, direct_equal);
        HashTable<string, Gtk.Label> valores = new HashTable<string, Gtk.Label> (str_hash, str_equal);
        HashTable<string, Area> graficas = new HashTable<string, Area> (str_hash, str_equal);
        HashTable<string, Gtk.Label> leyendas = new HashTable<string, Gtk.Label> (str_hash, str_equal);
        Gtk.ComboBoxText? selector_disco = null;
        Gtk.ComboBoxText? selector_red = null;
        string pestana = "";
        bool cambiando = false;
        bool pidiendo = false;
        string yo = Environment.get_user_name ();
        double ultimo_cpu_total = 0;

        string filtro_proceso = "todos";
        uint frecuencia_ms = 1000;

        public Ventana (Gtk.Application app) {
            Object (application: app);
            show_menubar = false;       // el menú va al panel (menú global), no dentro de la ventana
            title = "Activity Monitor (All Processes)";
            set_default_size (800, 560);
            window_position = Gtk.WindowPosition.CENTER;
            get_style_context ().add_class ("act-ventana");
            MacOS.aplicar_css (CSS);

            cabecera = new Gtk.HeaderBar ();
            cabecera.show_close_button = true;
            cabecera.decoration_layout = "close,minimize,maximize:";
            cabecera.title = "Activity Monitor (All Processes)";
            set_titlebar (cabecera);

            var raiz = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            raiz.pack_start (barra_herramientas (), false, false, 0);

            cuerpo = new Gtk.Stack ();
            cuerpo.add_named (pagina_procesos (), "procesos");
            cuerpo.add_named (pagina_recursos (), "resources");
            raiz.pack_start (cuerpo, true, true, 0);
            add (raiz);

            string e;
            if (!motor.conectar (out e)) warning ("sin monitor: %s", e);
            motor.muestreado.connect (al_muestrear);
            motor.suscribir.begin (1000, (o, res) => {
                try { motor.suscribir.end (res); } catch (GLib.Error err) { warning ("%s", err.message); }
            });
            destroy.connect (() => { motor.soltar.begin (); });
            registrar_acciones ();
            show_all ();
            ir_a ("cpu");
        }

        SimpleAction? accion_salir = null;

        /** Las acciones win.* que la barra de menús (actividad_menus.vala) llama; las que no están aquí van en gris. */
        void registrar_acciones () {
            var cerrar = new SimpleAction ("cerrar", null);
            cerrar.activate.connect (() => { close (); });
            add_action (cerrar);
            var buscar = new SimpleAction ("buscar", null);
            buscar.activate.connect (() => { busqueda.grab_focus (); });
            add_action (buscar);
            var minimizar = new SimpleAction ("minimizar", null);
            minimizar.activate.connect (() => { iconify (); });
            add_action (minimizar);
            var zoom = new SimpleAction ("zoom", null);
            zoom.activate.connect (() => { if (is_maximized) unmaximize (); else maximize (); });
            add_action (zoom);
            var principal = new SimpleAction ("principal", null);
            principal.activate.connect (() => { present (); });
            add_action (principal);
            accion_salir = new SimpleAction ("salir", null);
            accion_salir.set_enabled (false);
            accion_salir.activate.connect (() => { pedir_salida (); });
            add_action (accion_salir);

            var frecuencia = new SimpleAction.stateful ("frecuencia", VariantType.STRING, new Variant.string ("1"));
            frecuencia.activate.connect ((p) => {
                frecuencia.set_state (p);
                frecuencia_ms = (uint) int.parse (p.get_string ()) * 1000;
                motor.suscribir.begin (frecuencia_ms, (o, res) => {
                    try { motor.suscribir.end (res); } catch (GLib.Error e) { warning ("%s", e.message); }
                });
            });
            add_action (frecuencia);
            var filtro_a = new SimpleAction.stateful ("filtro", VariantType.STRING, new Variant.string ("todos"));
            filtro_a.activate.connect ((p) => {
                filtro_a.set_state (p);
                filtro_proceso = p.get_string ();
                filtro.refilter ();
            });
            add_action (filtro_a);

            string[,] atajos = { { "win.cerrar", "<Primary>w" }, { "win.buscar", "<Primary>f" }, { "win.minimizar", "<Primary>m" },
                                  { "win.principal", "<Primary>1" }, { "win.salir", "<Primary><Alt>q" } };
            for (int i = 0; i < atajos.length[0]; i++) application.set_accels_for_action (atajos[i, 0], { atajos[i, 1] });
            application.set_accels_for_action ("win.buscar", { "<Primary>f", "<Primary><Alt>f" });
        }

        // ---- barra de herramientas ------------------------------------------------------------------------------

        Gtk.Widget barra_herramientas () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            caja.get_style_context ().add_class ("act-barra");

            var izq = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            detener = new Gtk.Button.from_icon_name ("window-close-symbolic", Gtk.IconSize.MENU);
            detener.get_style_context ().add_class ("act-redondo");
            detener.sensitive = false;
            detener.tooltip_text = "Stop";
            detener.clicked.connect (pedir_salida);
            izq.pack_start (detener, false, false, 0);
            // El inspector y el engranaje esperan sus capturas (no hay ninguna de la ventana de inspección ni del menú).
            var info = new Gtk.Button.from_icon_name ("dialog-information-symbolic", Gtk.IconSize.MENU);
            info.get_style_context ().add_class ("act-redondo");
            info.sensitive = false;
            info.tooltip_text = "Inspect selected process";
            izq.pack_start (info, false, false, 0);
            var engranaje = new Gtk.Button.from_icon_name ("emblem-system-symbolic", Gtk.IconSize.MENU);
            engranaje.get_style_context ().add_class ("act-redondo");
            engranaje.sensitive = false;
            engranaje.tooltip_text = "System diagnostics options";
            izq.pack_start (engranaje, false, false, 0);
            caja.pack_start (izq, false, false, 0);

            var seg = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            seg.get_style_context ().add_class ("act-segmentos");
            seg.halign = Gtk.Align.CENTER;
            seg.tooltip_text = "Display processes in the category specified";
            string[] claves = { "cpu", "memory", "energy", "disk", "network", "resources" };
            string[] titulos = { "CPU", "Memory", "Energy", "Disk", "Network", "Resources" };
            for (int i = 0; i < claves.length; i++) {
                var b = new Gtk.ToggleButton.with_label (titulos[i]);
                var clave = claves[i];
                b.clicked.connect (() => { if (!cambiando) ir_a (clave); });
                botones.insert (clave, b);
                seg.pack_start (b, false, false, 0);
            }
            caja.pack_start (seg, true, true, 0);

            busqueda = new Gtk.SearchEntry ();
            busqueda.width_chars = 22;
            busqueda.placeholder_text = "Search";
            busqueda.tooltip_text = "Show only processes containing the string specified";
            busqueda.search_changed.connect (() => { filtro.refilter (); });
            caja.pack_end (busqueda, false, false, 0);
            return caja;
        }

        // ---- la lista de procesos -----------------------------------------------------------------------------------

        Gtk.Widget pagina_procesos () {
            almacen = new Gtk.ListStore (1, typeof (Fila));
            filtro = new Gtk.TreeModelFilter (almacen, null);
            filtro.set_visible_func (visible);
            orden = new Gtk.TreeModelSort.with_model (filtro);
            lista = new Gtk.TreeView.with_model (orden);
            lista.get_style_context ().add_class ("act-lista");
            lista.headers_clickable = true;
            lista.rules_hint = true;
            lista.fixed_height_mode = false;
            lista.get_selection ().changed.connect (al_elegir);
            var sw = new Gtk.ScrolledWindow (null, null);
            sw.add (lista);

            paneles = new Gtk.Stack ();
            paneles.get_style_context ().add_class ("act-panel");
            paneles.add_named (panel_cpu (), "cpu");
            paneles.add_named (panel_memoria (), "memory");
            paneles.add_named (panel_energia (), "energy");
            paneles.add_named (panel_disco (), "disk");
            paneles.add_named (panel_red (), "network");

            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            caja.pack_start (sw, true, true, 0);
            caja.pack_start (paneles, false, false, 0);
            return caja;
        }

        bool visible (Gtk.TreeModel m, Gtk.TreeIter it) {
            Fila? f;
            m.get (it, 0, out f);
            if (f == null) return false;
            // Energy lista aplicaciones, no procesos: las que tienen ícono (su .desktop).
            if (pestana == "energy" && f.icono == "") return false;
            if (!pasa_filtro (f)) return false;
            var q = busqueda.text.strip ().down ();
            if (q == "") return true;
            return f.nombre.down ().contains (q) || f.usuario.down ().contains (q) || f.pid.to_string () == q;
        }

        /** View ▸ All / My / System / Other User Processes. «System» es lo de usuarios del sistema (uid < 1000, root incluido). */
        bool pasa_filtro (Fila f) {
            if (filtro_proceso == "todos") return true;
            if (filtro_proceso == "mios") return f.usuario == yo;
            unowned Posix.Passwd? pw = Posix.getpwnam (f.usuario);
            bool de_sistema = pw != null && pw.pw_uid < 1000;
            if (filtro_proceso == "sistema") return de_sistema;
            if (filtro_proceso == "otros") return f.usuario != yo && !de_sistema;
            return true;
        }

        Col[] columnas_de (string p) {
            switch (p) {
            case "memory":
                return { Col () { clave = "nombre", titulo = "Process Name", derecha = false, ancho = 250 },
                         Col () { clave = "memoria", titulo = "Memory", derecha = true, ancho = 110 },
                         Col () { clave = "comprimida", titulo = "Compressed Mem", derecha = true, ancho = 120 },
                         Col () { clave = "hilos", titulo = "Threads", derecha = true, ancho = 80 },
                         Col () { clave = "puertos", titulo = "Ports", derecha = true, ancho = 70 },
                         Col () { clave = "pid", titulo = "PID", derecha = true, ancho = 70 },
                         Col () { clave = "usuario", titulo = "User", derecha = false, ancho = 90 } };
            case "energy":
                return { Col () { clave = "nombre", titulo = "App Name", derecha = false, ancho = 250 },
                         Col () { clave = "energia", titulo = "Energy Impact", derecha = true, ancho = 110 },
                         Col () { clave = "energia_promedio", titulo = "Avg Energy Impact", derecha = true, ancho = 140 },
                         Col () { clave = "app_nap", titulo = "App Nap", derecha = true, ancho = 80 },
                         Col () { clave = "gpu_alto_rendimiento", titulo = "Requires High Perf GPU", derecha = true, ancho = 170 } };
            case "disk":
                return { Col () { clave = "nombre", titulo = "Process Name", derecha = false, ancho = 250 },
                         Col () { clave = "escrito", titulo = "Bytes Written", derecha = true, ancho = 120 },
                         Col () { clave = "leido", titulo = "Bytes Read", derecha = true, ancho = 120 },
                         Col () { clave = "tipo", titulo = "Kind", derecha = false, ancho = 80 },
                         Col () { clave = "pid", titulo = "PID", derecha = true, ancho = 70 },
                         Col () { clave = "usuario", titulo = "User", derecha = false, ancho = 90 } };
            case "network":
                return { Col () { clave = "nombre", titulo = "Process Name", derecha = false, ancho = 250 },
                         Col () { clave = "red_enviada", titulo = "Sent Bytes", derecha = true, ancho = 110 },
                         Col () { clave = "red_recibida", titulo = "Rcvd Bytes", derecha = true, ancho = 110 },
                         Col () { clave = "paquetes_enviados", titulo = "Sent Packets", derecha = true, ancho = 110 },
                         Col () { clave = "paquetes_recibidos", titulo = "Rcvd Packets", derecha = true, ancho = 110 },
                         Col () { clave = "pid", titulo = "PID", derecha = true, ancho = 70 },
                         Col () { clave = "usuario", titulo = "User", derecha = false, ancho = 90 } };
            default:
                return { Col () { clave = "nombre", titulo = "Process Name", derecha = false, ancho = 250 },
                         Col () { clave = "cpu", titulo = "% CPU", derecha = true, ancho = 90 },
                         Col () { clave = "tiempo_cpu", titulo = "CPU Time", derecha = true, ancho = 100 },
                         Col () { clave = "hilos", titulo = "Threads", derecha = true, ancho = 80 },
                         Col () { clave = "despertares", titulo = "Idle Wake Ups", derecha = true, ancho = 120 },
                         Col () { clave = "pid", titulo = "PID", derecha = true, ancho = 70 },
                         Col () { clave = "usuario", titulo = "User", derecha = false, ancho = 90 } };
            }
        }

        static double valor_de (Fila f, string clave) {
            switch (clave) {
            case "cpu": return f.cpu;
            case "tiempo_cpu": return f.tiempo_cpu;
            case "hilos": return f.hilos;
            case "despertares": return f.despertares;
            case "memoria": return f.memoria;
            case "comprimida": return f.comprimida;
            case "escrito": return f.escrito;
            case "leido": return f.leido;
            case "pid": return f.pid;
            }
            return -1;
        }

        static string texto_de (Fila f, string clave) {
            switch (clave) {
            case "nombre": return f.nombre;
            case "usuario": return f.usuario;
            case "tipo": return f.tipo;
            case "pid": return f.pid.to_string ();
            case "cpu": return f.cpu < 0 ? "" : "%.1f".printf (f.cpu);
            case "tiempo_cpu": return tiempo_texto (f.tiempo_cpu);
            case "hilos": return f.hilos < 0 ? "" : miles (f.hilos);
            case "despertares": return f.despertares < 0 ? "" : miles (f.despertares);
            case "memoria": return bytes_texto (f.memoria, 1);
            case "comprimida": return bytes_texto (f.comprimida, 1);
            case "escrito": return bytes_texto (f.escrito, 1);
            case "leido": return bytes_texto (f.leido, 1);
            }
            return "";      // sin fuente: vacío
        }

        void armar_columnas (string p) {
            foreach (var c in lista.get_columns ()) lista.remove_column (c);
            var cols = columnas_de (p);
            for (int i = 0; i < cols.length; i++) {
                var spec = cols[i];
                var col = new Gtk.TreeViewColumn ();
                col.title = spec.titulo;
                col.resizable = true;
                col.min_width = spec.ancho;
                col.sort_column_id = i;
                col.alignment = spec.derecha ? 1.0f : 0.0f;
                if (spec.clave == "nombre") {
                    var ic = new Gtk.CellRendererPixbuf ();
                    ic.xpad = 4;
                    col.pack_start (ic, false);
                    col.set_cell_data_func (ic, (c, cell, m, it) => {
                        Fila? f;
                        m.get (it, 0, out f);
                        var px = cell as Gtk.CellRendererPixbuf;
                        if (f == null || f.icono == "") { px.icon_name = null; px.pixbuf = vacio_16 (); return; }
                        px.icon_name = f.icono;
                    });
                }
                var tx = new Gtk.CellRendererText ();
                tx.xalign = spec.derecha ? 1.0f : 0.0f;
                tx.ellipsize = Pango.EllipsizeMode.END;
                tx.xpad = 6;
                col.pack_start (tx, true);
                var clave = spec.clave;
                col.set_cell_data_func (tx, (c, cell, m, it) => {
                    Fila? f;
                    m.get (it, 0, out f);
                    ((Gtk.CellRendererText) cell).text = f != null ? texto_de (f, clave) : "";
                });
                orden.set_sort_func (i, (m, a, b) => {
                    Fila? fa, fb;
                    m.get (a, 0, out fa);
                    m.get (b, 0, out fb);
                    if (fa == null || fb == null) return 0;
                    if (clave == "nombre" || clave == "usuario" || clave == "tipo")
                        return strcmp (texto_de (fa, clave).down (), texto_de (fb, clave).down ());
                    double x = valor_de (fa, clave), y = valor_de (fb, clave);
                    return x < y ? -1 : (x > y ? 1 : 0);
                });
                lista.append_column (col);
            }
            // El orden de cada pestaña, como en las capturas: % CPU, Memory, Avg Energy Impact, Bytes Written y Sent Bytes.
            int orden_col = p == "memory" || p == "disk" || p == "network" || p == "energy" ? 1 : 1;
            if (p == "energy") orden_col = 2;
            orden.set_sort_column_id (orden_col, Gtk.SortType.DESCENDING);
        }

        Gdk.Pixbuf? pixbuf_vacio = null;
        Gdk.Pixbuf vacio_16 () {
            if (pixbuf_vacio == null) {
                pixbuf_vacio = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, 16, 16);
                pixbuf_vacio.fill (0);
            }
            return pixbuf_vacio;
        }

        void al_elegir () {
            Gtk.TreeModel m;
            Gtk.TreeIter it;
            bool propio = false;
            if (lista.get_selection ().get_selected (out m, out it)) {
                Fila? f;
                m.get (it, 0, out f);
                propio = f != null && f.usuario == yo;
            }
            detener.sensitive = propio;
            if (accion_salir != null) accion_salir.set_enabled (propio);
        }

        // ---- pestañas ---------------------------------------------------------------------------------------------

        public void ir_a (string p) {
            if (p == "") p = "cpu";
            cambiando = true;
            foreach (var k in botones.get_keys ()) botones.lookup (k).active = (k == p);
            cambiando = false;
            pestana = p;
            if (p == "resources") {
                cuerpo.visible_child_name = "resources";
                cabecera.title = "Activity Monitor";
                title = "Activity Monitor";
            } else {
                cuerpo.visible_child_name = "procesos";
                paneles.visible_child_name = p;
                armar_columnas (p);
                var t = p == "energy" ? "Activity Monitor (Applications)" : "Activity Monitor (All Processes)";
                cabecera.title = t;
                title = t;
                filtro.refilter ();
            }
            al_muestrear ();
        }

        // ---- datos --------------------------------------------------------------------------------------------------

        void al_muestrear () {
            if (pidiendo) return;
            pidiendo = true;
            actualizar.begin ();
        }

        async void actualizar () {
            try {
                var procs = yield motor.procesos ();
                aplicar_procesos (procs);
                var r = yield motor.resumen ();
                aplicar_resumen (r);
                yield aplicar_series ();
            } catch (GLib.Error e) {
                warning ("monitor: %s", e.message);
            }
            pidiendo = false;
        }

        void aplicar_procesos (GenericArray<Fila> procs) {
            var vivos = new HashTable<int, bool> (direct_hash, direct_equal);
            for (int i = 0; i < procs.length; i++) {
                var f = procs[i];
                vivos.replace (f.pid, true);
                Gtk.TreeIter? it = filas.lookup (f.pid);
                if (it == null) {
                    Gtk.TreeIter nuevo;
                    almacen.append (out nuevo);
                    almacen.set (nuevo, 0, f, -1);
                    filas.replace (f.pid, nuevo);
                } else {
                    almacen.set (it, 0, f, -1);
                }
            }
            var fuera = new GenericArray<int> ();
            filas.foreach ((pid, it) => { if (!vivos.contains (pid)) fuera.add (pid); });
            for (int i = 0; i < fuera.length; i++) {
                Gtk.TreeIter? it = filas.lookup (fuera[i]);
                if (it != null) almacen.remove (ref it);
                filas.remove (fuera[i]);
            }
        }

        // ---- los paneles de abajo ----------------------------------------------------------------------------------

        Gtk.Box caja3 (Gtk.Widget izq, Gtk.Widget centro, Gtk.Widget der) {
            var fuera = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            fuera.halign = Gtk.Align.CENTER;
            fuera.get_style_context ().add_class ("act-caja");
            izq.set_size_request (190, 86);
            centro.set_size_request (190, 86);
            der.set_size_request (190, 86);
            fuera.pack_start (izq, false, false, 0);
            fuera.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);
            fuera.pack_start (centro, false, false, 0);
            fuera.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);
            fuera.pack_start (der, false, false, 0);
            return fuera;
        }

        /** Filas «Etiqueta:  valor»; `claves` son los nombres con los que se actualizan. `color`: "", "rojo" o "azul" por fila. */
        Gtk.Grid filas_de (string[] etiquetas, string[] claves, string[] colores) {
            var g = new Gtk.Grid ();
            g.margin = 6;
            g.row_spacing = 3;
            g.column_spacing = 8;
            for (int i = 0; i < etiquetas.length; i++) {
                var k = new Gtk.Label (etiquetas[i]);
                k.xalign = 0;
                k.get_style_context ().add_class ("act-clave");
                g.attach (k, 0, i, 1, 1);
                var v = new Gtk.Label ("");
                v.xalign = 1;
                v.hexpand = true;
                v.get_style_context ().add_class ("act-valor");
                if (colores[i] == "rojo") v.get_style_context ().add_class ("act-rojo");
                if (colores[i] == "azul") v.get_style_context ().add_class ("act-azul");
                g.attach (v, 1, i, 1, 1);
                valores.replace (claves[i], v);
            }
            return g;
        }

        Gtk.Widget grafica_con_titulo (string titulo, Area a, Gtk.Widget? selector = null) {
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            c.margin = 6;
            if (selector != null) {
                c.pack_start (selector, false, false, 0);
            } else {
                var t = new Gtk.Label (titulo);
                t.get_style_context ().add_class ("act-titulo-grafica");
                c.pack_start (t, false, false, 0);
            }
            c.pack_start (a, true, true, 0);
            return c;
        }

        Gtk.Widget panel_cpu () {
            var a = new Area (170, 62);
            a.apilado = true;
            a.maximo = 100;
            a.rejilla = false;
            a.agregar ("cpu.sistema", 0.88, 0.13, 0.11);
            a.agregar ("cpu.usuario", 0.12, 0.12, 0.82);
            graficas.replace ("cpu_carga", a);
            return caja3 (filas_de ({ "System:", "User:", "Idle:" }, { "cpu_sistema", "cpu_usuario", "cpu_ocioso" }, { "rojo", "azul", "" }),
                          grafica_con_titulo ("CPU LOAD", a),
                          filas_de ({ "Threads:", "Processes:" }, { "hilos", "procesos" }, { "", "" }));
        }

        Gtk.Widget panel_memoria () {
            var a = new Area (170, 62);
            a.maximo = 100;
            a.rejilla = false;
            a.agregar ("mem.presion", 0.20, 0.72, 0.25);
            graficas.replace ("mem_presion", a);
            return caja3 (grafica_con_titulo ("MEMORY PRESSURE", a),
                          filas_de ({ "Physical Memory:", "Memory Used:", "Cached Files:", "Swap Used:" },
                                    { "mem_fisica", "mem_usada", "mem_cache", "swap_usada" }, { "", "", "", "" }),
                          filas_de ({ "App Memory:", "Wired Memory:", "Compressed:" },
                                    { "mem_app", "mem_wired", "mem_comprimida" }, { "", "", "" }));
        }

        Gtk.Widget panel_energia () {
            // Energy Impact no tiene fuente en Linux sin root: el panel enseña solo lo que sí se mide (la batería, si la hay).
            var vacio = new Gtk.Label ("");
            return caja3 (vacio, filas_de ({ "Remaining charge:" }, { "bateria_carga" }, { "" }), new Gtk.Label (""));
        }

        Gtk.ComboBoxText selector (string[] opciones) {
            var c = new Gtk.ComboBoxText ();
            foreach (var o in opciones) c.append_text (o);
            c.active = 0;
            c.halign = Gtk.Align.CENTER;
            return c;
        }

        Gtk.Widget panel_disco () {
            var a = new Area (170, 52);
            a.rejilla = false;
            a.agregar ("disco.lecturas", 0.12, 0.12, 0.82);
            a.agregar ("disco.escrituras", 0.88, 0.13, 0.11);
            graficas.replace ("disco", a);
            selector_disco = selector ({ "IO", "Data" });
            selector_disco.changed.connect (() => {
                bool io = selector_disco.active == 0;
                a.series.remove_range (0, a.series.length);
                if (io) { a.agregar ("disco.lecturas", 0.12, 0.12, 0.82); a.agregar ("disco.escrituras", 0.88, 0.13, 0.11); }
                else { a.agregar ("disco.leido", 0.12, 0.12, 0.82); a.agregar ("disco.escrito", 0.88, 0.13, 0.11); }
                al_muestrear ();
            });
            return caja3 (filas_de ({ "Reads in:", "Writes out:", "Reads in/sec:", "Writes out/sec:" },
                                    { "disco_lecturas", "disco_escrituras", "disco_lecturas_s", "disco_escrituras_s" }, { "", "", "azul", "rojo" }),
                          grafica_con_titulo ("", a, selector_disco),
                          filas_de ({ "Data read:", "Data written:", "Data read/sec:", "Data written/sec:" },
                                    { "disco_leido", "disco_escrito", "disco_leido_s", "disco_escrito_s" }, { "", "", "azul", "rojo" }));
        }

        Gtk.Widget panel_red () {
            var a = new Area (170, 52);
            a.rejilla = false;
            a.agregar ("red.paquetes_rx", 0.12, 0.12, 0.82);
            a.agregar ("red.paquetes_tx", 0.88, 0.13, 0.11);
            graficas.replace ("red", a);
            selector_red = selector ({ "PACKETS", "DATA" });
            selector_red.changed.connect (() => {
                bool paquetes = selector_red.active == 0;
                a.series.remove_range (0, a.series.length);
                if (paquetes) { a.agregar ("red.paquetes_rx", 0.12, 0.12, 0.82); a.agregar ("red.paquetes_tx", 0.88, 0.13, 0.11); }
                else { a.agregar ("red.rx", 0.12, 0.12, 0.82); a.agregar ("red.tx", 0.88, 0.13, 0.11); }
                al_muestrear ();
            });
            return caja3 (filas_de ({ "Packets in:", "Packets out:", "Packets in/sec:", "Packets out/sec:" },
                                    { "red_paquetes_recibidos", "red_paquetes_enviados", "red_paquetes_rx_s", "red_paquetes_tx_s" }, { "", "", "azul", "rojo" }),
                          grafica_con_titulo ("", a, selector_red),
                          filas_de ({ "Data received:", "Data sent:", "Data received/sec:", "Data sent/sec:" },
                                    { "red_recibido", "red_enviado", "red_rx_s", "red_tx_s" }, { "", "", "", "" }));
        }

        void poner (string clave, string texto) {
            var l = valores.lookup (clave);
            if (l != null) l.label = texto;
        }

        void aplicar_resumen (Resumen r) {
            poner ("cpu_sistema", porcentaje (r.dato ("cpu_sistema")));
            poner ("cpu_usuario", porcentaje (r.dato ("cpu_usuario")));
            poner ("cpu_ocioso", porcentaje (r.dato ("cpu_ocioso")));
            poner ("hilos", miles (r.dato ("hilos")));
            poner ("procesos", miles (r.dato ("procesos")));
            poner ("mem_fisica", bytes_texto (r.dato ("mem_fisica")));
            poner ("mem_usada", bytes_texto (r.dato ("mem_usada")));
            poner ("mem_cache", bytes_texto (r.dato ("mem_cache")));
            poner ("swap_usada", bytes_texto (r.dato ("swap_usada")));
            poner ("mem_app", bytes_texto (r.dato ("mem_app")));
            poner ("mem_wired", bytes_texto (r.dato ("mem_wired")));
            if (r.tiene ("mem_comprimida")) poner ("mem_comprimida", bytes_texto (r.dato ("mem_comprimida")));
            poner ("disco_lecturas", miles (r.dato ("disco_lecturas")));
            poner ("disco_escrituras", miles (r.dato ("disco_escrituras")));
            poner ("disco_leido", bytes_texto (r.dato ("disco_leido")));
            poner ("disco_escrito", bytes_texto (r.dato ("disco_escrito")));
            poner ("red_paquetes_recibidos", miles (r.dato ("red_paquetes_recibidos")));
            poner ("red_paquetes_enviados", miles (r.dato ("red_paquetes_enviados")));
            poner ("red_recibido", bytes_texto (r.dato ("red_recibido")));
            poner ("red_enviado", bytes_texto (r.dato ("red_enviado")));
            if (r.tiene ("bateria_carga")) poner ("bateria_carga", "%.0f%%".printf (r.dato ("bateria_carga")));
            actualizar_leyendas (r);
        }

        string[] series_visibles () {
            switch (pestana) {
            case "cpu": return { "cpu.sistema", "cpu.usuario" };
            case "memory": return { "mem.presion" };
            case "disk": return selector_disco != null && selector_disco.active == 1 ? new string[] { "disco.leido", "disco.escrito" }
                                                                                       : new string[] { "disco.lecturas", "disco.escrituras" };
            case "network": return selector_red != null && selector_red.active == 1 ? new string[] { "red.rx", "red.tx" }
                                                                                    : new string[] { "red.paquetes_rx", "red.paquetes_tx" };
            }
            return {};
        }

        async void aplicar_series () throws GLib.Error {
            string[] pedir = {};
            Area? destino = null;
            switch (pestana) {
            case "cpu": destino = graficas.lookup ("cpu_carga"); break;
            case "memory": destino = graficas.lookup ("mem_presion"); break;
            case "disk": destino = graficas.lookup ("disco"); break;
            case "network": destino = graficas.lookup ("red"); break;
            case "resources":
                yield series_recursos ();
                return;
            }
            if (destino == null) return;
            // Las cuatro series de la pestaña: la gráfica dibuja las del selector, y lo «por segundo» de los paneles sale de todas.
            pedir = pestana == "disk" ? new string[] { "disco.lecturas", "disco.escrituras", "disco.leido", "disco.escrito" }
                  : pestana == "network" ? new string[] { "red.paquetes_rx", "red.paquetes_tx", "red.rx", "red.tx" }
                  : series_visibles ();
            foreach (var s in pedir) {
                var d = yield motor.historial (s, 120);
                destino.poner (s, d);
                // lo «por segundo» de los paneles sale del último punto de la serie
                if (d.length > 0) por_segundo (s, d[d.length - 1]);
            }
        }

        void por_segundo (string serie, double v) {
            switch (serie) {
            case "disco.lecturas": poner ("disco_lecturas_s", miles (v)); break;
            case "disco.escrituras": poner ("disco_escrituras_s", miles (v)); break;
            case "disco.leido": poner ("disco_leido_s", bytes_texto (v)); break;
            case "disco.escrito": poner ("disco_escrito_s", bytes_texto (v)); break;
            case "red.paquetes_rx": poner ("red_paquetes_rx_s", miles (v)); break;
            case "red.paquetes_tx": poner ("red_paquetes_tx_s", miles (v)); break;
            case "red.rx": poner ("red_rx_s", bytes_texto (v)); break;
            case "red.tx": poner ("red_tx_s", bytes_texto (v)); break;
            }
        }

        // ---- Resources: las gráficas de GNOME System Monitor -------------------------------------------------------------

        Gtk.Box recursos_caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
        int nucleos = 0;

        Gtk.Widget pagina_recursos () {
            recursos_caja.margin = 20;
            var sw = new Gtk.ScrolledWindow (null, null);
            sw.hscrollbar_policy = Gtk.PolicyType.NEVER;
            sw.add (recursos_caja);
            return sw;
        }

        /** Se arma la primera vez que llega `nucleos` en el resumen. */
        void armar_recursos (int n) {
            nucleos = n;
            var t1 = new Gtk.Label ("CPU");
            t1.xalign = 0;
            t1.get_style_context ().add_class ("act-seccion");
            recursos_caja.pack_start (t1, false, false, 0);
            var rejilla = new Gtk.Grid ();
            rejilla.column_spacing = 12;
            rejilla.row_spacing = 12;
            rejilla.column_homogeneous = true;
            double[] cr = { 0.20, 0.45, 0.80, 0.90 };
            for (int i = 0; i < n; i++) {
                var a = new Area (200, 90);
                a.maximo = 100;
                var s = a.agregar ("cpu.%d".printf (i), 0.20, 0.45, 0.85);
                s.r = 0.17 + 0.1 * (i % 3);
                graficas.replace ("rec_cpu_%d".printf (i), a);
                var l = new Gtk.Label ("CPU%d".printf (i + 1));
                l.xalign = 0;
                l.get_style_context ().add_class ("act-leyenda");
                leyendas.replace ("rec_cpu_%d".printf (i), l);
                var celda = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
                celda.pack_start (l, false, false, 0);
                celda.pack_start (a, true, true, 0);
                rejilla.attach (celda, i % 4, i / 4, 1, 1);
            }
            recursos_caja.pack_start (rejilla, false, false, 0);

            var t2 = new Gtk.Label ("Memory and Swap");
            t2.xalign = 0;
            t2.get_style_context ().add_class ("act-seccion");
            recursos_caja.pack_start (t2, false, false, 0);
            var m = new Area (600, 110);
            m.agregar ("mem.usada", 0.20, 0.45, 0.85);
            m.agregar ("swap.usada", 0.85, 0.30, 0.20);
            graficas.replace ("rec_mem", m);
            var lm = new Gtk.Label ("");
            lm.xalign = 0;
            lm.get_style_context ().add_class ("act-leyenda");
            leyendas.replace ("rec_mem", lm);
            recursos_caja.pack_start (m, false, false, 0);
            recursos_caja.pack_start (lm, false, false, 0);

            var t3 = new Gtk.Label ("Network");
            t3.xalign = 0;
            t3.get_style_context ().add_class ("act-seccion");
            recursos_caja.pack_start (t3, false, false, 0);
            var r = new Area (600, 110);
            r.agregar ("red.rx", 0.20, 0.65, 0.30);
            r.agregar ("red.tx", 0.85, 0.30, 0.20);
            graficas.replace ("rec_red", r);
            var lr = new Gtk.Label ("");
            lr.xalign = 0;
            lr.get_style_context ().add_class ("act-leyenda");
            leyendas.replace ("rec_red", lr);
            recursos_caja.pack_start (r, false, false, 0);
            recursos_caja.pack_start (lr, false, false, 0);
            recursos_caja.show_all ();
        }

        async void series_recursos () throws GLib.Error {
            if (nucleos == 0) return;
            for (int i = 0; i < nucleos; i++) {
                var a = graficas.lookup ("rec_cpu_%d".printf (i));
                var d = yield motor.historial ("cpu.%d".printf (i), 120);
                a.poner ("cpu.%d".printf (i), d);
                var l = leyendas.lookup ("rec_cpu_%d".printf (i));
                if (d.length > 0) l.label = "CPU%d   %.0f%%".printf (i + 1, d[d.length - 1]);
            }
            var m = graficas.lookup ("rec_mem");
            m.poner ("mem.usada", yield motor.historial ("mem.usada", 120));
            m.poner ("swap.usada", yield motor.historial ("swap.usada", 120));
            var r = graficas.lookup ("rec_red");
            var rx = yield motor.historial ("red.rx", 120);
            var tx = yield motor.historial ("red.tx", 120);
            r.poner ("red.rx", rx);
            r.poner ("red.tx", tx);
            if (rx.length > 0) leyendas.lookup ("rec_red").label = "Receiving  %s/s     Sending  %s/s".printf (bytes_texto (rx[rx.length - 1]), bytes_texto (tx[tx.length - 1]));
        }

        void actualizar_leyendas (Resumen r) {
            if (nucleos == 0 && r.tiene ("nucleos")) armar_recursos ((int) r.dato ("nucleos"));
            var lm = leyendas.lookup ("rec_mem");
            if (lm != null && r.dato ("mem_fisica") > 0) {
                double fis = r.dato ("mem_fisica"), usada = r.dato ("mem_usada"), sw = r.dato ("swap_usada"), swt = r.dato ("swap_total");
                lm.label = "Memory  %s (%.0f%%) of %s     Swap  %s%s".printf (bytes_texto (usada), usada / fis * 100, bytes_texto (fis), bytes_texto (sw),
                    swt > 0 ? " (%.0f%%) of %s".printf (sw / swt * 100, bytes_texto (swt)) : "");
                var m = graficas.lookup ("rec_mem");
                if (m != null) m.maximo = fis;
            }
        }

        // ---- Quit / Force Quit ------------------------------------------------------------------------------------

        void pedir_salida () {
            Gtk.TreeModel m;
            Gtk.TreeIter it;
            if (!lista.get_selection ().get_selected (out m, out it)) return;
            Fila? f;
            m.get (it, 0, out f);
            if (f == null || f.usuario != yo) return;
            int pid = f.pid;
            // Las cadenas del nib de Catalina (CONFIRM_KILL_NAME_FMT, Quit, Force Quit, Cancel). El orden de los botones en pantalla
            // no se pudo leer del nib: queda pendiente de captura.
            var d = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE,
                                           "Do you really want to quit “%s”?", f.nombre);
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            d.add_button ("Force Quit", Gtk.ResponseType.REJECT);
            d.add_button ("Quit", Gtk.ResponseType.ACCEPT);
            d.set_default_response (Gtk.ResponseType.ACCEPT);
            d.response.connect ((r) => {
                d.destroy ();
                if (r != Gtk.ResponseType.ACCEPT && r != Gtk.ResponseType.REJECT) return;
                motor.salir.begin (pid, r == Gtk.ResponseType.REJECT, (o, res) => {
                    try { motor.salir.end (res); } catch (GLib.Error e) { warning ("%s", e.message); }
                });
            });
            d.show ();
        }
    }
}
