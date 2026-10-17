/*
 * Spotlyte (el «Spotlight» de este Linux, con el ícono de Spotlight de Catalina): los ajustes de Spotlyte (el fork de Ulauncher), en su
 * settings.json (port de PanelSpotlight en settings/propios.py). Solo lleva los controles que Spotlyte tiene de verdad; las
 * categorías de resultados y Privacy de Catalina no existen allí. Spotlyte lee su configuración al arrancar, así que cada cambio lo
 * reinicia (con los mismos argumentos con que estaba corriendo).
 */
namespace Preferencias {

    class ProcesoSpotlyte {
        public int pid;
        public string[] argv;
    }

    class OpcionCombo {
        public string clave;
        public string nombre;
    }

    public class PanelSpotlight : Panel {
        bool cargando = false;
        // MINT_SPOTLIGHT_ARCHIVO y MINT_SPOTLIGHT_SIN_REINICIO: para las pruebas (otro archivo; no reinicia Spotlyte).
        string archivo;
        bool sin_reinicio = Environment.get_variable ("MINT_SPOTLIGHT_SIN_REINICIO") != null;

        public PanelSpotlight () {
            id = "com.apple.preference.spotlight";
            nombre = "Spotlyte";
            palabras = "spotlyte, spotlight, search, ulauncher, shortcut, menu bar, recent apps";
            var otro = Environment.get_variable ("MINT_SPOTLIGHT_ARCHIVO");
            archivo = otro != null ? otro : Path.build_filename (Environment.get_home_dir (), ".config", "ulauncher", "settings.json");
        }

        Json.Object leer () {
            try {
                var p = new Json.Parser ();
                p.load_from_file (archivo);
                var raiz = p.get_root ();
                if (raiz != null && raiz.get_node_type () == Json.NodeType.OBJECT) {
                    return raiz.dup_object ();
                }
            } catch (Error e) {
            }
            return new Json.Object ();
        }

        /** Cambia una clave sin tocar las demás y reinicia Spotlyte para que la lea. */
        void escribir (string clave, Json.Node valor) {
            if (cargando) {
                return;
            }
            var datos = leer ();
            datos.set_member (clave, valor);
            var nodo = new Json.Node (Json.NodeType.OBJECT);
            nodo.set_object (datos);
            try {
                DirUtils.create_with_parents (Path.get_dirname (archivo), 0755);
                FileUtils.set_contents (archivo + ".tmp", json_a_texto (nodo));
                FileUtils.rename (archivo + ".tmp", archivo);
            } catch (Error e) {
                warning ("no se pudo escribir %s: %s", archivo, e.message);
                return;
            }
            Idle.add (() => { reiniciar (); return false; });
        }

        /** [(pid, argv)] de Spotlyte en marcha (su programa lleva «spotlyte» y «ulauncher» en la ruta). */
        static List<ProcesoSpotlyte> procesos () {
            var salida = new List<ProcesoSpotlyte> ();
            var propio = (int) Posix.getpid ();
            try {
                var dir = Dir.open ("/proc");
                string? d;
                while ((d = dir.read_name ()) != null) {
                    int pid;
                    if (!int.try_parse (d, out pid) || pid == propio) {
                        continue;
                    }
                    string texto;
                    try {
                        FileUtils.get_contents ("/proc/%s/cmdline".printf (d), out texto);
                    } catch (Error e) {
                        continue;
                    }
                    var argv = texto.split ("\0");
                    // El último elemento está vacío (la línea acaba en \0).
                    string[] limpio = {};
                    for (int i = 0; i < argv.length - 1; i++) {
                        limpio += argv[i];
                    }
                    if (limpio.length >= 2 && Path.get_basename (limpio[0]).contains ("python") && limpio[1].contains ("spotlyte")
                        && limpio[1].has_suffix ("/ulauncher")) {
                        var ps = new ProcesoSpotlyte ();
                        ps.pid = pid;
                        ps.argv = limpio;
                        salida.append (ps);
                    }
                }
            } catch (Error e) {
            }
            return salida;
        }

        void reiniciar () {
            if (sin_reinicio) {
                stderr.printf ("[prueba] reiniciaría Spotlyte\n");
                return;
            }
            var lista = procesos ();
            if (lista.length () == 0) {
                return;
            }
            var primero = lista.first ().data;
            string[] argv = {};
            foreach (var a in primero.argv) {
                argv += a;
            }
            foreach (var p in lista) {
                Posix.kill ((Posix.pid_t) p.pid, Posix.Signal.TERM);
            }
            for (int i = 0; i < 20; i++) {
                if (procesos ().length () == 0) {
                    break;
                }
                Thread.usleep (100000);
            }
            try {
                Process.spawn_async (null, argv, null,
                                     SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                     () => { Posix.setsid (); }, null);
            } catch (Error e) {
            }
        }

