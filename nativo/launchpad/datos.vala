/*
 * Lo que muestra el Launchpad: las apps de /Applications (los lanzadores que arma aplicaciones.py), las AppImages que hay
 * soltadas en /Applications o ~/Applications (con el lanzador que les escribe el servicio de aplicaciones, ver
 * aplicaciones/APPIMAGE.md) y, al final, la carpeta «Other» con las de Utilities; la búsqueda por palabras que empiezan
 * con lo escrito.
 */
namespace Launchpad {
    public const string DESTINO_POR_DEFECTO = "/Applications";

    public class Elemento : Object {
        public string nombre;
        public string clave;
    }

    public class App : Elemento {
        public string id;                   // el archivo del lanzador: con él se guarda el orden y las carpetas
        public DesktopAppInfo info;
        public string[] palabras;
        public Cairo.ImageSurface? icono = null;
        public bool icono_intentado = false;
        public Cairo.ImageSurface? mini = null;
        public bool mini_intentado = false;

        public App (DesktopAppInfo info, string ruta) {
            this.info = info;
            id = Path.get_basename (ruta);
            string n = info.get_name () ?? Path.get_basename (ruta);
            nombre = n.down ().has_suffix (".app") ? n.substring (0, n.length - 4) : n;
            clave = nombre.casefold ();
            palabras = separar_palabras (nombre);
        }

        public void lanzar () {
            try {
                info.launch (null, Gdk.Display.get_default ().get_app_launch_context ());
            } catch (Error e) {
                stderr.printf ("No se pudo abrir %s: %s\n", nombre, e.message);
            }
        }
    }

    public class Carpeta : Elemento {
        public string id = "";              // «otros» para la de Utilities; «c1», «c2»… las que arma la persona
        public bool es_otros = false;       // la de Utilities no se edita
        public List<App> apps;
        public Carpeta (string nombre, owned List<App> apps) {
            this.nombre = nombre;
            this.apps = (owned) apps;
            clave = nombre.casefold ();
        }
    }

    /** Las palabras de un nombre, partiendo también «ColorSync» en Color y Sync. */
    string[] separar_palabras (string nombre) {
        string[] salida = {};
        var actual = new StringBuilder ();
        unichar previo = 0;
        for (int i = 0; i < nombre.char_count (); i++) {
            unichar c = nombre.get_char (nombre.index_of_nth_char (i));
            bool corte = !c.isalnum () || (c.isupper () && actual.len > 0 && previo.islower ());
            if (corte && actual.len > 0) {
                salida += actual.str.casefold ();
                actual.truncate (0);
            }
            if (c.isalnum ()) {
                actual.append_unichar (c);
            }
            previo = c;
        }
        if (actual.len > 0) {
            salida += actual.str.casefold ();
        }
        return salida;
    }

    List<App> leer_carpeta (string ruta) {
        var apps = new List<App> ();
        var nombres = new GenericArray<string> ();
        try {
            var dir = Dir.open (ruta);
            string? n;
            while ((n = dir.read_name ()) != null) {
                nombres.add (n);
            }
        } catch (FileError e) {
            return apps;
        }
        nombres.sort ((a, b) => strcmp (a, b));
        foreach (var n in nombres.data) {
            if (!n.has_suffix (".desktop") || n == "launchpad.desktop" || n == "mint-macos-launchpad.desktop") {
                continue;
            }
            string p = Path.build_filename (ruta, n);
            var info = new DesktopAppInfo.from_filename (p);
            if (info == null || info.get_nodisplay ()) {
                continue;
            }
            apps.append (new App (info, p));
        }
        apps.sort ((a, b) => strcmp (a.clave, b.clave));
        return apps;
    }

    bool es_appimage (string nombre) {
        string m = nombre.down ();
        return m.has_suffix (".appimage");
    }

    /** El lanzador que el servicio escribe para una AppImage: el md5 es el de la URI file:// de su ruta. */
    string lanzador_de_appimage (string ruta) {
        string uri = File.new_for_path (ruta).get_uri ();
        string md5 = Checksum.compute_for_string (ChecksumType.MD5, uri);
        return Path.build_filename (Environment.get_user_data_dir (), "applications", "mint-macos-appimage-%s.desktop".printf (md5));
    }

