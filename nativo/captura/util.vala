/*
 * Lo que no es ventana: carpetas, nombres de archivo como los de la Mac, a dónde va la captura, la sombra.
 */
namespace Captura {
    public const string[] MODOS = { "pantalla", "ventana", "porcion", "grabar-pantalla", "grabar-porcion" };

    public string tip_de (string modo) {
        switch (modo) {
        case "pantalla": return "Capture Entire Screen";
        case "ventana": return "Capture Selected Window";
        case "porcion": return "Capture Selected Portion";
        case "grabar-pantalla": return "Record Entire Screen";
        default: return "Record Selected Portion";
        }
    }

    string? escritorio_cache = null;

    // XDG_DESKTOP_DIR de ~/.config/user-dirs.dirs, sin lanzar xdg-user-dir (un proceso menos al abrir la barra).
    string desktop_de_xdg () {
        var home = Environment.get_home_dir ();
        try {
            string texto;
            FileUtils.get_contents (Path.build_filename (Environment.get_user_config_dir (), "user-dirs.dirs"), out texto);
            foreach (var linea in texto.split ("\n")) {
                if (!linea.has_prefix ("XDG_DESKTOP_DIR=")) continue;
                var v = linea.substring (16).strip ();
                if (v.has_prefix ("\"") && v.has_suffix ("\"") && v.length >= 2) v = v.substring (1, v.length - 2);
                if (v.has_prefix ("$HOME")) v = home + v.substring (5);
                return v;
            }
        } catch (Error e) {
        }
        return "";
    }

    public string escritorio () {
        if (escritorio_cache != null) return escritorio_cache;
        var home = Environment.get_home_dir ();
        var d = desktop_de_xdg ();
        var sin_barra = d;
        while (sin_barra.length > 1 && sin_barra.has_suffix ("/")) sin_barra = sin_barra.substring (0, sin_barra.length - 1);
        if (d == "" || sin_barra == home) d = Path.build_filename (home, "Desktop");
        escritorio_cache = d;
        return d;
    }

    public string[] carpetas_rutas () {
        var home = Environment.get_home_dir ();
        return { escritorio (), Path.build_filename (home, "Documents"), Path.build_filename (home, "Downloads") };
    }

    public string temporales () {
        var t = Path.build_filename (Environment.get_home_dir (), ".cache", "mac-captura");
        DirUtils.create_with_parents (t, 0755);
        return t;
    }

    /** «Screen Shot 2026-10-14 at 3.00.00 PM.png»; si existe, « (2)», « (3)»… como la Mac. Siempre en inglés. */
    public string nombre_libre (string carpeta, string prefijo, string ext) {
        DirUtils.create_with_parents (carpeta, 0755);
        var t = new DateTime.now_local ();
        int h = t.get_hour ();
        int h12 = h % 12 == 0 ? 12 : h % 12;
        var base_ = "%s %04d-%02d-%02d at %d.%02d.%02d %s".printf (prefijo, t.get_year (), t.get_month (), t.get_day_of_month (),
                                                              h12, t.get_minute (), t.get_second (), h < 12 ? "AM" : "PM");
        var ruta = Path.build_filename (carpeta, "%s.%s".printf (base_, ext));
        int n = 2;
        while (FileUtils.test (ruta, FileTest.EXISTS)) {
            ruta = Path.build_filename (carpeta, "%s (%d).%s".printf (base_, n, ext));
            n++;
        }
        return ruta;
    }

    string[]? micros_cache = null;

    public string[] micros () {
        if (micros_cache != null) return micros_cache;
        string[] fuentes = {};
        try {
            string salida;
            Process.spawn_command_line_sync ("pactl list short sources", out salida);
            foreach (var linea in salida.split ("\n")) {
                var partes = linea.split ("\t");
                if (partes.length > 1 && !linea.contains (".monitor")) fuentes += partes[1];
            }
        } catch (Error e) {
        }
        micros_cache = fuentes;
        return fuentes;
    }

    // Un proceso suelto que sobrevive a este (xclip sigue sirviendo la selección hasta que otro programa la toma).
    void soltar (string[] argv) {
        try {
            Pid pid;
            Process.spawn_async (null, argv, null,
                                 SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                 () => { Posix.setsid (); }, out pid);
            Process.close_pid (pid);
        } catch (Error e) {
            stderr.printf ("No se pudo lanzar %s: %s\n", argv[0], e.message);
        }
    }

    /** Lo que se hace con el archivo cuando el destino no es una carpeta. */
    public void entregar (string destino, string ruta) {
        if (destino == "clipboard") {
            soltar ({ "xclip", "-selection", "clipboard", "-t", "image/png", "-i", ruta });
        } else if (destino == "mail") {
            soltar ({ "xdg-email", "--attach", ruta });
        } else if (destino == "preview") {
            soltar ({ "xdg-open", ruta });
        }
    }

    public void abrir (string ruta) {
        soltar ({ "xdg-open", ruta });
    }

    /** Como la captura de ventana de la Mac: sombra alrededor, en el canal alfa (medida en una captura de Catalina). */
    public void con_sombra (string ruta) throws Error {
        string[] argv = { "convert", ruta, "(", "+clone", "-background", "black", "-shadow", "35x28+0+18", ")", "+swap",
                          "-background", "none", "-layers", "merge", "+repage", ruta };
        int estado;
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, null, null, out estado);
        if (estado != 0) throw new IOError.FAILED ("convert terminó con error");
    }

    /** (izq, der, arriba, abajo) de _GTK_FRAME_EXTENTS, o ceros si la ventana no dibuja sombra. */
    public int[] extensiones_gtk (Gdk.Window w) {
        int[] ceros = { 0, 0, 0, 0 };
        Gdk.Atom tipo;
        int formato, largo;
        uint8[] datos;
        if (!Gdk.property_get (w, Gdk.Atom.intern ("_GTK_FRAME_EXTENTS", false), Gdk.Atom.intern ("CARDINAL", false),
                               0, 16, 0, out tipo, out formato, out datos)) {
            return ceros;
        }
        largo = datos.length;
        if (formato != 32) return ceros;
        // Con formato 32, X entrega cada valor como un «long» de C (8 bytes aquí).
        int paso = (int) sizeof (long);
        if (largo < 4 * paso) return ceros;
        long* p = (long*) datos;
        return { (int) p[0], (int) p[1], (int) p[2], (int) p[3] };
    }
}
