/*
 * Las opciones de la herramienta (Options ⌄), en ~/.config/mac-captura/config.json: el mismo archivo y el mismo
 * formato que escribe herramienta.py, para que la vuelta atrás no pierda nada. Son siete claves planas; se leen y
 * se escriben a mano, sin json-glib.
 */
namespace Captura {
    public class Config : Object {
        public string modo = "pantalla";
        public string guardar_en = "";
        public string destino = "carpeta";
        public int temporizador = 0;
        public string micro = "";
        public bool miniatura = true;
        public bool recordar = true;

        public static string ruta () {
            return Path.build_filename (Environment.get_home_dir (), ".config", "mac-captura", "config.json");
        }

        public static Config cargar () {
            var c = new Config ();
            try {
                string texto;
                FileUtils.get_contents (ruta (), out texto);
                var re = new Regex ("\"((?:[^\"\\\\]|\\\\.)*)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\"|true|false|-?\\d+)");
                MatchInfo m;
                for (re.match (texto, 0, out m); m.matches (); m.next ()) {
                    var clave = desescapar (m.fetch (1));
                    var valor = m.fetch (2);
                    var es_texto = valor.has_prefix ("\"");
                    var s = es_texto ? desescapar (valor.substring (1, valor.length - 2)) : valor;
                    switch (clave) {
                    case "modo": c.modo = s; break;
                    case "guardar_en": c.guardar_en = s; break;
                    case "destino": c.destino = s; break;
                    case "micro": c.micro = s; break;
                    case "temporizador": c.temporizador = int.parse (s); break;
                    case "miniatura": c.miniatura = (s == "true"); break;
                    case "recordar": c.recordar = (s == "true"); break;
                    }
                }
            } catch (Error e) {
                // sin archivo, o ilegible: valores por defecto
            }
            return c;
        }

        public void guardar () {
            var sb = new StringBuilder ();
            sb.append ("{\n");
            sb.append ("  \"modo\": %s,\n".printf (comillas (modo)));
            sb.append ("  \"guardar_en\": %s,\n".printf (comillas (guardar_en)));
            sb.append ("  \"destino\": %s,\n".printf (comillas (destino)));
            sb.append ("  \"temporizador\": %d,\n".printf (temporizador));
            sb.append ("  \"micro\": %s,\n".printf (comillas (micro)));
            sb.append ("  \"miniatura\": %s,\n".printf (miniatura ? "true" : "false"));
            sb.append ("  \"recordar\": %s\n".printf (recordar ? "true" : "false"));
            sb.append ("}");
            try {
                DirUtils.create_with_parents (Path.get_dirname (ruta ()), 0755);
                FileUtils.set_contents (ruta (), sb.str);
            } catch (Error e) {
                // no se pudo guardar: la herramienta sigue
            }
        }

        static string comillas (string s) {
            var sb = new StringBuilder ("\"");
            for (int i = 0; i < s.length; i++) {
                char ch = s[i];
                if (ch == '"') sb.append ("\\\"");
                else if (ch == '\\') sb.append ("\\\\");
                else if (ch == '\n') sb.append ("\\n");
                else if (ch == '\t') sb.append ("\\t");
                else sb.append_c (ch);
            }
            sb.append_c ('"');
            return sb.str;
        }

        // Lo que escribe Python: \" \\ \/ \n \t y \uXXXX para lo que no es ASCII.
        static string desescapar (string s) {
            var sb = new StringBuilder ();
            int i = 0;
            while (i < s.length) {
                char ch = s[i];
                if (ch != '\\' || i + 1 >= s.length) {
                    sb.append_c (ch);
                    i++;
                    continue;
                }
                char sig = s[i + 1];
                i += 2;
                switch (sig) {
                case 'n': sb.append_c ('\n'); break;
                case 't': sb.append_c ('\t'); break;
                case 'u':
                    if (i + 4 <= s.length) {
                        uint cp;
                        uint.try_parse ("0x" + s.substring (i, 4), out cp);
                        i += 4;
                        // par sustituto (emoji y similares)
                        if (cp >= 0xD800 && cp < 0xDC00 && i + 6 <= s.length && s[i] == '\\' && s[i + 1] == 'u') {
                            uint lo;
                            uint.try_parse ("0x" + s.substring (i + 2, 4), out lo);
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                            i += 6;
                        }
                        sb.append_unichar ((unichar) cp);
                    }
                    break;
                default: sb.append_c (sig); break;
                }
            }
            return sb.str;
        }
    }

