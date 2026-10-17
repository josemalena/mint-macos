/*
 * Sharing: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.52 PM Printer Sharing, 1.22.59 Screen Sharing, 1.23.05 File
 * Sharing, 1.23.09 Remote Login; el resto de los servicios en 1.22.56 … 1.23.21); port de settings/compartir.py.
 *
 * Con equivalente real, por un ayudante de root con polkit (settings/sharing/, como Startup Disk):
 *   Remote Login     ssh.socket / ssh.service
 *   File Sharing     smbd (Samba)
 *   Printer Sharing  cupsctl --share-printers
 * Su estado se lee sin root (systemctl is-active, cupsctl). El Computer Name es el nombre bonito del equipo (hostnamectl --pretty).
 * Sin equivalente (en gris): DVD or CD Sharing, Screen Sharing (x11vnc está instalado pero sin servicio), Media Sharing, Remote
 * Management, Bluetooth Sharing, Remote Apple Events, Internet Sharing, Content Caching, Allow access for…, las carpetas y los
 * usuarios de File Sharing y Edit… Las pantallas de «Off» de cada servicio y la hoja Edit… no tienen captura.
 */
namespace Preferencias {

    /** Lo que imprime un comando (sin errores), o "" si no se pudo correr. */
    public string salida_de (string[] cmd) {
        try {
            var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            string? salida;
            p.communicate_utf8 (null, null, out salida, null);
            return (salida ?? "").strip ();
        } catch (Error e) {
            return "";
        }
    }

    public class PanelSharing : Panel {
        const string AYUDANTE = "/usr/libexec/mint-macos/sharing";
        // (nombre en Catalina, clave del ayudante o "")
        const string[] NOMBRES = { "DVD or CD Sharing", "Screen Sharing", "Media Sharing", "File Sharing", "Printer Sharing",
                                   "Remote Login", "Remote Management", "Bluetooth Sharing", "Remote Apple Events",
                                   "Internet Sharing", "Content Caching" };
        const string[] CLAVES = { "", "", "", "file-sharing", "printer-sharing", "remote-login", "", "", "", "", "" };
        // MINT_COMPARTIR_PRUEBA: solo lee: no enciende ni apaga nada.
        bool prueba = Environment.get_variable ("MINT_COMPARTIR_PRUEBA") != null;
        bool cargando = false;
        Gtk.ListStore servicios;
        Gtk.TreeView arbol;
        Gtk.Box detalle;
        Gtk.Entry nombre_pc;

        public PanelSharing () {
            id = "com.apple.preferences.sharing";
            nombre = "Sharing";
            palabras = "sharing, remote login, ssh, file sharing, samba, printer sharing, screen sharing, computer name";
        }

        static bool encendido (string clave) {
            if (clave == "remote-login") {
                return salida_de ({ "systemctl", "is-active", "ssh.socket" }) == "active"
                    || salida_de ({ "systemctl", "is-active", "ssh.service" }) == "active";
            }
            if (clave == "file-sharing") {
                return salida_de ({ "systemctl", "is-active", "smbd.service" }) == "active";
            }
            if (clave == "printer-sharing") {
                return "_share_printers=1" in salida_de ({ "cupsctl" });
            }
            return false;
        }

        public override Gtk.Widget? construir () {
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 16, 16, 16, 16);
            // Computer Name
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 6;
            g.halign = Gtk.Align.CENTER;
            g.attach (etiqueta_fila ("Computer Name:"), 0, 0, 1, 1);
            var estatico = salida_de ({ "hostnamectl", "--static" });
            if (estatico == "") {
                estatico = "localhost";
            }
            var bonito = salida_de ({ "hostnamectl", "--pretty" });
            if (bonito == "") {
                bonito = estatico;
            }
            nombre_pc = new Gtk.Entry ();
            nombre_pc.text = bonito;
            nombre_pc.width_chars = 40;
            nombre_pc.activate.connect (() => poner_nombre (nombre_pc.get_text ()));
            g.attach (nombre_pc, 1, 0, 2, 1);
            var d = new Gtk.Label ("Computers on your local network can access your computer at:\n%s.local".printf (estatico));
            d.xalign = 0;
            d.get_style_context ().add_class ("mp-sd-detalle");
            g.attach (d, 1, 1, 1, 1);
            g.attach (gris (new Gtk.Button.with_label ("Edit…")), 2, 1, 1, 1);
            caja.pack_start (g, false, false, 0);

