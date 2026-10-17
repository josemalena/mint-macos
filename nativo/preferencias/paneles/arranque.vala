/*
 * Startup Disk: elige con qué sistema arranca la computadora (port de PanelStartupDisk en settings/propios.py). La lista sale de las
 * entradas de arranque EFI (efibootmgr, que cualquiera puede leer: Ubuntu/GRUB, Mac OS X…) y escribe el BootOrder; aparte, la entrada
 * por defecto del propio GRUB. Todo cambio lo hace el ayudante de root (settings/startup-disk) por pkexec: el candado pide la clave de
 * administrador una vez, como en Catalina. MINT_STARTUPDISK_PRUEBA=1 usa datos falsos y no toca nada (=2: además, ya desbloqueado).
 */
namespace Preferencias {

    public delegate void ListoAyudante (bool ok, string salida, string error);

    class EntradaEfi {
        public string ident;
        public string nombre;
        public string ruta;
    }

    class HijoArranque : Gtk.FlowBoxChild {
        public string entrada_id = "";
    }

    public class PanelStartupDisk : Panel {
        const string AYUDANTE = "/usr/libexec/mint-macos/startup-disk";
        string? prueba = Environment.get_variable ("MINT_STARTUPDISK_PRUEBA");
        bool desbloqueado = false;
        List<EntradaEfi> entradas = new List<EntradaEfi> ();
        string? actual = null;
        string[] orden = {};
        string? elegida = null;
        bool ignorar_grub = false;
        Gtk.FlowBox fila;
        Gtk.Label seleccion_txt;
        Gtk.Button b_reiniciar;
        Gtk.ComboBoxText combo_grub;
        Gtk.Button b_saved;
        Gtk.Label grub_txt;
        Gtk.Button b_candado;
        Gtk.Image candado_img;
        Gtk.Label candado_txt;

        public PanelStartupDisk () {
            id = "com.apple.preference.startupdisk";
            nombre = "Startup Disk";
            palabras = "startup disk, boot, grub, efi, restart, default os, macos";
        }

        bool es_prueba () {
            return prueba != null && prueba != "";
        }

        // ── los datos ────────────────────────────────────────────────────
        /** Las entradas, BootCurrent y BootOrder de `efibootmgr -v`. */
        void leer_efi () {
            string texto;
            if (es_prueba ()) {
                texto = "BootCurrent: 0000\nBootOrder: 0000,0080\n"
                    + "Boot0000* Ubuntu\tHD(1,GPT,x)/File(\\EFI\\GRUB\\shimx64.efi)\n"
                    + "Boot0080* Mac OS X\tPciRoot(0x0)/File(\\System\\Library\\CoreServices\\boot.efi)\n"
                    + "Boot0082* \tPciRoot(0x0)/File(\\x\\boot.efi)\n";
            } else {
                texto = salida_de_efi ();
            }
            entradas = new List<EntradaEfi> ();
            actual = null;
            orden = {};
            var re = new Regex ("^Boot([0-9A-Fa-f]{4})\\*? ?(.*)$");
            foreach (var linea in texto.split ("\n")) {
                if (linea.has_prefix ("BootCurrent:")) {
                    actual = linea.substring (linea.index_of (":") + 1).strip ().up ();
                } else if (linea.has_prefix ("BootOrder:")) {
                    foreach (var x in linea.substring (linea.index_of (":") + 1).split (",")) {
                        if (x.strip () != "") {
                            orden += x.strip ().up ();
                        }
                    }
                } else {
                    MatchInfo m;
                    if (re.match (linea, 0, out m)) {
                        var resto = m.fetch (2);
                        int t = resto.index_of ("\t");
                        var nom = t >= 0 ? resto.substring (0, t) : resto;
                        var ruta = t >= 0 ? resto.substring (t + 1) : "";
                        if (nom.strip () != "") {
                            var e = new EntradaEfi ();
                            e.ident = m.fetch (1).up ();
                            e.nombre = nom.strip ();
                            e.ruta = ruta;
                            entradas.append (e);
                        }
                    }
                }
            }
        }

