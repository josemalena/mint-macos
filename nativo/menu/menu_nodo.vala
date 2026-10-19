/*
 * Un ítem de menú ya aplanado: lo que el servicio devuelve por D-Bus, más lo que hace falta para ejecutarlo. Las fuentes
 * (GTK y dbusmenu) llenan los campos que les tocan; el servicio no sabe de cuál viene.
 */
namespace Menu {
    public class Nodo : Object {
        public string id = "";
        public string tipo = "item";           // item | separador | submenu
        public string etiqueta = "";
        public bool activo = true;
        public string marca = "";              // "" | check | radio
        public bool marcado = false;
        public string atajo = "";
        public string icono = "";
        public string? color_etiqueta = null;  // x-constanza-tag-color: el hex del color de una etiqueta del Finder («» = sin color); null si no es una
        public bool alterno = false;           // x-constanza-alternate: solo se ve con ⌥, en lugar del ítem anterior
        public bool es_menu_app = false;       // x-constanza-app-menu: lo pinta appmenu, no la barra
        public string ruta = "";               // solo en Buscar: «Edit ▸ Find ▸ Find…»
        public GenericArray<Nodo>? hijos = null;

        // GTK
        public MenuModel? submodelo = null;
        public ActionGroup? grupo = null;
        public string accion = "";
        public Variant? objetivo = null;
        public bool booleano = false;          // acción con estado booleano y sin objetivo: se invierte

        public static Nodo separador () {
            var n = new Nodo ();
            n.tipo = "separador";
            return n;
        }

        /** Los campos que se mandan por D-Bus; las claves sin dato no se ponen. */
        public void a_dict (VariantDict d) {
            d.insert_value ("id", new Variant.string (id));
            d.insert_value ("tipo", new Variant.string (tipo));
            if (tipo == "separador") return;
            d.insert_value ("etiqueta", new Variant.string (etiqueta));
            d.insert_value ("activo", new Variant.boolean (activo));
            if (marca != "") {
                d.insert_value ("marca", new Variant.string (marca));
                d.insert_value ("marcado", new Variant.boolean (marcado));
            }
            if (atajo != "") d.insert_value ("atajo", new Variant.string (atajo));
            if (alterno) d.insert_value ("alterno", new Variant.boolean (true));
            if (color_etiqueta != null) d.insert_value ("etiqueta_color", new Variant.string (color_etiqueta));
            if (icono != "") d.insert_value ("icono", new Variant.string (icono));
            if (hijos != null) d.insert_value ("hijos", lista_variant (hijos));
            if (ruta != "") d.insert_value ("ruta", new Variant.string (ruta));
        }

        public Variant a_variant () {
            var d = new VariantDict ();
            a_dict (d);
            return d.end ();
        }

        public HashTable<string, Variant> a_tabla () {
            var t = new HashTable<string, Variant> (str_hash, str_equal);
            var v = a_variant ();
            var it = v.iterator ();
            string k;
            Variant val;
            while (it.next ("{sv}", out k, out val)) t.insert (k, val);
            return t;
        }

        public static Variant lista_variant (GenericArray<Nodo> lista) {
            var b = new VariantBuilder (new VariantType ("aa{sv}"));
            for (int i = 0; i < lista.length; i++) b.add_value (lista[i].a_variant ());
            return b.end ();
        }

        public static HashTable<string, Variant>[] a_tablas (GenericArray<Nodo> lista) {
            HashTable<string, Variant>[] r = {};
            for (int i = 0; i < lista.length; i++) r += lista[i].a_tabla ();
            return r;
        }
    }

    /** «_Archivo» → «Archivo»; «__» queda como un «_». */
    public string limpiar_etiqueta (string s) {
        return s.replace ("__", "\x01").replace ("_", "").replace ("\x01", "_");
    }

    /** Quita separadores al principio, al final y repetidos (las apps los dejan donde escondieron ítems). */
    public void limpiar_separadores (GenericArray<Nodo> lista) {
        var fuera = new GenericArray<Nodo> ();
        for (int i = 0; i < lista.length; i++) {
            var n = lista[i];
            if (n.tipo == "separador" && (fuera.length == 0 || fuera[fuera.length - 1].tipo == "separador")) continue;
            fuera.add (n);
        }
        while (fuera.length > 0 && fuera[fuera.length - 1].tipo == "separador") fuera.remove_index (fuera.length - 1);
        lista.remove_range (0, lista.length);
        for (int i = 0; i < fuera.length; i++) {
            lista.add (fuera[i]);
            if (fuera[i].hijos != null) limpiar_separadores (fuera[i].hijos);
        }
    }
}