        // ── la página ────────────────────────────────────────────────────
        Gtk.ComboBoxText combo (Json.Object datos, OpcionCombo[] opciones, string clave, string defecto) {
            var c = new Gtk.ComboBoxText ();
            foreach (var o in opciones) {
                c.append (o.clave, o.nombre);
            }
            var actual = defecto;
            if (datos.has_member (clave)) {
                var n = datos.get_member (clave);
                if (n.get_node_type () == Json.NodeType.VALUE) {
                    var t = n.get_value_type ();
                    actual = t == typeof (string) ? n.get_string () : (t == typeof (bool) ? (n.get_boolean () ? "True" : "False")
                                                                                       : (t == typeof (int64) ? n.get_int ().to_string () : n.get_double ().to_string ()));
                }
            }
            if (!c.set_active_id (actual)) {
                c.append (actual, actual);
                c.set_active_id (actual);
            }
            c.changed.connect (() => escribir (clave, new Json.Node (Json.NodeType.VALUE).init_string (c.get_active_id ())));
            return c;
        }

        static OpcionCombo op (string clave, string nombre) {
            var o = new OpcionCombo ();
            o.clave = clave;
            o.nombre = nombre;
            return o;
        }

        public override Gtk.Widget? construir () {
            var datos = leer ();
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            caja.get_style_context ().add_class ("mp-propio");

            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            cab.pack_start (imagen_icono_panel (id, 48), false, false, 0);
            var t = new Gtk.Label ("Spotlyte helps you quickly find apps and files on your computer.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (70);
            cab.pack_start (t, true, true, 0);
            caja.pack_start (cab, false, false, 0);

            var marco = marco_lista ();
            var cuadro = new Gtk.Grid ();
            cuadro.column_spacing = 14;
            cuadro.row_spacing = 14;
            margenes (cuadro, 20, 20, 24, 24);
            cuadro.halign = Gtk.Align.START;
            marco.add (cuadro);
            int fila = 0;

            OpcionCombo[] atajos = { op ("<Super>space", "⌘Space"), op ("<Control>space", "⌃Space"), op ("<Alt>space", "⌥Space"),
                                     op ("<Alt><Super>space", "⌥⌘Space") };
            OpcionCombo[] pantallas = { op ("mouse-pointer-monitor", "Display with the mouse pointer"), op ("default-monitor", "Main display") };
            OpcionCombo[] recientes = { op ("0", "None"), op ("3", "3"), op ("5", "5"), op ("8", "8") };

            // Spotlight shortcut
            cuadro.attach (etiqueta_fila ("Spotlyte shortcut:"), 0, fila, 1, 1);
            cuadro.attach (combo (datos, atajos, "hotkey-show-app", "<Super>space"), 1, fila, 1, 1);
            fila++;
            // Show on
            cuadro.attach (etiqueta_fila ("Show Spotlyte on:"), 0, fila, 1, 1);
            cuadro.attach (combo (datos, pantallas, "render-on-screen", "mouse-pointer-monitor"), 1, fila, 1, 1);
            fila++;
            // Recent apps
            cuadro.attach (etiqueta_fila ("Recent apps:"), 0, fila, 1, 1);
            cuadro.attach (combo (datos, recientes, "show-recent-apps", "0"), 1, fila, 1, 1);
            fila++;

            string[] claves = { "show-menu-icon", "clear-previous-query" };
            string[] textos = { "Show Spotlyte in the menu bar", "Clear the search when Spotlyte loses focus" };
            bool[] defectos = { false, true };
            for (int i = 0; i < 2; i++) {
                var c = new Gtk.CheckButton.with_label (textos[i]);
                var clave = claves[i];
                bool valor = defectos[i];
                if (datos.has_member (clave) && datos.get_member (clave).get_node_type () == Json.NodeType.VALUE) {
                    valor = datos.get_boolean_member (clave);
                }
                c.active = valor;
                c.toggled.connect (() => escribir (clave, new Json.Node (Json.NodeType.VALUE).init_boolean (c.active)));
                cuadro.attach (c, 0, fila, 2, 1);
                fila++;
            }
            caja.pack_start (marco, false, false, 0);

            var nota = new Gtk.Label ("Spotlyte restarts when you change a setting.");
            nota.xalign = 0;
            nota.get_style_context ().add_class ("mp-sd-detalle");
            caja.pack_start (nota, false, false, 0);
            caja.show_all ();
            cargando = false;
            return caja;
        }
    }
}
