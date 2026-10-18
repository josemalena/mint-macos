/*
 * La cara de Vala del motor del App Store (org.mintmacos.Tienda1, rust/tienda/DBUS.md). Aquí no se decide nada de
 * dónde sale una app: el motor da resúmenes, fichas y trabajos; esto los convierte en objetos y reenvía las señales.
 * Las claves que el motor no trae quedan vacías; nunca se rellenan con un valor inventado.
 */
namespace Tienda {
    public class Resumen : Object {
        public string id = "";
        public string appstream_id = "";
        public string nombre = "";
        public string resumen = "";
        public string icono = "";
        public string icono_tema = "";
        public string origen = "";
        public string desarrollador = "";
        public string version = "";
        public string version_instalada = "";
        public bool instalada = false;
        public bool actualizable = false;
        public bool verificada = false;

        public static string texto (Variant d, string clave) {
            var v = d.lookup_value (clave, VariantType.STRING);
            return v != null ? v.get_string () : "";
        }

        public static bool booleano (Variant d, string clave) {
            var v = d.lookup_value (clave, VariantType.BOOLEAN);
            return v != null && v.get_boolean ();
        }

        public static Resumen desde (Variant d) {
            var r = new Resumen ();
            r.id = texto (d, "id");
            r.appstream_id = texto (d, "appstream_id");
            r.nombre = texto (d, "nombre");
            r.resumen = texto (d, "resumen");
            r.icono = texto (d, "icono");
            r.icono_tema = texto (d, "icono_tema");
            r.origen = texto (d, "origen");
            r.desarrollador = texto (d, "desarrollador");
            r.version = texto (d, "version");
            r.version_instalada = texto (d, "version_instalada");
            r.instalada = booleano (d, "instalada");
            r.actualizable = booleano (d, "actualizable");
            r.verificada = booleano (d, "verificada");
            return r;
        }
    }

    public class Estante : Object {
        public string id = "";
        public string titulo = "";
        public string tipo = "";      // destacada | fila | lista-numerada
        public string fuente = "";
        public GenericArray<Resumen> apps = new GenericArray<Resumen> ();
    }

    /** (id, título, categorías de AppStream): una sección o una categoría. */
    public class Grupo : Object {
        public string id = "";
        public string titulo = "";
        public string[] categorias = {};
    }

    public class Motor : Object {
        const string NOMBRE = "org.mintmacos.Tienda1";
        const string RUTA = "/org/mintmacos/Tienda1";
        static Motor? _instancia = null;

        public static Motor instancia {
            get {
                if (_instancia == null) _instancia = new Motor ();
                return _instancia;
            }
        }

        DBusConnection? con = null;
        public HashTable<string, string> trabajo_a_id = new HashTable<string, string> (str_hash, str_equal);
        public HashTable<string, string> id_a_trabajo = new HashTable<string, string> (str_hash, str_equal);
        public HashTable<string, string> trabajo_a_tipo = new HashTable<string, string> (str_hash, str_equal);
        public HashTable<string, uint> trabajo_a_pct = new HashTable<string, uint> (str_hash, str_equal);

        public signal void progreso (string trabajo, uint pct, string etapa);
        public signal void terminado (string trabajo, string id, string tipo, bool ok, string codigo, string mensaje);
        public signal void instaladas_cambiaron (string[] ids);
        public signal void actualizaciones_cambiaron ();
        public signal void icono_listo (string url, string ruta);
        public signal void abrir_ficha (string id);

        public bool conectar (out string error) {
            error = "";
            if (con != null) return true;
            try {
                con = Bus.get_sync (BusType.SESSION);
                con.signal_subscribe (NOMBRE, NOMBRE, null, RUTA, null, DBusSignalFlags.NONE, al_llegar_senal);
            } catch (Error e) {
                error = e.message;
                return false;
            }
            return true;
        }

        void al_llegar_senal (DBusConnection c, string? remitente, string ruta, string iface, string senal, Variant p) {
            switch (senal) {
            case "Progreso": {
                var trabajo = p.get_child_value (0).get_string ();
                uint pct = p.get_child_value (1).get_uint32 ();
                var etapa = p.get_child_value (2).get_string ();
                trabajo_a_pct.replace (trabajo, pct);
                progreso (trabajo, pct, etapa);
                break;
            }
            case "Terminado": {
                var trabajo = p.get_child_value (0).get_string ();
                bool ok = p.get_child_value (1).get_boolean ();
                var codigo = p.get_child_value (2).get_string ();
                var mensaje = p.get_child_value (3).get_string ();
                var id = trabajo_a_id.lookup (trabajo) ?? "";
                var tipo = trabajo_a_tipo.lookup (trabajo) ?? "";
                olvidar (trabajo);
                terminado (trabajo, id, tipo, ok, codigo, mensaje);
                break;
            }
            case "InstaladasCambiaron":
                instaladas_cambiaron (p.get_child_value (0).dup_strv ());
                break;
            case "ActualizacionesCambiaron":
                actualizaciones_cambiaron ();
                break;
            case "IconoListo":
                icono_listo (p.get_child_value (0).get_string (), p.get_child_value (1).get_string ());
                break;
            }
        }

