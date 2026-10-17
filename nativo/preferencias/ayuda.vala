/*
 * Lo común de System Preferences: dónde están los íconos de Apple (settings/desde-mac.sh), cómo se pintan los glifos de la
 * barra y las piezas que repiten todos los paneles (etiqueta de fila, slider con marcas, control en gris).
 */
namespace Preferencias {
    public const string APP_ID = "io.github.josemalena.MintMacosSettings";
    public const string TITULO = "System Preferences";
    public const int ICONO = 40;               // el ícono de cada panel en la cuadrícula
    public const int COLUMNAS = 8;             // paneles por fila, como en Catalina
    public const int ANCHO = 668;              // el ancho de la ventana de Catalina
    public const int BUSCADOR_ANCHO = 158;     // medido en la captura de Catalina (1 px = 1 pt)
    public const int MIN_ALTO = 380;
    public const int MIN_PAGINA = 520;         // una página de panel no baja de esto: sus listas se estiran
    public const string MOTIVO = "This feature is not available on this computer.";

    public string carpeta_apps () {
        return Path.build_filename (Environment.get_home_dir (), ".local", "share", "mint-macos", "settings");
    }

    /** Donde está instalado el System Preferences de Python (su CSS y su ventana de respaldo). */
    public string carpeta_python () {
        var env = Environment.get_variable ("MP_PYTHON_DIR");
        return env != null ? env : Path.build_filename (Environment.get_home_dir (), ".local", "lib", "mint-macos", "settings");
    }

    /** El ícono de Apple del panel (settings/iconos/ID.png), o el del tema. */
    public Gdk.Pixbuf? pixbuf_icono (string ident, string icono_tema, int lado) {
        var ruta = Path.build_filename (carpeta_apps (), "iconos", ident + ".png");
        try {
            if (FileUtils.test (ruta, FileTest.EXISTS)) {
                return new Gdk.Pixbuf.from_file_at_size (ruta, lado, lado);
            }
        } catch (Error e) {
        }
        var tema = Gtk.IconTheme.get_default ();
        foreach (var nombre in new string[] { icono_tema, "preferences-system" }) {
            try {
                // FORCE_SIZE: que todos midan lo mismo, aunque el tema no tenga ese tamaño.
                return tema.load_icon (nombre, lado, Gtk.IconLookupFlags.FORCE_SIZE);
            } catch (Error e) {
            }
        }
        return null;
    }

    public Gtk.Image imagen_icono (string ident, string icono_tema, int lado) {
        var img = new Gtk.Image ();
        var pb = pixbuf_icono (ident, icono_tema, lado);
        if (pb != null) {
            img.set_from_pixbuf (pb);
        }
        img.set_size_request (lado, lado);
        return img;
    }

    /** El ícono grande de un panel dentro de su página (Siri…): el de Apple o el genérico del tema. */
    public Gtk.Image imagen_icono_panel (string ident, int lado) {
        var img = new Gtk.Image ();
        var ruta = Path.build_filename (carpeta_apps (), "iconos", ident + ".png");
        try {
            img.set_from_pixbuf (new Gdk.Pixbuf.from_file_at_size (ruta, lado, lado));
        } catch (Error e) {
            img.set_from_icon_name ("preferences-system", Gtk.IconSize.DIALOG);
        }
        return img;
    }