            // La lista de servicios y su detalle
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            var izq = marco_lista ();
            servicios = new Gtk.ListStore (4, typeof (bool), typeof (string), typeof (string), typeof (bool));    // encendido, nombre, clave, ¿se puede?
            for (int i = 0; i < NOMBRES.length; i++) {
                Gtk.TreeIter it;
                servicios.append (out it);
                servicios.set (it, 0, CLAVES[i] != "" ? encendido (CLAVES[i]) : false, 1, NOMBRES[i], 2, CLAVES[i], 3, CLAVES[i] != "");
            }
            arbol = new Gtk.TreeView.with_model (servicios);
            arbol.set_size_request (190, 270);
            var ck = new Gtk.CellRendererToggle ();
            ck.toggled.connect ((ruta) => conmutar (ruta));
            var col = new Gtk.TreeViewColumn.with_attributes ("On", ck, "active", 0, "activatable", 3, "sensitive", 3, null);
            arbol.append_column (col);
            arbol.append_column (new Gtk.TreeViewColumn.with_attributes ("Service", new Gtk.CellRendererText (), "text", 1, null));
            arbol.get_selection ().changed.connect (() => elegido ());
            izq.add (arbol);
            cuerpo.pack_start (izq, false, false, 0);
            detalle = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            cuerpo.pack_start (detalle, true, true, 0);
            caja.pack_start (cuerpo, true, true, 0);
            caja.show_all ();
            var pedido = Environment.get_variable ("MINT_COMPARTIR_SERVICIO");      // solo para las pruebas visuales
            int indice = 5;                                                           // Remote Login
            for (int i = 0; i < NOMBRES.length; i++) {
                if (pedido != null ? NOMBRES[i] == pedido : NOMBRES[i] == "Remote Login") {
                    indice = i;
                }
            }
            arbol.get_selection ().select_path (new Gtk.TreePath.from_indices (indice));
            cargando = false;
            return caja;
        }

