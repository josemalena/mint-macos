/*
 * Los atajos como los escribe la Mac en los menús: «⇧⌘Z», en el orden de la Mac (◆ ⌥ ⇧ ⌘). Con keyd, ⌘ es Ctrl; «^⌘»
 * (Ctrl+Super) lo trae el propio ítem en x-constanza-accel y se respeta tal cual. Las excepciones por app (la clase de
 * WM_CLASS, en minúsculas) se leen de ~/.config/keyd/app.conf: una línea «meta.q = C-S-q» dice que ⌘Q le llega a esa
 * app como Ctrl+Shift+Q, y su ítem con Ctrl+Shift+Q se pinta «⌘Q».
 */
namespace Menu {
    namespace Atajos {
        HashTable<string, string>? teclas = null;
        HashTable<string, HashTable<string, string>>? excepciones = null;
        int64 excepciones_mtime = -1;

        HashTable<string, string> tabla_teclas () {
            if (teclas == null) {
                teclas = new HashTable<string, string> (str_hash, str_equal);
                string[] pares = {
                    "Delete", "⌦", "BackSpace", "⌫", "Return", "↩", "Escape", "⎋", "Tab", "⇥", "space", "Space",
                    "Left", "←", "Right", "→", "Up", "↑", "Down", "↓", "Page_Up", "⇞", "Page_Down", "⇟",
                    "Home", "↖", "End", "↘", "plus", "+", "minus", "-", "equal", "=", "comma", ",", "period", ".",
                    "bracketleft", "[", "bracketright", "]", "slash", "/", "backslash", "\\", "semicolon", ";",
                    "apostrophe", "'", "grave", "`", "Insert", "Ins", "Esc", "⎋", "Del", "⌦", "Backspace", "⌫",
                    "Enter", "↩", "KP_Enter", "⌤",
                    // Edge manda algunas teclas como carácter de control, no por nombre.
                    "\x1b", "⎋", "\x7f", "⌦", "\x08", "⌫", "\t", "⇥", "\r", "↩", "\n", "↩"
                };
                for (int i = 0; i + 1 < pares.length; i += 2) teclas.insert (pares[i], pares[i + 1]);
            }
            return teclas;
        }

        public string tecla_bonita (string k) {
            var t = tabla_teclas ().lookup (k);
            if (t != null) return t;
            return k.char_count () == 1 ? k.up () : k;
        }

        const string ORDEN = "◆⌥⇧⌘";

        string ordenar (string mods) {
            var sb = new StringBuilder ();
            int i = 0;
            unichar c;
            while (ORDEN.get_next_char (ref i, out c)) {
                if (mods.contains (c.to_string ())) sb.append_unichar (c);
            }
            return sb.str;
        }