    /** Las AppImages de una carpeta que ya tienen su lanzador; sin él (el servicio aún no pasó, o no la integró) no salen. */
    List<App> leer_appimages (string ruta) {
        var apps = new List<App> ();
        var nombres = new GenericArray<string> ();
        try {
            var dir = Dir.open (ruta);
            string? n;
            while ((n = dir.read_name ()) != null) {
                if (es_appimage (n)) {
                    nombres.add (n);
                }
            }
        } catch (FileError e) {
            return apps;
        }
        nombres.sort ((a, b) => strcmp (a, b));
        foreach (var n in nombres.data) {
            string archivo = Path.build_filename (ruta, n);
            string lanzador = lanzador_de_appimage (archivo);
            if (!FileUtils.test (lanzador, FileTest.EXISTS) || !FileUtils.test (archivo, FileTest.IS_REGULAR)) {
                continue;
            }
            var info = new DesktopAppInfo.from_filename (lanzador);
            if (info == null || info.get_nodisplay ()) {
                continue;
            }
            apps.append (new App (info, archivo));
        }
        return apps;
    }

    /** Las carpetas donde se buscan AppImages: la de destino y ~/Applications si existe. */
    string[] carpetas_de_appimages () {
        string[] r = { destino () };
        string casa = Path.build_filename (Environment.get_home_dir (), "Applications");
        if (casa != destino () && FileUtils.test (casa, FileTest.IS_DIR)) {
            r += casa;
        }
        return r;
    }

    public string destino () {
        return Environment.get_variable ("LAUNCHPAD_DESTINO") ?? DESTINO_POR_DEFECTO;
    }

    // ── el orden y las carpetas que arma la persona ───────────────────────
    // ~/.config/mint-macos/launchpad.json: {"orden": ["app:x.desktop", "carpeta:c1", "otros"],
    //   "carpetas": [{"id": "c1", "nombre": "Untitled", "apps": ["a.desktop", "b.desktop"]}]}.
    // Sin el archivo (o con apps nuevas que no están en él) sale como siempre: por orden alfabético y «Other» al final.
    public string ruta_diseno () {
        return Environment.get_variable ("LAUNCHPAD_DISENO")
            ?? Path.build_filename (Environment.get_user_config_dir (), "mint-macos", "launchpad.json");
    }

    class DisenoCarpeta : Object {
        public string id = "";
        public string nombre = "";
        public string[] apps = {};
    }

    class Diseno : Object {
        public string[] orden = {};
        public GenericArray<DisenoCarpeta> carpetas = new GenericArray<DisenoCarpeta> ();
    }

    Diseno leer_diseno () {
        var d = new Diseno ();
        try {
            var p = new Json.Parser ();
            p.load_from_file (ruta_diseno ());
            var raiz = p.get_root ().get_object ();
            if (raiz.has_member ("orden")) {
                foreach (var e in raiz.get_array_member ("orden").get_elements ()) {
                    d.orden += e.get_string ();
                }
            }
            if (raiz.has_member ("carpetas")) {
                foreach (var e in raiz.get_array_member ("carpetas").get_elements ()) {
                    var o = e.get_object ();
                    var c = new DisenoCarpeta ();
                    c.id = o.get_string_member ("id");
                    c.nombre = o.get_string_member ("nombre");
                    foreach (var a in o.get_array_member ("apps").get_elements ()) {
                        c.apps += a.get_string ();
                    }
                    d.carpetas.add (c);
                }
            }
        } catch (Error e) {
            // sin archivo o ilegible: el orden de siempre
        }
        return d;
    }