    /**
     * Un glifo de la barra de herramientas de Apple, pintado del color dado. Salen en negro de la Mac
     * (settings/desde-mac.sh): aquí se usan como máscara. Sin ellos se usa el ícono simbólico del tema.
     */
    public Gtk.Image glifo (string nombre, string respaldo, double r = 1.0, double g = 1.0, double b = 1.0, double a = 0.85) {
        int escala = Gdk.Screen.get_default ().get_monitor_scale_factor (0);
        escala = escala >= 2 ? 2 : 1;
        var ruta = Path.build_filename (carpeta_apps (), "glifos", "%s@%dx.png".printf (nombre, escala));
        Gdk.Pixbuf pb;
        try {
            pb = new Gdk.Pixbuf.from_file (ruta);
        } catch (Error e) {
            return new Gtk.Image.from_icon_name (respaldo, Gtk.IconSize.MENU);
        }
        int ancho = pb.get_width (), alto = pb.get_height ();
        var mascara = new Cairo.ImageSurface (Cairo.Format.ARGB32, ancho, alto);
        var cr = new Cairo.Context (mascara);
        Gdk.cairo_set_source_pixbuf (cr, pb, 0, 0);
        cr.paint ();
        var pintado = new Cairo.ImageSurface (Cairo.Format.ARGB32, ancho, alto);
        cr = new Cairo.Context (pintado);
        cr.set_source_rgba (r, g, b, a);
        cr.mask_surface (mascara, 0, 0);
        pintado.set_device_scale (escala, escala);
        return new Gtk.Image.from_surface (pintado);
    }

    /** La etiqueta de una fila («Size:»), a la derecha. */
    public Gtk.Label etiqueta_fila (string texto) {
        var l = new Gtk.Label (texto);
        l.xalign = 1.0f;
        l.get_style_context ().add_class ("mp-fila-etiqueta");
        return l;
    }

    /** Un control en gris, como en una Mac que no tuviera esa función. */
    public Gtk.Widget gris (Gtk.Widget w) {
        w.set_sensitive (false);
        w.set_tooltip_text (MOTIVO);
        return w;
    }

    /** El «?» redondo de abajo a la derecha de los paneles de Catalina (aquí no hay Help Viewer: en gris). */
    public Gtk.Widget boton_ayuda () {
        var b = new Gtk.Button.with_label ("?");
        b.get_style_context ().add_class ("circular");
        b.set_size_request (24, 24);
        return gris (b);
    }

    public Gtk.Frame marco_lista () {
        var m = new Gtk.Frame (null);
        m.get_style_context ().add_class ("mp-sd-lista");
        return m;
    }

    public void margenes (Gtk.Widget w, int arriba, int abajo, int inicio, int fin) {
        w.margin_top = arriba;
        w.margin_bottom = abajo;
        w.margin_start = inicio;
        w.margin_end = fin;
    }
}

namespace Preferencias {
    /** Settings del esquema si está instalado; null si no (g_settings_new con un esquema que falta aborta el programa). */
    public Settings? abrir_settings (string esquema) {
        var fuente = SettingsSchemaSource.get_default ();
        if (fuente == null || fuente.lookup (esquema, true) == null) {
            return null;
        }
        return new Settings (esquema);
    }

    /**
     * Las claves de un JSON plano (sin anidar) como texto, a la manera de str() de Python: «true» entre comillas es texto
     * «true», pero un true sin comillas es «True». Sin json-glib: los archivos que se leen aquí (timeshift.json…) son planos.
     */
    public HashTable<string, string> json_plano (string ruta) {
        var d = new HashTable<string, string> (str_hash, str_equal);
        try {
            string texto;
            FileUtils.get_contents (ruta, out texto);
            var re = new Regex ("\"((?:[^\"\\\\]|\\\\.)*)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\"|true|false|null|-?[0-9.eE+-]+)");
            MatchInfo m;
            for (re.match (texto, 0, out m); m.matches (); m.next ()) {
                var v = m.fetch (2);
                if (v.has_prefix ("\"")) {
                    v = v.substring (1, v.length - 2).replace ("\\\"", "\"").replace ("\\\\", "\\");
                } else if (v == "true") {
                    v = "True";
                } else if (v == "false") {
                    v = "False";
                } else if (v == "null") {
                    v = "None";
                }
                d[m.fetch (1)] = v;
            }
        } catch (Error e) {
            return d;
        }
        return d;
    }

    public delegate void Hacer ();
}