        /** «<Control><Shift>n» → «⇧⌘N». */
        public string de_gtk (string accel, string clase) {
            if (accel == "") return "";
            uint tecla;
            Gdk.ModifierType m;
            Gtk.accelerator_parse (accel, out tecla, out m);
            if (tecla == 0) return "";
            var nombre = Gdk.keyval_name (tecla) ?? "";
            if (nombre == "") return "";
            // Las teclas con símbolo («question», «F5» no) salen como el carácter.
            if (!tabla_teclas ().contains (nombre)) {
                unichar u = Gdk.keyval_to_unicode (tecla);
                if (u > 32 && u != 127) nombre = u.to_string ();
            }
            bool ctrl = (m & Gdk.ModifierType.CONTROL_MASK) != 0;
            bool shift = (m & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool alt = (m & Gdk.ModifierType.MOD1_MASK) != 0;
            bool sup = (m & (Gdk.ModifierType.SUPER_MASK | Gdk.ModifierType.META_MASK)) != 0;
            return formatear (ctrl, shift, alt, sup, nombre, clase);
        }

        /** [["Control", "Shift", "n"]] → «⇧⌘N». */
        public string de_dbusmenu (Variant? atajo, string clase) {
            if (atajo == null || atajo.n_children () == 0) return "";
            var fila = atajo.get_child_value (0);
            bool ctrl = false, shift = false, alt = false, sup = false;
            string tecla = "";
            for (size_t i = 0; i < fila.n_children (); i++) {
                var k = fila.get_child_value (i).get_string ();
                switch (k) {
                case "Control": case "Ctrl": case "Primary": ctrl = true; break;
                case "Shift": shift = true; break;
                case "Alt": alt = true; break;
                case "Super": case "Meta": sup = true; break;
                default: tecla = k; break;
                }
            }
            // Un atajo sin tecla (Edge manda alguno así) no se pinta a medias.
            if (tecla == "") return "";
            return formatear (ctrl, shift, alt, sup, tecla, clase);
        }

        string formatear (bool ctrl, bool shift, bool alt, bool sup, string nombre, string clase) {
            var ex = excepcion (clase, ctrl, shift, alt, sup, nombre);
            if (ex != null) return ex;
            var mods = new StringBuilder ();
            if (ctrl) mods.append ("⌘");
            if (shift) mods.append ("⇧");
            if (alt) mods.append ("⌥");
            if (sup) mods.append ("◆");
            return ordenar (mods.str) + tecla_bonita (nombre);
        }

        string clave (bool ctrl, bool shift, bool alt, bool sup, string tecla) {
            return "%s%s%s%s%s".printf (ctrl ? "C" : "", shift ? "S" : "", alt ? "A" : "", sup ? "M" : "", "+" + tecla.down ());
        }

        string? excepcion (string clase, bool ctrl, bool shift, bool alt, bool sup, string nombre) {
            if (clase == "") return null;
            cargar_excepciones ();
            var de_clase = excepciones.lookup (clase);
            if (de_clase == null) return null;
            return de_clase.lookup (clave (ctrl, shift, alt, sup, nombre));
        }

        /** ~/.config/keyd/app.conf: «[clase]» y líneas «meta.q = C-S-q» (entrada = salida). Se relee si cambia. */
        void cargar_excepciones () {
            var ruta = Path.build_filename (Environment.get_home_dir (), ".config", "keyd", "app.conf");
            int64 mt = 0;
            try {
                mt = File.new_for_path (ruta).query_info ("time::modified", FileQueryInfoFlags.NONE).get_modification_date_time ().to_unix ();
            } catch (GLib.Error e) {
                mt = 0;
            }
            if (excepciones != null && mt == excepciones_mtime) return;
            excepciones_mtime = mt;
            excepciones = new HashTable<string, HashTable<string, string>> (str_hash, str_equal);
            string texto;
            try {
                FileUtils.get_contents (ruta, out texto);
            } catch (GLib.Error e) {
                return;
            }
            string seccion = "";
            foreach (var l0 in texto.split ("\n")) {
                var l = l0.strip ();
                if (l == "" || l.has_prefix ("#")) continue;
                if (l.has_prefix ("[") && l.has_suffix ("]")) {
                    seccion = l.substring (1, l.length - 2).down ();
                    continue;
                }
                var eq = l.index_of ("=");
                if (eq < 0 || seccion == "") continue;
                var entrada = l.substring (0, eq).strip ();
                var salida = l.substring (eq + 1).strip ();
                // Solo las que traducen ⌘ + tecla a otra combinación de Ctrl/Shift/Alt; M-x (kitty) las deja pasar sin traducir.
                var punto = entrada.last_index_of (".");
                if (punto < 0 || !entrada.has_prefix ("meta") || salida.has_prefix ("M-") || salida.has_prefix ("A-") || !salida.contains ("-")) continue;
                bool shift_en = entrada.substring (0, punto).contains ("shift");
                var tecla_ent = entrada.substring (punto + 1);
                var partes = salida.split ("-");
                var tecla_sal = partes[partes.length - 1];
                bool c = false, s = false, a = false, m = false;
                for (int i = 0; i < partes.length - 1; i++) {
                    switch (partes[i]) {
                    case "C": c = true; break;
                    case "S": s = true; break;
                    case "A": a = true; break;
                    case "M": m = true; break;
                    }
                }
                var de_clase = excepciones.lookup (seccion);
                if (de_clase == null) {
                    de_clase = new HashTable<string, string> (str_hash, str_equal);
                    excepciones.insert (seccion, de_clase);
                }
                de_clase.insert (clave (c, s, a, m, tecla_sal), (shift_en ? "⇧" : "") + "⌘" + tecla_bonita (tecla_ent));
            }
        }
    }
}