    /** Guarda el orden y las carpetas de lo que hay en la rejilla. */
    public void guardar_diseno (List<Elemento> elementos) {
        var b = new Json.Builder ();
        b.begin_object ();
        b.set_member_name ("version").add_int_value (1);
        b.set_member_name ("orden").begin_array ();
        foreach (var e in elementos) {
            if (e is Carpeta) {
                b.add_string_value (((Carpeta) e).es_otros ? "otros" : "carpeta:" + ((Carpeta) e).id);
            } else {
                b.add_string_value ("app:" + ((App) e).id);
            }
        }
        b.end_array ();
        b.set_member_name ("carpetas").begin_array ();
        foreach (var e in elementos) {
            if (!(e is Carpeta) || ((Carpeta) e).es_otros) {
                continue;
            }
            var c = (Carpeta) e;
            b.begin_object ();
            b.set_member_name ("id").add_string_value (c.id);
            b.set_member_name ("nombre").add_string_value (c.nombre);
            b.set_member_name ("apps").begin_array ();
            foreach (var a in c.apps) {
                b.add_string_value (a.id);
            }
            b.end_array ();
            b.end_object ();
        }
        b.end_array ();
        b.end_object ();
        var g = new Json.Generator ();
        g.root = b.get_root ();
        g.pretty = true;
        try {
            DirUtils.create_with_parents (Path.get_dirname (ruta_diseno ()), 0755);
            FileUtils.set_contents (ruta_diseno (), g.to_data (null));
        } catch (Error e) {
            stderr.printf ("No se pudo guardar el orden del Launchpad: %s\n", e.message);
        }
    }

    /** Los elementos de la rejilla y todas las apps (para buscar). */
    public void leer_aplicaciones (out List<Elemento> elementos, out List<App> todas) {
        var arriba = leer_carpeta (destino ());
        foreach (var d in carpetas_de_appimages ()) {
            foreach (var a in leer_appimages (d)) {
                arriba.append (a);
            }
        }
        arriba.sort ((a, b) => strcmp (a.clave, b.clave));
        var util = leer_carpeta (Path.build_filename (destino (), "Utilities"));
        elementos = new List<Elemento> ();
        todas = new List<App> ();
        var por_id = new HashTable<string, App> (str_hash, str_equal);
        foreach (var a in arriba) {
            todas.append (a);
            por_id[a.id] = a;
        }
        Carpeta? otros = null;
        if (util.length () > 0) {
            var copia = new List<App> ();
            foreach (var a in util) {
                copia.append (a);
                todas.append (a);
            }
            otros = new Carpeta ("Other", (owned) copia);
            otros.id = "otros";
            otros.es_otros = true;
        }

        // Las carpetas de la persona, con las apps que todavía existen; lo que está en una carpeta no sale suelto.
        var diseno = leer_diseno ();
        var carpetas = new HashTable<string, Carpeta> (str_hash, str_equal);
        var en_carpeta = new HashTable<string, bool> (str_hash, str_equal);
        foreach (var dc in diseno.carpetas.data) {
            var apps = new List<App> ();
            foreach (var aid in dc.apps) {
                var a = por_id[aid];
                if (a != null && !en_carpeta.contains (aid)) {
                    apps.append (a);
                    en_carpeta[aid] = true;
                }
            }
            if (apps.length () == 0) {
                continue;
            }
            var c = new Carpeta (dc.nombre, (owned) apps);
            c.id = dc.id;
            carpetas[dc.id] = c;
        }
        // En el orden guardado; lo que no está (apps nuevas) va al final, alfabético.
        var puestos = new HashTable<string, bool> (str_hash, str_equal);
        foreach (var clave in diseno.orden) {
            if (clave == "otros" && otros != null && !puestos.contains ("otros")) {
                elementos.append (otros);
                puestos["otros"] = true;
            } else if (clave.has_prefix ("carpeta:")) {
                var c = carpetas[clave.substring (8)];
                if (c != null && !puestos.contains (clave)) {
                    elementos.append (c);
                    puestos[clave] = true;
                }
            } else if (clave.has_prefix ("app:")) {
                var aid = clave.substring (4);
                var a = por_id[aid];
                if (a != null && !en_carpeta.contains (aid) && !puestos.contains (clave)) {
                    elementos.append (a);
                    puestos[clave] = true;
                }
            }
        }
        foreach (var a in arriba) {
            if (!en_carpeta.contains (a.id) && !puestos.contains ("app:" + a.id)) {
                elementos.append (a);
            }
        }
        foreach (var dc in diseno.carpetas.data) {
            var c = carpetas[dc.id];
            if (c != null && !puestos.contains ("carpeta:" + dc.id)) {
                elementos.append (c);
            }
        }
        if (otros != null && !puestos.contains ("otros")) {
            elementos.append (otros);
        }
    }