        static string salida_de_efi () {
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE, "efibootmgr", "-v");
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                return salida ?? "";
            } catch (Error e) {
                return "";
            }
        }

        static void describir (string ruta, out string detalle, out string icono) {
            var r = ruta.down ();
            if (r.contains ("coreservices") || r.contains ("boot.efi")) {
                detalle = "macOS";
                icono = "drive-harddisk-system";
            } else if (r.contains ("grub") || r.contains ("shim")) {
                detalle = "Linux, GRUB";
                icono = "distributor-logo";
            } else {
                detalle = "EFI";
                icono = "drive-harddisk";
            }
        }

        // ── la página ────────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            leer_efi ();
            elegida = orden.length > 0 ? orden[0] : null;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.get_style_context ().add_class ("mp-propio");
            var titulo = new Gtk.Label ("Select the system you want to use to start up your computer");
            titulo.xalign = 0;
            titulo.get_style_context ().add_class ("mp-sd-titulo");
            caja.pack_start (titulo, false, false, 0);

            // La lista: cuadros de 118×98 con el ícono y dos líneas, sobre fondo oscuro.
            var marco = marco_lista ();
            marco.set_size_request (-1, 98);
            fila = new Gtk.FlowBox ();
            fila.set_selection_mode (Gtk.SelectionMode.SINGLE);
            fila.set_min_children_per_line (4);
            fila.set_max_children_per_line (8);
            fila.set_homogeneous (false);
            fila.halign = Gtk.Align.START;
            fila.valign = Gtk.Align.START;
            fila.get_style_context ().add_class ("mp-sd-fila");
            fila.child_activated.connect ((hijo) => elegir ((hijo as HijoArranque).entrada_id));
            foreach (var e in entradas) {
                string detalle, icono;
                describir (e.ruta, out detalle, out icono);
                var celda = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                celda.set_size_request (110, -1);
                celda.pack_start (new Gtk.Image.from_icon_name (icono, Gtk.IconSize.DIALOG), false, false, 0);
                var n = new Gtk.Label (e.nombre);
                n.get_style_context ().add_class ("mp-sd-nombre");
                celda.pack_start (n, false, false, 0);
                var d = new Gtk.Label (detalle + (e.ident == actual ? ", running" : ""));
                d.get_style_context ().add_class ("mp-sd-detalle");
                celda.pack_start (d, false, false, 0);
                var hijo = new HijoArranque ();
                hijo.entrada_id = e.ident;
                hijo.add (celda);
                fila.add (hijo);
            }
            marco.add (fila);
            caja.pack_start (marco, false, false, 0);

            seleccion_txt = new Gtk.Label ("");
            seleccion_txt.xalign = 0;
            seleccion_txt.get_style_context ().add_class ("mp-sd-detalle");
            seleccion_txt.set_line_wrap (true);
            b_reiniciar = new Gtk.Button.with_label ("Restart…");
            b_reiniciar.set_size_request (151, -1);
            b_reiniciar.clicked.connect (() => reiniciar ());
            var fila_r = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            fila_r.pack_start (seleccion_txt, true, true, 0);
            fila_r.pack_end (b_reiniciar, false, false, 0);
            fila_r.margin_top = 6;
            caja.pack_start (fila_r, false, false, 0);

            // GRUB: la entrada que arranca sola (lo que en Catalina es el modo de disco de destino).
            var sec = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            sec.margin_top = 22;
            var t2 = new Gtk.Label ("Choose the entry GRUB starts by default");
            t2.xalign = 0;
            t2.get_style_context ().add_class ("mp-sd-titulo");
            sec.pack_start (t2, false, false, 0);
            var d2 = new Gtk.Label ("When nothing is chosen at startup, GRUB starts this entry. Unlock the pane to see the list.");
            d2.xalign = 0;
            d2.set_line_wrap (true);
            d2.set_max_width_chars (70);
            d2.get_style_context ().add_class ("mp-sd-detalle");
            sec.pack_start (d2, false, false, 0);
            combo_grub = new Gtk.ComboBoxText ();
            combo_grub.set_sensitive (false);
            combo_grub.changed.connect (() => grub_cambio ());
            b_saved = new Gtk.Button.with_label ("Enable…");
            b_saved.no_show_all = true;
            b_saved.clicked.connect (() => activar_saved ());
            grub_txt = new Gtk.Label ("");
            grub_txt.xalign = 0;
            grub_txt.get_style_context ().add_class ("mp-sd-detalle");
            grub_txt.set_line_wrap (true);
            var fila_g = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            fila_g.pack_start (combo_grub, true, true, 0);
            fila_g.pack_start (b_saved, false, false, 0);
            fila_g.margin_top = 6;
            fila_g.margin_bottom = 6;
            sec.pack_start (fila_g, false, false, 0);
            sec.pack_start (grub_txt, false, false, 0);
            caja.pack_start (sec, false, false, 0);

            // El candado.
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            pie.margin_top = 26;
            b_candado = new Gtk.Button ();
            b_candado.set_relief (Gtk.ReliefStyle.NONE);
            b_candado.get_style_context ().add_class ("mp-sd-candado");
            b_candado.clicked.connect (() => candado ());
            candado_img = new Gtk.Image ();
            b_candado.add (candado_img);
            candado_txt = new Gtk.Label ("");
            candado_txt.xalign = 0;
            candado_txt.get_style_context ().add_class ("mp-sd-detalle");
            pie.pack_start (b_candado, false, false, 0);
            pie.pack_start (candado_txt, false, false, 0);
            caja.pack_start (pie, false, false, 0);

            pintar_candado ();
            pintar_seleccion ();
            // el nombre del que arranca hoy queda marcado
            foreach (var h in fila.get_children ()) {
                if ((h as HijoArranque).entrada_id == elegida) {
                    fila.select_child (h as Gtk.FlowBoxChild);
                }
            }
            caja.show_all ();
            if (prueba == "2") {       // prueba: ya desbloqueado
                Timeout.add (500, () => { candado (); return false; });
            }
            return caja;
        }

        // ── estado ───────────────────────────────────────────────────────
        string nombre_de (string? ident) {
            foreach (var e in entradas) {
                if (e.ident == ident) {
                    return e.nombre;
                }
            }
            return ident ?? "";
        }

        void pintar_candado () {
            var glifo_ = desbloqueado ? "LockUnlocked" : "LockLocked";
            var ruta = Path.build_filename (carpeta_apps (), "glifos", glifo_ + "@1x.png");
            try {
                candado_img.set_from_pixbuf (new Gdk.Pixbuf.from_file (ruta));
            } catch (Error e) {
                candado_img.set_from_icon_name (desbloqueado ? "changes-allow" : "changes-prevent", Gtk.IconSize.LARGE_TOOLBAR);
            }
            candado_txt.set_text (desbloqueado ? "Click the lock to prevent further changes." : "Click the lock to make changes.");
            fila.set_sensitive (desbloqueado);
            var modelo = combo_grub.get_model ();
            int n = 0;
            if (modelo != null) {
                modelo.foreach ((m, p, it) => { n++; return false; });
            }
            combo_grub.set_sensitive (desbloqueado && n > 0);
            b_reiniciar.set_sensitive (desbloqueado && elegida != null);
            b_saved.set_visible (false);
        }

        void pintar_seleccion () {
            if (elegida != null) {
                seleccion_txt.set_text ("You have selected %s.".printf (nombre_de (elegida)));
            } else {
                seleccion_txt.set_text ("");
            }
        }

        // ── el ayudante de root ──────────────────────────────────────────
        /** Corre el ayudante con pkexec sin bloquear la ventana. */
        void ayudante (string[] args, owned ListoAyudante listo) {
            if (es_prueba ()) {
                stderr.printf ("[prueba] ayudante: %s\n", string.joinv (" ", args));
                string falso = "";
                if (args[0] == "grub-list") {
                    falso = "{\"entries\": [{\"id\": \"0\", \"title\": \"Linux Mint 22.2 Cinnamon\"}, {\"id\": \"1>0\", \"title\": \"Advanced options > Linux 6.8\"}, "
                        + "{\"id\": \"2\", \"title\": \"UEFI Firmware Settings\"}], \"default\": \"saved\", \"saved_entry\": \"0\"}";
                }
                Idle.add (() => { listo (true, falso, ""); return false; });
                return;
            }
            if (!FileUtils.test (AYUDANTE, FileTest.EXISTS)) {
                Idle.add (() => { listo (false, "", "missing"); return false; });
                return;
            }
            string[] cmd = { "pkexec", AYUDANTE };
            foreach (var a in args) {
                cmd += a;
            }
            try {
                var proc = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
                proc.communicate_utf8_async.begin (null, null, (o, r) => {
                    try {
                        string? salida, error;
                        proc.communicate_utf8_async.end (r, out salida, out error);
                        listo (proc.get_exit_status () == 0, salida ?? "", (error ?? "").strip ());
                    } catch (Error e) {
                        listo (false, "", e.message);
                    }
                });
            } catch (Error e) {
                var msg = e.message;
                Idle.add (() => { listo (false, "", msg); return false; });
            }
        }

        void sin_ayudante () {
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.INFO, Gtk.ButtonsType.OK, "%s",
                                           "Startup Disk needs its helper installed.");
            d.format_secondary_text ("Run this once in a terminal, then try again:\n\nsudo %s",
                                     Path.build_filename (carpeta_python (), "startup-disk", "instalar-root.sh"));
            d.run ();
            d.destroy ();
        }

        void mostrar_error (string titulo, string detalle) {
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "%s", titulo);
            d.format_secondary_text ("%s", detalle);
            d.run ();
            d.destroy ();
        }

        // ── acciones ─────────────────────────────────────────────────────
        void candado () {
            if (desbloqueado) {
                desbloqueado = false;
                pintar_candado ();
                return;
            }
            ayudante ({ "auth" }, (ok, o, err) => {
                if (!ok) {
                    if (err == "missing") {
                        sin_ayudante ();
                    }
                    return;
                }
                desbloqueado = true;
                pintar_candado ();
                cargar_grub ();
            });
        }

        void elegir (string ident) {
            if (!desbloqueado || ident == elegida) {
                return;
            }
            var previo = elegida;
            ayudante ({ "efi-order", ident }, (ok, o, err) => {
                if (ok) {
                    elegida = ident;
                } else {
                    elegida = previo;
                    mostrar_error ("The startup disk was not changed.", err != "" ? err : "The helper failed.");
                    foreach (var h in fila.get_children ()) {
                        if ((h as HijoArranque).entrada_id == previo) {
                            fila.select_child (h as Gtk.FlowBoxChild);
                        }
                    }
                }
                pintar_seleccion ();
                b_reiniciar.set_sensitive (elegida != null);
            });
        }

        void reiniciar () {
            if (elegida == null) {
                return;
            }
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.NONE, "%s",
                                           "Are you sure you want to restart?");
            d.format_secondary_text ("Your computer will start up using %s.", nombre_de (elegida));
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            d.add_button ("Restart", Gtk.ResponseType.OK);
            d.set_default_response (Gtk.ResponseType.OK);
            var r = d.run ();
            d.destroy ();
            if (r != Gtk.ResponseType.OK) {
                return;
            }
            var destino = elegida;
            ayudante ({ "efi-next", destino }, (ok, o, err) => {
                if (!ok) {
                    mostrar_error ("The computer could not be restarted.", err != "" ? err : "The helper failed.");
                    return;
                }
                if (es_prueba ()) {
                    stderr.printf ("[prueba] systemctl reboot\n");
                } else {
                    try {
                        Process.spawn_async (null, { "systemctl", "reboot" }, null, SpawnFlags.SEARCH_PATH, null, null);
                    } catch (Error e) {
                    }
                }
            });
        }

        void cargar_grub () {
            ayudante ({ "grub-list" }, (ok, salida, err) => {
                if (!ok) {
                    grub_txt.set_text (err != "missing" ? "The GRUB menu could not be read." : "");
                    return;
                }
                try {
                    var p = new Json.Parser ();
                    p.load_from_data (salida);
                    var datos = p.get_root ().get_object ();
                    ignorar_grub = true;
                    combo_grub.remove_all ();
                    var entradas_json = datos.get_array_member ("entries");
                    for (uint i = 0; i < entradas_json.get_length (); i++) {
                        var e = entradas_json.get_object_element (i);
                        combo_grub.append (e.get_string_member ("id"), e.get_string_member ("title"));
                    }
                    bool salvado = datos.has_member ("default") && datos.get_string_member ("default") == "saved";
                    if (salvado) {
                        var guardada = datos.has_member ("saved_entry") ? datos.get_string_member ("saved_entry") : "";
                        combo_grub.set_active_id (guardada != "" ? guardada : "0");
                    }
                    ignorar_grub = false;
                    b_saved.set_visible (!salvado);
                    grub_txt.set_text (salvado ? "" : "GRUB is not set to remember a default. Enable it to choose one here.");
                    combo_grub.set_sensitive (salvado);
                } catch (Error e) {
                    ignorar_grub = false;
                }
            });
        }

        void activar_saved () {
            ayudante ({ "grub-enable-saved" }, (ok, o, err) => {
                if (!ok) {
                    mostrar_error ("GRUB could not be changed.", err != "" ? err : "The helper failed.");
                    return;
                }
                cargar_grub ();
            });
        }

        void grub_cambio () {
            var ident = combo_grub.get_active_id ();
            if (ignorar_grub || ident == null || ident == "" || !desbloqueado) {
                return;
            }
            ayudante ({ "grub-default", ident }, (ok, o, err) => {
                if (!ok) {
                    mostrar_error ("The default entry was not changed.", err != "" ? err : "The helper failed.");
                }
            });
        }
    }
}
