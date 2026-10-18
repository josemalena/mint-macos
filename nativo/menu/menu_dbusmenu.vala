/*
 * El menú de las apps que no son GTK nativo (Firefox, Thunderbird, Chrome, Edge, Electron, LibreOffice, Qt): publican
 * com.canonical.dbusmenu y se anotan en com.canonical.AppMenu.Registrar (ventana → servicio y ruta). Se habla directo por
 * GDBus; el árbol llega como (ia{sv}av) y se convierte a Nodo. Chrome, Firefox y Electron arman el menú en AboutToShow:
 * se pide antes de abrir, con un tope de 150 ms; lo que llegue después sale por `cambio`. Los ids son «d» + el id del ítem.
 */
namespace Menu {
    class ItemD {
        public int id = 0;
        public HashTable<string, Variant> props = new HashTable<string, Variant> (str_hash, str_equal);
        public GenericArray<ItemD> hijos = new GenericArray<ItemD> ();

        public string texto (string k) {
            var v = props.lookup (k);
            return v != null && v.is_of_type (VariantType.STRING) ? v.get_string () : "";
        }

        public bool bandera (string k, bool defecto) {
            var v = props.lookup (k);
            return v != null && v.is_of_type (VariantType.BOOLEAN) ? v.get_boolean () : defecto;
        }

        public bool es_separador () { return texto ("type") == "separator"; }
        public bool visible () { return bandera ("visible", true); }
        public bool tiene_submenu () { return texto ("children-display") == "submenu" || hijos.length > 0; }

        /** (ia{sv}av) → ItemD. */
        public static ItemD desde (Variant v) {
            var it = new ItemD ();
            it.id = v.get_child_value (0).get_int32 ();
            var dic = v.get_child_value (1);
            for (size_t i = 0; i < dic.n_children (); i++) {
                var par = dic.get_child_value (i);
                it.props.insert (par.get_child_value (0).get_string (), par.get_child_value (1).get_variant ());
            }
            var av = v.get_child_value (2);
            for (size_t i = 0; i < av.n_children (); i++) it.hijos.add (ItemD.desde (av.get_child_value (i).get_variant ()));
            return it;
        }
    }

    public class FuenteDbusmenu : Fuente {
        const string IFAZ = "com.canonical.dbusmenu";
        const string[] PROPS = { "type", "label", "enabled", "visible", "toggle-type", "toggle-state", "shortcut", "children-display" };
        DBusConnection con;
        string servicio;
        string ruta;
        uint[] suscripciones = {};
        uint aviso = 0;
        bool abriendo = false;
        string abierto = "";

        public FuenteDbusmenu (DBusConnection con, string servicio, string ruta) {
            this.con = con;
            this.servicio = servicio;
            this.ruta = ruta;
            foreach (var nombre in new string[] { "LayoutUpdated", "ItemsPropertiesUpdated" }) {
                suscripciones += con.signal_subscribe (servicio, IFAZ, nombre, ruta, null, DBusSignalFlags.NONE, al_senal);
            }
        }

        ~FuenteDbusmenu () {
            foreach (var s in suscripciones) con.signal_unsubscribe (s);
            if (aviso != 0) Source.remove (aviso);
        }

        public override string nombre_fuente () { return "dbusmenu"; }

        void al_senal () {
            if (abriendo) return;       // AboutToShow dispara LayoutUpdated
            if (aviso != 0) Source.remove (aviso);
            aviso = Timeout.add (150, () => { aviso = 0; cambio (abierto); return false; });
        }

        async ItemD arbol (int padre, int ms = 3000) throws GLib.Error {
            var r = yield con.call (servicio, ruta, IFAZ, "GetLayout",
                new Variant.tuple ({ new Variant.int32 (padre), new Variant.int32 (-1), new Variant.strv (PROPS) }),
                new VariantType ("(u(ia{sv}av))"), DBusCallFlags.NONE, ms, null);
            return ItemD.desde (r.get_child_value (1));
        }

        async bool antes_de_abrir (int id, int ms) {
            try {
                var r = yield con.call (servicio, ruta, IFAZ, "AboutToShow", new Variant.tuple ({ new Variant.int32 (id) }),
                    new VariantType ("(b)"), DBusCallFlags.NONE, ms, null);
                return r.get_child_value (0).get_boolean ();
            } catch (GLib.Error e) {
                return false;       // no todas lo implementan
            }
        }