        // ── detalle de cada servicio ─────────────────────────────────────
        void elegido () {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!arbol.get_selection ().get_selected (out modelo, out it)) {
                return;
            }
            bool on;
            string nombre_s, clave;
            modelo.get (it, 0, out on, 1, out nombre_s, 2, out clave, -1);
            foreach (var h in detalle.get_children ()) {
                detalle.remove (h);
            }
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var punto = new Gtk.Label (null);
            punto.set_markup ("<span foreground=\"%s\">●</span>".printf (on ? "#37c94b" : "#8a8a8e"));
            cab.pack_start (punto, false, false, 0);
            var t = new Gtk.Label ("%s: %s".printf (nombre_s, on ? "On" : "Off"));
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            cab.pack_start (t, false, false, 0);
            detalle.pack_start (cab, false, false, 0);
            var host = salida_de ({ "hostnamectl", "--static" });
            if (host == "") {
                host = "localhost";
            }
            var usuario = Environment.get_variable ("USER") ?? "user";
            if (clave == "remote-login") {
                texto ("To log in to this computer remotely, type “ssh %s@%s.local”.".printf (usuario, host));
                acceso ();
            } else if (clave == "file-sharing") {
                texto ("Other users can access shared folders on this computer at “smb://%s.local”.".printf (host));
                carpetas_smb ();
            } else if (clave == "printer-sharing") {
                texto ("Printer Sharing allows others on your network to use printers connected to this computer.");
                impresoras ();
            } else {
                texto ("This service is not available on this computer.");
            }
            detalle.show_all ();
        }

        void texto (string s) {
            var t = new Gtk.Label (s);
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (60);
            t.get_style_context ().add_class ("mp-sd-detalle");
            detalle.pack_start (t, false, false, 0);
        }

        void acceso () {
            var sep = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            sep.margin_top = 8;
            sep.margin_bottom = 8;
            detalle.pack_start (sep, false, false, 0);
            var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            f.pack_start (new Gtk.Label ("Allow access for:"), false, false, 0);
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var todos = new Gtk.RadioButton.with_label_from_widget (null, "All users");
            var solo = new Gtk.RadioButton.with_label_from_widget (todos, "Only these users:");
            todos.active = true;
            gris_con (todos, "Access is controlled by sshd on this computer.");
            c.pack_start (todos, false, false, 0);
            c.pack_start (gris (solo), false, false, 0);
            f.pack_start (c, false, false, 0);
            detalle.pack_start (f, false, false, 0);
        }

        static Gtk.Widget gris_con (Gtk.Widget w, string motivo) {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        void carpetas_smb () {
            var marco = marco_lista ();
            marco.set_size_request (-1, 120);
            var lista = new Gtk.ListStore (1, typeof (string));
            foreach (var linea in salida_de ({ "testparm", "-s", "--suppress-prompt" }).split ("\n")) {
                var l = linea.strip ();
                if (l.length > 2 && l.has_prefix ("[") && l.has_suffix ("]")) {
                    var n = l.substring (1, l.length - 2);
                    if (n != "global" && n != "printers" && n != "print$") {
                        Gtk.TreeIter it;
                        lista.append (out it);
                        lista.set (it, 0, n, -1);
                    }
                }
            }
            var a = new Gtk.TreeView.with_model (lista);
            a.headers_visible = false;
            a.append_column (new Gtk.TreeViewColumn.with_attributes ("", new Gtk.CellRendererText (), "text", 0, null));
            marco.add (a);
            var sf = new Gtk.Label ("Shared Folders:");
            sf.xalign = 0;
            detalle.pack_start (sf, false, false, 0);
            detalle.pack_start (gris_con (marco, "Edit /etc/samba/smb.conf to change shared folders."), true, true, 0);
        }

        void impresoras () {
            var pl = new Gtk.Label ("Printers:");
            pl.xalign = 0;
            detalle.pack_start (pl, false, false, 0);
            var marco = marco_lista ();
            marco.set_size_request (-1, 100);
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            caja.margin = 6;
            foreach (var linea in salida_de ({ "lpstat", "-p" }).split ("\n")) {
                if (linea.has_prefix ("printer ")) {
                    var resto = linea.substring (8);
                    int fin = resto.index_of (" ");
                    var nom = fin > 0 ? resto.substring (0, fin) : resto;
                    var c = new Gtk.CheckButton.with_label (nom);
                    c.active = true;
                    caja.pack_start (gris_con (c, "Every printer is shared when Printer Sharing is on."), false, false, 0);
                }
            }
            marco.add (caja);
            detalle.pack_start (marco, false, false, 0);
        }

        // ── encender y apagar ────────────────────────────────────────────
        void conmutar (string ruta) {
            Gtk.TreeIter it;
            if (!servicios.get_iter_from_string (out it, ruta)) {
                return;
            }
            bool on, se_puede;
            string nombre_s, clave;
            servicios.get (it, 0, out on, 1, out nombre_s, 2, out clave, 3, out se_puede, -1);
            if (cargando || !se_puede) {
                return;
            }
            bool quiere = !on;
            if (prueba) {
                return;
            }
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE, "pkexec", AYUDANTE, clave,
                                        quiere ? "on" : "off");
                string? salida, error;
                p.communicate_utf8 (null, null, out salida, out error);
                int codigo = p.get_exit_status ();
                if (codigo != 0 && codigo != 126 && codigo != 127) {
                    var msg = ((error ?? "") != "" ? error : ((salida ?? "") != "" ? salida : "The change was not applied.")).strip ();
                    aviso ("%s: %s".printf (nombre_s, msg));
                }
            } catch (Error e) {
                aviso ("%s: %s".printf (nombre_s, e.message));
            }
            servicios.set (it, 0, encendido (clave), -1);
            elegido ();
        }

        void poner_nombre (string t) {
            var texto = t.strip ();
            if (texto == "" || prueba) {
                return;
            }
            try {
                var p = new Subprocess (SubprocessFlags.NONE, "hostnamectl", "set-hostname", "--pretty", texto);
                p.wait ();
            } catch (Error e) {
            }
        }

        void aviso (string texto) {
            var d = new Gtk.MessageDialog (ventana, Gtk.DialogFlags.MODAL, Gtk.MessageType.WARNING, Gtk.ButtonsType.OK, "%s", texto);
            d.run ();
            d.destroy ();
        }
    }
}
