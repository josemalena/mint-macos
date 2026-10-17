/*
 * Printers & Scanners: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.47 PM); port de settings/impresoras.py.
 *
 * La lista, el estado, Location, Kind y la impresora predeterminada salen de CUPS (lpstat, lpoptions); «Share this printer on the
 * network» es printer-is-shared (lpadmin, el usuario está en el grupo lpadmin); Open Print Queue… y Options & Supplies… abren
 * system-config-printer en esa impresora; el «+» abre system-config-printer para añadir una. Sin equivalente (en gris): Default
 * paper size, y la lista de escáneres (no hay captura de la lista con escáneres).
 * La ventana de añadir impresora, la cola y las hojas de opciones de Catalina no tienen captura.
 */
namespace Preferencias {

    class DatosImpresora {
        public string nombre = "";
        public string estado = "Idle";
        public string descripcion = "";
        public string lugar = "";
        public string conexion = "";
    }

    class FilaImpresora : Gtk.ListBoxRow {
        public DatosImpresora p;
    }

    public class PanelPrinters : Panel {
        // MINT_IMPRESORAS_PRUEBA: solo lee: no cambia nada en CUPS.
        bool prueba = Environment.get_variable ("MINT_IMPRESORAS_PRUEBA") != null;
        bool cargando = false;
        Gtk.ListBox lista;
        Gtk.Frame der;
        Gtk.ComboBoxText pred;

        public PanelPrinters () {
            id = "com.apple.preference.printfax";
            nombre = "Printers & Scanners";
            palabras = "printers, scanners, print, printer, default printer, queue, sharing";
        }

        /** Lo que imprime un comando con el entorno en inglés (los textos de lpstat se leen en inglés). */
        static string salida_c (string[] cmd) {
            try {
                var l = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                l.setenv ("LC_ALL", "C", true);
                var p = l.spawnv (cmd);
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                return salida ?? "";
            } catch (Error e) {
                return "";
            }
        }

        /** [{nombre, estado, descripcion, lugar, conexion}] de `lpstat -l -p`. */
        static List<DatosImpresora> impresoras () {
            var salida = salida_c ({ "lpstat", "-l", "-p" });
            var lista = new List<DatosImpresora> ();
            DatosImpresora? actual = null;
            foreach (var linea in salida.split ("\n")) {
                if (linea.has_prefix ("printer ")) {
                    var resto = linea.substring (8);
                    int i = resto.index_of (" ");
                    if (i <= 0) {
                        continue;
                    }
                    var texto = resto.substring (i + 1);
                    bool fuera = texto.contains ("disabled") || texto.contains ("not accepting");
                    actual = new DatosImpresora ();
                    actual.nombre = resto.substring (0, i);
                    actual.estado = fuera ? "Offline" : (texto.contains ("now printing") ? "Printing" : "Idle");
                    lista.append (actual);
                } else if (actual != null) {
                    var l = linea.strip ();
                    int i = l.index_of (":");
                    if (i < 0) {
                        continue;
                    }
                    var k = l.substring (0, i);
                    var v = l.substring (i + 1).strip ();
                    if (k == "Description") {
                        actual.descripcion = v;
                    } else if (k == "Location") {
                        actual.lugar = v;
                    } else if (k == "Connection") {
                        actual.conexion = v;
                    }
                }
            }
            return lista;
        }

        static string predeterminada () {
            var s = salida_c ({ "lpstat", "-d" });
            int i = s.index_of ("destination: ");
            if (i < 0) {
                return "";
            }
            var resto = s.substring (i + 13);
            int fin = resto.index_of_char ('\n');
            return (fin >= 0 ? resto.substring (0, fin) : resto).strip ();
        }

        const string PRUEBA_IPP = "{\n  OPERATION Get-Printer-Attributes\n  GROUP operation-attributes-tag\n"
            + "  ATTR charset attributes-charset utf-8\n  ATTR language attributes-natural-language en\n"
            + "  ATTR uri printer-uri $uri\n  ATTR keyword requested-attributes printer-make-and-model,printer-is-shared\n"
            + "  DISPLAY printer-make-and-model\n  DISPLAY printer-is-shared\n}\n";

