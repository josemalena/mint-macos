/*
 * Lo que muestra el Launchpad: las apps de /Applications (los lanzadores que arma aplicaciones.py) y, al final, la
 * carpeta «Other» con las de Utilities; la búsqueda por palabras que empiezan con lo escrito.
 */
namespace Launchpad {
    public const string DESTINO_POR_DEFECTO = "/Applications";

    public class Elemento : Object {
        public string nombre;
        public string clave;
    }

    public class App : Elemento {
        public DesktopAppInfo info;
        public string[] palabras;
        public Cairo.ImageSurface? icono = null;
        public bool icono_intentado = false;
        public Cairo.ImageSurface? mini = null;
        public bool mini_intentado = false;

        public App (DesktopAppInfo info, string ruta) {
            this.info = info;
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

    public string destino () {
        return Environment.get_variable ("LAUNCHPAD_DESTINO") ?? DESTINO_POR_DEFECTO;
    }

    /** Los elementos de la rejilla y todas las apps (para buscar). */
    public void leer_aplicaciones (out List<Elemento> elementos, out List<App> todas) {
        var arriba = leer_carpeta (destino ());
        var util = leer_carpeta (Path.build_filename (destino (), "Utilities"));
        elementos = new List<Elemento> ();
        todas = new List<App> ();
        foreach (var a in arriba) {
            elementos.append (a);
            todas.append (a);
        }
        if (util.length () > 0) {
            var copia = new List<App> ();
            foreach (var a in util) {
                copia.append (a);
                todas.append (a);
            }
            elementos.append (new Carpeta ("Other", (owned) copia));
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