    public List<App> buscar (List<App> todas, string consulta) {
        string q = consulta.strip ().casefold ();
        var prim = new List<App> ();
        var resto = new List<App> ();
        if (q == "") {
            return prim;
        }
        foreach (var a in todas) {
            if (a.clave.has_prefix (q)) {
                prim.append (a);
                continue;
            }
            bool coincide = q.contains (" ") && a.clave.contains (q);
            foreach (var p in a.palabras) {
                if (p.has_prefix (q)) {
                    coincide = true;
                    break;
                }
            }
            if (coincide) {
                resto.append (a);
            }
        }
        foreach (var a in resto) {
            prim.append (a);
        }
        return prim;
    }

    /** Qué hay hoy en /Applications y en Utilities (nombre y fecha de cada lanzador): para saber si cambió. */
    public string sello_apps () {
        var sb = new StringBuilder ();
        // Las AppImages: el archivo y su lanzador (aparece o se quita sin que cambie ningún .desktop de /Applications).
        foreach (var d in carpetas_de_appimages ()) {
            try {
                var dir = Dir.open (d);
                string? n;
                while ((n = dir.read_name ()) != null) {
                    if (!es_appimage (n)) {
                        continue;
                    }
                    Posix.Stat st;
                    string l = lanzador_de_appimage (Path.build_filename (d, n));
                    sb.append ("%s|%s;".printf (n, Posix.stat (l, out st) == 0 ? "%ld|%ld".printf ((long) st.st_mtim.tv_sec, (long) st.st_mtim.tv_nsec) : "-"));
                }
            } catch (FileError e) {
            }
        }
        foreach (var d in new string[] { destino (), Path.build_filename (destino (), "Utilities") }) {
            try {
                var dir = Dir.open (d);
                var nombres = new GenericArray<string> ();
                string? n;
                while ((n = dir.read_name ()) != null) {
                    if (n.has_suffix (".desktop")) {
                        nombres.add (n);
                    }
                }
                nombres.sort ((a, b) => strcmp (a, b));
                foreach (var n2 in nombres.data) {
                    Posix.Stat st;
                    if (Posix.stat (Path.build_filename (d, n2), out st) == 0) {
                        sb.append ("%s|%ld|%ld;".printf (n2, (long) st.st_mtim.tv_sec, (long) st.st_mtim.tv_nsec));
                    }
                }
            } catch (FileError e) {
            }
        }
        return sb.str;
    }

    // ── íconos ───────────────────────────────────────────────────────────
    public Cairo.ImageSurface? superficie_de (Gdk.Pixbuf pb) {
        var sup = new Cairo.ImageSurface (Cairo.Format.ARGB32, pb.width, pb.height);
        var cr = new Cairo.Context (sup);
        Gdk.cairo_set_source_pixbuf (cr, pb, 0, 0);
        cr.paint ();
        return sup;
    }

    public Cairo.ImageSurface? icono_de (App app, int lado) {
        var tema = Gtk.IconTheme.get_default ();
        var ic = app.info.get_icon ();
        Gdk.Pixbuf? pb = null;
        try {
            if (ic is ThemedIcon) {
                var nombres = ((ThemedIcon) ic).get_names ();
                foreach (var n in nombres) {
                    if (tema.has_icon (n)) {
                        pb = tema.load_icon (n, lado, Gtk.IconLookupFlags.FORCE_SIZE);
                        break;
                    }
                }
            } else if (ic is FileIcon) {
                pb = new Gdk.Pixbuf.from_file_at_size (((FileIcon) ic).get_file ().get_path (), lado, lado);
            }
            if (pb == null) {
                pb = tema.load_icon ("application-x-executable", lado, Gtk.IconLookupFlags.FORCE_SIZE);
            }
        } catch (Error e) {
            return null;
        }
        return pb != null ? superficie_de (pb) : null;
    }
}