        /** Dos valores CSV de una línea («"EPSON Printer, driverless, 2.0.0",false»). */
        static string[] campos_csv (string linea) {
            string[] campos = {};
            var actual = new StringBuilder ();
            bool entre_comillas = false;
            for (int i = 0; i < linea.length; i++) {
                char c = linea[i];
                if (c == '"') {
                    if (entre_comillas && i + 1 < linea.length && linea[i + 1] == '"') {
                        actual.append_c ('"');
                        i++;
                    } else {
                        entre_comillas = !entre_comillas;
                    }
                } else if (c == ',' && !entre_comillas) {
                    campos += actual.str;
                    actual.truncate (0);
                } else {
                    actual.append_c (c);
                }
            }
            campos += actual.str;
            return campos;
        }

        /**
         * printer-make-and-model («Kind» en Catalina) y printer-is-shared de CUPS por IPP, con ipptool: lo mismo que da pycups. Los
         * dos valores salen vacíos si no se puede saber.
         */
        static void atributos_ipp (string impresora, out string modelo, out bool compartida) {
            modelo = "";
            compartida = false;
            var carpeta = Path.build_filename (Environment.get_home_dir (), ".cache", "mint-macos");
            var archivo = Path.build_filename (carpeta, "impresora-ipp.test");
            try {
                if (!FileUtils.test (archivo, FileTest.EXISTS)) {
                    DirUtils.create_with_parents (carpeta, 0755);
                    FileUtils.set_contents (archivo, PRUEBA_IPP);
                }
            } catch (Error e) {
                return;
            }
            var salida = salida_c ({ "ipptool", "-c", "ipp://localhost/printers/" + impresora, archivo });
            var lineas = salida.split ("\n");
            if (lineas.length < 2) {
                return;
            }
            var c = campos_csv (lineas[1]);
            if (c.length >= 2) {
                modelo = c[0];
                compartida = c[1].strip () == "true";
            }
        }

        public override Gtk.Widget? construir () {
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 16, 16, 16, 16);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var marco = marco_lista ();
            lista = new Gtk.ListBox ();
            lista.set_size_request (200, 240);
            lista.row_selected.connect ((f) => detalle_de (f as FilaImpresora));
            marco.add (lista);
            izq.pack_start (marco, true, true, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            var mas = new Gtk.Button.with_label ("+");
            mas.clicked.connect (() => lanzar_scp ({}));
            var menos = new Gtk.Button.with_label ("−");
            menos.set_sensitive (false);
            menos.set_tooltip_text ("Use system-config-printer to remove a printer.");
            botones.pack_start (mas, false, false, 0);
            botones.pack_start (menos, false, false, 0);
            botones.margin_top = 4;
            botones.margin_bottom = 4;
            izq.pack_start (botones, false, false, 0);
            cuerpo.pack_start (izq, false, false, 0);
            der = marco_lista ();
            cuerpo.pack_start (der, true, true, 0);
            caja.pack_start (cuerpo, true, true, 0);

            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 8;
            g.halign = Gtk.Align.CENTER;
            g.attach (etiqueta_fila ("Default printer:"), 0, 0, 1, 1);
            pred = new Gtk.ComboBoxText ();
            pred.changed.connect (() => poner_predeterminada (pred.get_active_id ()));
            g.attach (pred, 1, 0, 1, 1);
            g.attach (etiqueta_fila ("Default paper size:"), 0, 1, 1, 1);
            var papel = new Gtk.ComboBoxText ();
            papel.append ("a4", "A4");
            papel.set_active (0);
            papel.set_sensitive (false);
            papel.set_tooltip_text ("The paper size is set by each printer on this computer.");
            g.attach (papel, 1, 1, 1, 1);
            caja.pack_start (g, false, false, 0);

            var todas = impresoras ();
            var por_defecto = predeterminada ();
            foreach (var p in todas) {
                var fila = new FilaImpresora ();
                fila.p = p;
                var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                h.margin = 6;
                h.pack_start (new Gtk.Image.from_icon_name ("printer", Gtk.IconSize.LARGE_TOOLBAR), false, false, 0);
                var v = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                var nom = new Gtk.Label (p.descripcion != "" ? p.descripcion : p.nombre);
                nom.xalign = 0;
                v.pack_start (nom, false, false, 0);
                var s = new Gtk.Label ("%s%s".printf (p.estado, p.nombre == por_defecto ? ", Default" : ""));
                s.xalign = 0;
                s.get_style_context ().add_class ("mp-sd-detalle");
                v.pack_start (s, false, false, 0);
                h.pack_start (v, true, true, 0);
                fila.add (h);
                lista.add (fila);
                pred.append (p.nombre, p.descripcion != "" ? p.descripcion : p.nombre);
            }
            if (por_defecto != "") {
                pred.set_active_id (por_defecto);
            }
            caja.show_all ();
            if (todas.length () > 0) {
                lista.select_row (lista.get_row_at_index (0));
            }
            cargando = false;
            return caja;
        }

