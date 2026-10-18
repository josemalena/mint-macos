/*
 * org.mintmacos.Menu1 (nativo/menu/DBUS.md): el menú de la app al frente, ya aplanado, para el applet de la barra y para
 * quien lo pida (el Help de la Mac, Spotlyte). Por ventana (xid) elige la fuente: GTK (GMenuModel) y, si no da ningún menú,
 * dbusmenu por el registrador. Nada de esto bloquea el main loop: las esperas son asíncronas.
 */
namespace Menu {
    class PropsX {
        public string? bus = null;
        public string? ruta_menu = null;
        public string? ruta_app = null;
        public string? ruta_ventana = null;
        public string clase = "";

        static string? texto (Gdk.Window w, string nombre, string tipo) {
            Gdk.Atom actual;
            int formato;
            uint8[] datos;
            if (!Gdk.property_get (w, Gdk.Atom.intern (nombre, false), Gdk.Atom.intern (tipo, false), 0, 4096, 0,
                                   out actual, out formato, out datos) || datos.length == 0) return null;
            var sb = new StringBuilder ();
            foreach (var b in datos) sb.append_c ((char) b);
            return sb.str;
        }

        public static PropsX leer (uint xid) {
            var p = new PropsX ();
            var disp = Gdk.Display.get_default () as Gdk.X11.Display;
            if (disp == null) return p;
            disp.error_trap_push ();
            var w = new Gdk.X11.Window.foreign_for_display (disp, (X.Window) xid);
            if (w != null) {
                p.bus = texto (w, "_GTK_UNIQUE_BUS_NAME", "UTF8_STRING");
                p.ruta_menu = texto (w, "_GTK_MENUBAR_OBJECT_PATH", "UTF8_STRING");
                p.ruta_app = texto (w, "_GTK_APPLICATION_OBJECT_PATH", "UTF8_STRING");
                p.ruta_ventana = texto (w, "_GTK_WINDOW_OBJECT_PATH", "UTF8_STRING");
                // WM_CLASS: «instancia\0clase\0»; keyd usa la clase en minúsculas.
                Gdk.Atom actual;
                int formato;
                uint8[] datos;
                if (Gdk.property_get (w, Gdk.Atom.intern ("WM_CLASS", false), Gdk.Atom.intern ("STRING", false), 0, 512, 0,
                                      out actual, out formato, out datos) && datos.length > 0) {
                    var partes = new GenericArray<string> ();
                    var sb = new StringBuilder ();
                    foreach (var b in datos) {
                        if (b == 0) { partes.add (sb.str); sb = new StringBuilder (); } else sb.append_c ((char) b);
                    }
                    if (sb.len > 0) partes.add (sb.str);
                    if (partes.length > 1) p.clase = partes[1].down ();
                    else if (partes.length > 0) p.clase = partes[0].down ();
                }
            }
            disp.error_trap_pop_ignored ();
            return p;
        }
    }

    class Ventana : Object {
        public uint xid;
        public Fuente? fuente = null;
        public uint version = 1;
        public PropsX props;
        public bool dbusmenu_probado = false;
        public HashTable<string, int> aperturas = new HashTable<string, int> (str_hash, str_equal);   // «id|remitente» → cuenta
        public int64 ultimo_uso = 0;
        public ulong enganche = 0;
    }

    [DBus (name = "org.mintmacos.Menu1")]
    public class Servicio : Object {
        const string REGISTRADOR = "com.canonical.AppMenu.Registrar";
        const string RUTA_REGISTRADOR = "/com/canonical/AppMenu/Registrar";
        const int ESPERA_BARRA = 400;
        const int ESPERA_DBUSMENU = 150;
        const int64 CADUCA_US = 120 * 1000000;

        DBusConnection? con = null;
        HashTable<uint, Ventana> ventanas = new HashTable<uint, Ventana> (direct_hash, direct_equal);
        HashTable<string, uint> vigilados = new HashTable<string, uint> (str_hash, str_equal);
        uint limpieza = 0;

        public signal void barra_cambio (uint xid);
        public signal void arbol_cambio (uint xid, string id);