    /**
     * El último rectángulo de «Capture Selected Portion», uno por pantalla (clave «ANCHOxALTO+X+Y» del monitor donde cae su centro), en
     * ~/.local/state/mac-captura/ultima-region.json: sobrevive a reiniciar la sesión. En la Mac ⇧⌘5 vuelve a mostrar la última porción,
     * con su ancho, alto y posición (fuente: José, 27-10-2026; sin captura de Catalina).
     */
    public class UltimaRegion : Object {
        public static string ruta () {
            return Path.build_filename (Environment.get_user_state_dir (), "mac-captura", "ultima-region.json");
        }

        public static string clave (Gdk.Display display, int[] r) {
            var m = display.get_monitor_at_point (r[0] + r[2] / 2, r[1] + r[3] / 2);
            var g = m.get_geometry ();
            return "%dx%d+%d+%d".printf (g.width, g.height, g.x, g.y);
        }

        static HashTable<string, string> leer () {
            var t = new HashTable<string, string> (str_hash, str_equal);
            try {
                string texto;
                FileUtils.get_contents (ruta (), out texto);
                var re = new Regex ("\"([^\"]+)\"\\s*:\\s*\\{\\s*\"x\":\\s*(-?\\d+),\\s*\"y\":\\s*(-?\\d+),\\s*\"w\":\\s*(\\d+),\\s*\"h\":\\s*(\\d+)");
                MatchInfo m;
                for (re.match (texto, 0, out m); m.matches (); m.next ()) {
                    t.insert (m.fetch (1), "%s,%s,%s,%s".printf (m.fetch (2), m.fetch (3), m.fetch (4), m.fetch (5)));
                }
            } catch (Error e) {
                // sin archivo: nada recordado
            }
            return t;
        }

        /** El rectángulo recordado para esta pantalla, si cabe en ella; null si no hay. */
        public static int[]? cargar (Gdk.Display display, Gdk.Monitor monitor) {
            var g = monitor.get_geometry ();
            var v = leer ().lookup ("%dx%d+%d+%d".printf (g.width, g.height, g.x, g.y));
            if (v == null) return null;
            var p = v.split (",");
            int[] r = { int.parse (p[0]), int.parse (p[1]), int.parse (p[2]), int.parse (p[3]) };
            bool cabe = r[2] >= 40 && r[3] >= 40 && r[0] >= g.x && r[1] >= g.y && r[0] + r[2] <= g.x + g.width && r[1] + r[3] <= g.y + g.height;
            return cabe ? r : null;
        }

        public static void guardar (Gdk.Display display, int[] r) {
            var t = leer ();
            t.insert (clave (display, r), "%d,%d,%d,%d".printf (r[0], r[1], r[2], r[3]));
            var sb = new StringBuilder ("{\n");
            var claves = t.get_keys ();
            bool primero = true;
            foreach (var k in claves) {
                var p = t.lookup (k).split (",");
                if (!primero) sb.append (",\n");
                primero = false;
                sb.append ("  \"%s\": {\"x\": %s, \"y\": %s, \"w\": %s, \"h\": %s}".printf (k, p[0], p[1], p[2], p[3]));
            }
            sb.append ("\n}\n");
            try {
                DirUtils.create_with_parents (Path.get_dirname (ruta ()), 0755);
                FileUtils.set_contents (ruta (), sb.str);
            } catch (Error e) {
                // no se pudo recordar: la herramienta sigue
            }
        }
    }
}