        void detalle_de (FilaImpresora? fila) {
            foreach (var h in der.get_children ()) {
                der.remove (h);
            }
            if (fila == null) {
                return;
            }
            var p = fila.p;
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            caja.margin = 16;
            caja.pack_start (imagen_icono_panel (id, 96), false, false, 0);
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var t = new Gtk.Label (p.descripcion != "" ? p.descripcion : p.nombre);
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            c.pack_start (t, false, false, 0);
            var cola = new Gtk.Button.with_label ("Open Print Queue…");
            cola.clicked.connect (() => lanzar_scp ({ "--show-jobs", p.nombre }));
            var opciones = new Gtk.Button.with_label ("Options & Supplies…");
            opciones.clicked.connect (() => lanzar_scp ({}));
            c.pack_start (cola, false, false, 0);
            c.pack_start (opciones, false, false, 0);
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 4;
            g.margin_top = 12;
            g.margin_bottom = 12;
            string[] ks = { "Location:", "Kind:", "Status:" };
            string modelo;
            bool esta_compartida;
            atributos_ipp (p.nombre, out modelo, out esta_compartida);
            string[] vs = { p.lugar, modelo, p.estado };
            for (int i = 0; i < 3; i++) {
                var e = new Gtk.Label (ks[i]);
                e.xalign = 1.0f;
                e.get_style_context ().add_class ("mp-sd-detalle");
                g.attach (e, 0, i, 1, 1);
                var val = new Gtk.Label (vs[i]);
                val.xalign = 0;
                g.attach (val, 1, i, 1, 1);
            }
            c.pack_start (g, false, false, 0);
            var compartir = new Gtk.CheckButton.with_label ("Share this printer on the network");
            compartir.active = esta_compartida;
            compartir.toggled.connect (() => compartir_impresora (p.nombre, compartir.active));
            c.pack_start (compartir, false, false, 0);
            caja.pack_start (c, true, true, 0);
            der.add (caja);
            der.show_all ();
        }

        // ── acciones ─────────────────────────────────────────────────────
        void lanzar_scp (string[] args) {
            if (prueba) {
                return;
            }
            string[] cmd = { "system-config-printer" };
            foreach (var a in args) {
                cmd += a;
            }
            try {
                Process.spawn_async (null, cmd, null,
                                     SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                     () => { Posix.setsid (); }, null);
            } catch (Error e) {
            }
        }

        void poner_predeterminada (string? nom) {
            if (cargando || prueba || nom == null || nom == "") {
                return;
            }
            salida_c ({ "lpadmin", "-d", nom });
        }

        void compartir_impresora (string nom, bool si) {
            if (cargando || prueba) {
                return;
            }
            salida_c ({ "lpadmin", "-p", nom, "-o", "printer-is-shared=%s".printf (si ? "true" : "false") });
        }
    }
}