        [DBus (visible = false)]
        public void registrar (DBusConnection c) {
            con = c;
            // Varias apps se anotan en el registrador segundos después de abrir la ventana (Firefox, Thunderbird): si alguien
            // ya preguntó por esa ventana, se vuelve a probar y se avisa de que la barra cambió.
            foreach (var nombre in new string[] { "WindowRegistered", "WindowUnregistered" }) {
                c.signal_subscribe (null, REGISTRADOR, nombre, RUTA_REGISTRADOR, null, DBusSignalFlags.NONE,
                    (cc, rem, ruta, ifaz, sen, p) => {
                        uint xid = p.get_child_value (0).get_uint32 ();
                        var v = ventanas.lookup (xid);
                        if (v == null) return;
                        if (v.fuente != null && v.fuente.nombre_fuente () == "dbusmenu") v.fuente = null;
                        if (v.fuente == null || v.fuente.nombre_fuente () == "dbusmenu") v.dbusmenu_probado = false;
                        v.version++;
                        barra_cambio (xid);
                    });
            }
            limpieza = Timeout.add_seconds (30, () => {
                int64 ahora = get_monotonic_time ();
                var fuera = new GenericArray<uint> ();
                ventanas.foreach ((xid, v) => { if (ahora - v.ultimo_uso > CADUCA_US) fuera.add (xid); });
                for (int i = 0; i < fuera.length; i++) ventanas.remove (fuera[i]);
                return true;
            });
        }

        /** La ventana y su fuente. GTK si publica _GTK_MENUBAR_OBJECT_PATH; si no, dbusmenu por el registrador. */
        async Ventana? obtener (uint xid) {
            var v = ventanas.lookup (xid);
            if (v == null) {
                v = new Ventana ();
                v.xid = xid;
                v.props = PropsX.leer (xid);
                ventanas.insert (xid, v);
            }
            v.ultimo_uso = get_monotonic_time ();
            if (v.fuente == null) {
                if (v.props.bus != null && v.props.ruta_menu != null) {
                    var f = new FuenteGtk (con, v.props.bus, v.props.ruta_menu, v.props.ruta_app, v.props.ruta_ventana);
                    f.clase = v.props.clase;
                    poner_fuente (v, f);
                } else {
                    yield probar_dbusmenu (v);
                }
            }
            return v.fuente != null ? v : null;
        }

        void poner_fuente (Ventana v, Fuente f) {
            if (v.fuente != null && v.enganche != 0) v.fuente.disconnect (v.enganche);
            v.fuente = f;
            uint xid = v.xid;
            v.enganche = f.cambio.connect ((id) => {
                var vv = ventanas.lookup (xid);
                if (vv == null) return;
                vv.version++;
                if (id == "") barra_cambio (xid); else arbol_cambio (xid, id);
            });
        }

        async bool probar_dbusmenu (Ventana v) {
            v.dbusmenu_probado = true;
            try {
                var r = yield con.call (REGISTRADOR, RUTA_REGISTRADOR, REGISTRADOR, "GetMenuForWindow",
                    new Variant.tuple ({ new Variant.uint32 (v.xid) }), new VariantType ("(so)"), DBusCallFlags.NONE, 3000, null);
                var servicio = r.get_child_value (0).get_string ();
                var ruta = r.get_child_value (1).get_string ();
                if (servicio == "" || ruta == "" || ruta == "/") return false;
                var f = new FuenteDbusmenu (con, servicio, ruta);
                f.clase = v.props.clase;
                poner_fuente (v, f);
                return true;
            } catch (GLib.Error e) {
                return false;       // la ventana no publica menú
            }
        }

        // ---- la interfaz -------------------------------------------------------------------------------------------

        public async string fuente (uint xid) throws GLib.Error {
            var v = yield obtener (xid);
            return v != null ? v.fuente.nombre_fuente () : "ninguna";
        }

        public async void barra (uint xid, out uint version, out HashTable<string, Variant>[] items) throws GLib.Error {
            var v = yield obtener (xid);
            if (v == null) {
                version = 0;
                items = {};
                return;
            }
            GenericArray<Nodo> lista;
            try {
                lista = yield v.fuente.barra (ESPERA_BARRA);
            } catch (GLib.Error e) {
                lista = new GenericArray<Nodo> ();
            }
            // Si GTK no dio ningún menú (el módulo anota CADA ventana GTK, también las que publican por dbusmenu), se prueba dbusmenu.
            if (lista.length == 0 && v.fuente.nombre_fuente () == "gtk" && !v.dbusmenu_probado) {
                if (yield probar_dbusmenu (v)) {
                    try { lista = yield v.fuente.barra (ESPERA_BARRA); } catch (GLib.Error e) { }
                }
            }
            version = v.version;
            items = Nodo.a_tablas (lista);
        }

        public async void abrir (uint xid, string id, BusName remitente, out uint version, out HashTable<string, Variant>[] items) throws GLib.Error {
            var v = yield obtener (xid);
            if (v == null) throw new Menu.Error.SIN_MENU ("la ventana %u no publica menú", xid);
            vigilar (remitente);
            var clave = "%s|%s".printf (id, (string) remitente);
            v.aperturas.replace (clave, (v.aperturas.lookup (clave)) + 1);
            GenericArray<Nodo> lista;
            try {
                lista = yield v.fuente.abrir (id, ESPERA_DBUSMENU);
            } catch (GLib.Error e) {
                throw new Menu.Error.SIN_MENU ("%s", e.message);
            }
            version = v.version;
            items = Nodo.a_tablas (lista);
        }

