/*
 * Íconos de Apple sacados del disco de la Mac, solo en local (nunca al repo); port de settings/iconos_catalina.py.
 *
 * Los dejan tema/iconos/car.py (hojas deepmap2 de los Assets.car, sesión de Infra: ~/.local/share/mint-macos/iconos-catalina-deepmap2/)
 * y desde-mac.sh/Pillow (los .icns de las apps, en ~/.local/share/mint-macos/settings/privacidad/). Si falta alguno, la fila va sin
 * ícono: nunca se pone otro en su lugar.
 */
namespace Preferencias {

    namespace IconosCatalina {
        string casa () {
            return Path.build_filename (Environment.get_home_dir (), ".local", "share", "mint-macos");
        }

        /** El primero (por orden alfabético) de los archivos de una carpeta que casan con el patrón (* y ?), o null. */
        string? buscar (string carpeta, string patron) {
            var spec = new PatternSpec (patron);
            var nombres = new GenericArray<string> ();
            try {
                var dir = Dir.open (carpeta);
                string? n;
                while ((n = dir.read_name ()) != null) {
                    if (spec.match_string (n)) {
                        nombres.add (n);
                    }
                }
            } catch (Error e) {
                return null;
            }
            if (nombres.length == 0) {
                return null;
            }
            nombres.sort ((a, b) => strcmp (a, b));
            return Path.build_filename (carpeta, nombres[0]);
        }

        /** Gtk.Image del archivo a ese tamaño (en píxeles lógicos), o null si no existe. */
        public Gtk.Image? imagen (string? ruta, int tam) {
            if (ruta == null || !FileUtils.test (ruta, FileTest.EXISTS)) {
                return null;
            }
            try {
                var pb = new Gdk.Pixbuf.from_file_at_size (ruta, tam * 2, tam * 2);
                return new Gtk.Image.from_pixbuf (pb.scale_simple (tam, tam, Gdk.InterpType.HYPER));
            } catch (Error e) {
                return null;
            }
        }

        public Gtk.Image? de_screentime (string nombre, int tam = 24) {
            return imagen (buscar (Path.build_filename (casa (), "iconos-catalina-deepmap2", "ScreenTime"), nombre + "-*@2x.png"), tam);
        }

        /** El ícono de un módulo de Dock & Menu Bar de Monterey («WiFi», «Sound», «Clock»…): perfiles/iconos-modulos-monterey.sh los copia del .car del panel. */
        public Gtk.Image? de_modulo_dock (string nombre, int tam = 24) {
            return imagen (Path.build_filename (casa (), "iconos-monterey", "Dock", nombre + ".png"), tam);
        }

        public Gtk.Image? de_atajos (string categoria, int tam = 16) {
            return imagen (buscar (Path.build_filename (casa (), "iconos-catalina-deepmap2", "shortcuts"),
                                   "category_%s-32x32@2x.png".printf (categoria)), tam);
        }

        /** «locationservices», «camera»… (Security.prefPane) o «contacts», «calendars», «reminders», «photos» (de sus apps). */
        public Gtk.Image? de_privacidad (string nombre, int tam = 24) {
            var ruta = buscar (Path.build_filename (casa (), "iconos-catalina-deepmap2", "Security"), "privacy-%s-*@2x.png".printf (nombre));
            if (ruta == null) {
                ruta = buscar (Path.build_filename (casa (), "settings", "privacidad"), nombre + ".png");
            }
            return imagen (ruta, tam);
        }

        // Banderas de Input Sources: el archivo de Apple trae 173 en orden y sin nombres. Solo van las que se compararon con la captura
        // (U.S. = la bandera sola; Spanish - ISO = España con «ISO» debajo); las demás distribuciones salen sin bandera.
        public Gtk.Image? bandera (string capa, int tam = 18) {
            int n = -1;
            if (capa == "us") {
                n = 58;
            } else if (capa == "es") {
                n = 51;
            }
            if (n < 0) {
                return null;
            }
            return imagen (buscar (Path.build_filename (casa (), "iconos-catalina-deepmap2", "banderas"), "bandera-%03d-*.png".printf (n)), tam);
        }
    }
}
