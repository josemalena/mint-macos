/* La versión de macOS escogida y su perfil (perfiles/ESQUEMA.md), para las piezas nativas.
 * Lo mismo que perfiles/macos_version.py: la versión activa se lee una vez (el cambio vale al
 * volver a entrar) y cada ítem se pide por su id estable.
 *
 *   var it = PerfilMacos.item ("menu-apple", "menu-apple", "sysp");
 *   if (it != null) etiqueta = it.get_string_member ("texto");   // «System Settings…» en Sequoia
 *
 * Compila con: --pkg json-glib-1.0 --pkg gio-2.0
 */
namespace PerfilMacos {
    const string POR_DEFECTO = "catalina-10.15";
    string? _activa = null;
    HashTable<string, Json.Object>? _perfiles = null;

    Json.Object? leer (string ruta) {
        try {
            var p = new Json.Parser ();
            p.load_from_file (ruta);
            var r = p.get_root ();
            return r != null && r.get_node_type () == Json.NodeType.OBJECT ? r.get_object () : null;
        } catch (Error e) {
            return null;
        }
    }

    string? version_de (string ruta) {
        var o = leer (ruta);
        return o != null && o.has_member ("version") ? o.get_string_member ("version") : null;
    }

    public string perfiles () {
        return Path.build_filename (Environment.get_user_data_dir (), "mint-macos", "macos");
    }

    /* La de esta sesión (la aplicó el arranque); si no, la escogida; si no, Catalina. */
    public string activa () {
        if (_activa == null) {
            _activa = version_de (Path.build_filename (Environment.get_user_runtime_dir (), "mint-macos", "macos.json"))
                ?? version_de (Path.build_filename (Environment.get_user_config_dir (), "mint-macos", "macos.json"))
                ?? POR_DEFECTO;
        }
        return _activa;
    }

    /* apps/<app>.json de la versión activa, o null si no hay. */
    public Json.Object? perfil (string app) {
        if (_perfiles == null)
            _perfiles = new HashTable<string, Json.Object> (str_hash, str_equal);
        var o = _perfiles.lookup (app);
        if (o == null) {
            o = leer (Path.build_filename (perfiles (), activa (), "apps", app + ".json"));
            if (o != null)
                _perfiles.insert (app, o);
        }
        return o;
    }

    /* Los ítems de un menú: el menú Apple ("menu-apple", "menu-apple") o uno estándar
     * ("menus-estandar", "app" | "file" | "edit" | "window"…). */
    public Json.Array? menu (string app, string id_menu) {
        var p = perfil (app);
        if (p == null)
            return null;
        if (p.has_member ("id") && p.get_string_member ("id") == id_menu && p.has_member ("items"))
            return p.get_array_member ("items");
        if (!p.has_member ("menus"))
            return null;
        foreach (var n in p.get_array_member ("menus").get_elements ()) {
            var m = n.get_object ();
            if (m.get_string_member ("id") == id_menu && m.has_member ("items"))
                return m.get_array_member ("items");
        }
        return null;
    }

    /* Un ítem por su id estable (comando de Carbon o acción de AppKit); null si en esta versión
     * no existe. */
    public Json.Object? item (string app, string id_menu, string id) {
        var items = menu (app, id_menu);
        if (items == null)
            return null;
        foreach (var n in items.get_elements ()) {
            var o = n.get_object ();
            if (o.has_member ("id") && o.get_string_member ("id") == id)
                return o;
        }
        return null;
    }
}