        public async void cerrar (uint xid, string id, BusName remitente) throws GLib.Error {
            var v = ventanas.lookup (xid);
            if (v == null) throw new Menu.Error.SIN_MENU ("la ventana %u no publica menú", xid);
            soltar (v, id, (string) remitente);
        }

        /** Resta una apertura de ese remitente; el «closed» de dbusmenu sale solo cuando cierra el último. */
        void soltar (Ventana v, string id, string remitente) {
            var clave = "%s|%s".printf (id, remitente);
            int n = v.aperturas.lookup (clave);
            if (n > 1) {
                v.aperturas.replace (clave, n - 1);
            } else {
                v.aperturas.remove (clave);
            }
            int quedan = 0;
            var pref = id + "|";
            v.aperturas.foreach ((k, c) => { if (k.has_prefix (pref)) quedan += c; });
            if (quedan == 0 && v.fuente != null) v.fuente.cerrar (id);
        }

        void vigilar (string remitente) {
            if (vigilados.contains (remitente) || con == null) return;
            uint w = Bus.watch_name_on_connection (con, remitente, BusNameWatcherFlags.NONE, null, (c, n) => {
                // el cliente se fue del bus: cuenta como que cerró lo suyo
                var sufijo = "|" + n;
                ventanas.foreach ((xid, v) => {
                    var claves = new GenericArray<string> ();
                    v.aperturas.foreach ((k, c2) => { if (k.has_suffix (sufijo)) claves.add (k); });
                    for (int i = 0; i < claves.length; i++) {
                        var id = claves[i].substring (0, claves[i].length - sufijo.length);
                        int cuenta = v.aperturas.lookup (claves[i]);
                        for (int j = 0; j < cuenta; j++) soltar (v, id, n);
                    }
                });
                var h = vigilados.lookup (n);
                vigilados.remove (n);
                Bus.unwatch_name (h);
            });
            vigilados.insert (remitente, w);
        }

        public async bool activar (uint xid, uint version, string id) throws GLib.Error {
            var v = ventanas.lookup (xid);
            if (v == null || v.fuente == null) throw new Menu.Error.SIN_MENU ("la ventana %u no publica menú", xid);
            if (version != v.version) throw new Menu.Error.VENCIDO ("el menú cambió (versión %u, ahora %u)", version, v.version);
            v.ultimo_uso = get_monotonic_time ();
            return v.fuente.activar (id);
        }

        public async HashTable<string, Variant>[] menu_app (uint xid) throws GLib.Error {
            var v = yield obtener (xid);
            if (v == null) throw new Menu.Error.SIN_MENU ("la ventana %u no publica menú", xid);
            try {
                return Nodo.a_tablas (yield v.fuente.menu_app ());
            } catch (GLib.Error e) {
                throw new Menu.Error.SIN_MENU ("%s", e.message);
            }
        }

        public async HashTable<string, Variant>[] buscar (uint xid, string texto) throws GLib.Error {
            var v = yield obtener (xid);
            if (v == null) throw new Menu.Error.SIN_MENU ("la ventana %u no publica menú", xid);
            var todos = yield v.fuente.todo (ESPERA_DBUSMENU);
            var q = texto.down ();
            var res = new GenericArray<Nodo> ();
            for (int i = 0; i < todos.length; i++) {
                if (todos[i].etiqueta.down ().contains (q)) res.add (todos[i]);
            }
            var tablas = Nodo.a_tablas (res);
            foreach (var t in tablas) t.insert ("version", new Variant.uint32 (v.version));
            return tablas;
        }
    }

    public delegate void Aviso ();

    /** Quien lo hospeda (mac-menu suelto o mac-ventanas --residente) lo arranca con esto. */
    public class Anfitrion : Object {
        static Servicio? servicio = null;

        /** Pide el nombre en el bus de sesión y exporta el objeto. `si_falla` se llama si el nombre ya lo tiene otro. */
        public static void iniciar (owned Aviso? si_falla = null) {
            if (servicio != null) return;
            servicio = new Servicio ();
            Bus.own_name (BusType.SESSION, "org.mintmacos.Menu1", BusNameOwnerFlags.NONE,
                (con) => {
                    try {
                        con.register_object ("/org/mintmacos/Menu1", servicio);
                        servicio.registrar (con);
                    } catch (IOError e) {
                        warning ("org.mintmacos.Menu1: %s", e.message);
                    }
                },
                null,
                () => {
                    warning ("org.mintmacos.Menu1 ya existe");
                    if (si_falla != null) si_falla ();
                });
        }
    }
}