        void olvidar (string trabajo) {
            var id = trabajo_a_id.lookup (trabajo);
            if (id != null) id_a_trabajo.remove (id);
            trabajo_a_id.remove (trabajo);
            trabajo_a_tipo.remove (trabajo);
            trabajo_a_pct.remove (trabajo);
        }

        public async Variant llamar (string metodo, Variant? args = null) throws Error {
            if (con == null) {
                string e;
                if (!conectar (out e)) throw new IOError.FAILED ("%s", e);
            }
            return yield con.call (NOMBRE, RUTA, NOMBRE, metodo, args, null, DBusCallFlags.NONE, 180000, null);
        }

        static Variant uno (string s) {
            return new Variant.tuple ({ new Variant.string (s) });
        }

        public async GenericArray<Resumen> buscar (string texto, uint limite = 60) throws Error {
            var r = yield llamar ("Buscar", new Variant.tuple ({ new Variant.string (texto),
                new Variant.strv (new string[0]), new Variant.uint32 (limite) }));
            return resumenes (r.get_child_value (0));
        }

        public async GenericArray<Resumen> listar_categoria (string categoria, uint desde, uint limite) throws Error {
            var r = yield llamar ("ListarCategoria", new Variant.tuple ({ new Variant.string (categoria),
                new Variant.uint32 (desde), new Variant.uint32 (limite) }));
            return resumenes (r.get_child_value (0));
        }

        public async GenericArray<Resumen> actualizaciones (string grupo) throws Error {
            var r = yield llamar ("Actualizaciones", uno (grupo));
            return resumenes (r.get_child_value (0));
        }

        public async GenericArray<Grupo> grupos (string metodo) throws Error {
            var r = yield llamar (metodo);
            var lista = new GenericArray<Grupo> ();
            var arr = r.get_child_value (0);
            for (size_t i = 0; i < arr.n_children (); i++) {
                var t = arr.get_child_value (i);
                var g = new Grupo ();
                g.id = t.get_child_value (0).get_string ();
                g.titulo = t.get_child_value (1).get_string ();
                g.categorias = t.get_child_value (2).dup_strv ();
                lista.add (g);
            }
            return lista;
        }

        public async GenericArray<Estante> estantes (string seccion) throws Error {
            var r = yield llamar ("Estantes", uno (seccion));
            var lista = new GenericArray<Estante> ();
            var arr = r.get_child_value (0);
            for (size_t i = 0; i < arr.n_children (); i++) {
                var t = arr.get_child_value (i);
                var e = new Estante ();
                e.id = t.get_child_value (0).get_string ();
                e.titulo = t.get_child_value (1).get_string ();
                e.tipo = t.get_child_value (2).get_string ();
                e.fuente = t.get_child_value (3).get_string ();
                e.apps = resumenes (t.get_child_value (4));
                if (e.apps.length > 0) lista.add (e);
            }
            return lista;
        }

        public async Variant ficha (string id) throws Error {
            var r = yield llamar ("Ficha", uno (id));
            return r.get_child_value (0);
        }

        public async GenericArray<Variant> resenas (string appstream_id, uint limite) throws Error {
            var r = yield llamar ("Resenas", new Variant.tuple ({ new Variant.string (appstream_id),
                new Variant.uint32 (limite) }));
            var lista = new GenericArray<Variant> ();
            var arr = r.get_child_value (0);
            for (size_t i = 0; i < arr.n_children (); i++) lista.add (arr.get_child_value (i));
            return lista;
        }

        /** Empieza un trabajo (Instalar, Quitar, Actualizar) y lo anota para que los botones se reenganchen. */
        async string empezar (string metodo, Variant args, string id, string tipo) throws Error {
            var r = yield llamar (metodo, args);
            var trabajo = r.get_child_value (0).get_string ();
            trabajo_a_id.replace (trabajo, id);
            trabajo_a_tipo.replace (trabajo, tipo);
            trabajo_a_pct.replace (trabajo, 101);
            if (id != "") id_a_trabajo.replace (id, trabajo);
            progreso (trabajo, 101, "esperando");
            return trabajo;
        }

        public async string instalar (string id) throws Error {
            return yield empezar ("Instalar", uno (id), id, "instalar");
        }

        public async string quitar (string id) throws Error {
            return yield empezar ("Quitar", uno (id), id, "quitar");
        }

        /** Un solo id, o todos los del grupo si `ids` viene vacío (id = "" en ese caso). */
        public async string actualizar (string grupo, string[] ids) throws Error {
            var id = ids.length == 1 ? ids[0] : "";
            return yield empezar ("Actualizar", new Variant.tuple ({ new Variant.string (grupo),
                new Variant.strv (ids) }), id, "actualizar");
        }

        public async bool cancelar (string trabajo) throws Error {
            var r = yield llamar ("Cancelar", uno (trabajo));
            return r.get_child_value (0).get_boolean ();
        }

        static GenericArray<Resumen> resumenes (Variant arr) {
            var lista = new GenericArray<Resumen> ();
            for (size_t i = 0; i < arr.n_children (); i++) lista.add (Resumen.desde (arr.get_child_value (i)));
            return lista;
        }
    }
}