        void evento (int id, string nombre) {
            uint hora = (uint) (get_monotonic_time () / 1000);
            con.call.begin (servicio, ruta, IFAZ, "Event",
                new Variant.tuple ({ new Variant.int32 (id), new Variant.string (nombre),
                                     new Variant.variant (new Variant.int32 (0)), new Variant.uint32 (hora) }),
                null, DBusCallFlags.NONE, 3000, null);
        }

        static int id_de (string id) {
            return id.has_prefix ("d") ? int.parse (id.substring (1)) : -1;
        }

        Nodo a_nodo (ItemD it) {
            if (it.es_separador ()) return Nodo.separador ();
            var n = new Nodo ();
            n.id = "d%d".printf (it.id);
            n.etiqueta = limpiar_etiqueta (it.texto ("label"));
            n.activo = it.bandera ("enabled", true);
            var tipo = it.texto ("toggle-type");
            if (tipo == "checkmark" || tipo == "radio") {
                n.marca = tipo == "checkmark" ? "check" : "radio";
                var st = it.props.lookup ("toggle-state");
                n.marcado = st != null && st.is_of_type (VariantType.INT32) && st.get_int32 () == 1;
            }
            n.atajo = Atajos.de_dbusmenu (it.props.lookup ("shortcut"), clase);
            if (it.tiene_submenu ()) {
                n.tipo = "submenu";
                n.hijos = new GenericArray<Nodo> ();
                for (int i = 0; i < it.hijos.length; i++) {
                    if (!it.hijos[i].visible ()) continue;
                    var h = it.hijos[i];
                    // Thunderbird deja ítems sin etiqueta (los que esconde por contexto).
                    if (!h.es_separador () && h.texto ("label") == "" && !h.tiene_submenu ()) continue;
                    n.hijos.add (a_nodo (h));
                }
            }
            return n;
        }

        public override async GenericArray<Nodo> barra (int espera_ms) throws GLib.Error {
            var res = new GenericArray<Nodo> ();
            ItemD raiz;
            try {
                raiz = yield arbol (0);
            } catch (GLib.Error e) {
                return res;
            }
            for (int i = 0; i < raiz.hijos.length; i++) {
                var h = raiz.hijos[i];
                if (!h.visible () || h.es_separador () || limpiar_etiqueta (h.texto ("label")) == "") continue;
                var n = new Nodo ();
                n.id = "d%d".printf (h.id);
                n.tipo = "submenu";
                n.etiqueta = limpiar_etiqueta (h.texto ("label"));
                n.activo = h.bandera ("enabled", true);
                res.add (n);
            }
            return res;
        }

        public override async GenericArray<Nodo> abrir (string id, int espera_ms) throws GLib.Error {
            int num = id_de (id);
            if (num < 0) throw new Error.SIN_MENU ("no hay menú «%s»", id);
            abriendo = true;
            abierto = id;
            ItemD? sub = null;
            try {
                // Chrome, Firefox y Electron llenan el menú en AboutToShow.
                yield antes_de_abrir (num, espera_ms);
                evento (num, "opened");
                sub = yield arbol (num);
                // los submenús de segundo nivel que lleguen vacíos se piden también
                for (int i = 0; i < sub.hijos.length; i++) {
                    var h = sub.hijos[i];
                    if (h.tiene_submenu () && h.hijos.length == 0 && (yield antes_de_abrir (h.id, espera_ms))) {
                        var s2 = yield arbol (h.id);
                        h.hijos = s2.hijos;
                    }
                }
            } catch (GLib.Error e) {
                throw new Error.SIN_MENU ("%s", e.message);
            } finally {
                abriendo = false;
            }
            if (sub == null) throw new Error.SIN_MENU ("sin menú");
            var res = new GenericArray<Nodo> ();
            for (int i = 0; i < sub.hijos.length; i++) {
                var h = sub.hijos[i];
                if (!h.visible ()) continue;
                if (!h.es_separador () && h.texto ("label") == "" && !h.tiene_submenu ()) continue;
                res.add (a_nodo (h));
            }
            limpiar_separadores (res);
            return res;
        }

        public override void cerrar (string id) {
            int num = id_de (id);
            if (num >= 0) evento (num, "closed");
            if (abierto == id) abierto = "";
        }

        public override bool activar (string id) throws GLib.Error {
            int num = id_de (id);
            if (num < 0) return false;
            evento (num, "clicked");
            return true;
        }

        public override async GenericArray<Nodo> menu_app () throws GLib.Error {
            return new GenericArray<Nodo> ();
        }
    }
}
