/*
 * Network: el panel de Catalina (Screen Shot 2026-10-14 at 1.18.49 PM, Ethernet); port de settings/red.py.
 *
 * Los servicios de la izquierda son los dispositivos de NetworkManager (Ethernet, Wi-Fi, Bluetooth PAN, VLAN) con su punto verde o
 * rojo; a la derecha, el estado, la IP, la máscara, el router, el DNS, los dominios de búsqueda y la IPv6, leídos con nmcli.
 * Advanced… abre la hoja de Catalina (todavía en el System Preferences de Python: red_avanzado.py); sin conexión de NetworkManager,
 * nm-connection-editor. En Wi-Fi, Turn Wi-Fi On/Off enciende y apaga la radio (nmcli radio wifi).
 * Sin equivalente (en gris): Location, Configure IPv4 (se muestra el método actual: cambiarlo se hace en Advanced…), +, −, el
 * engranaje, Revert y Apply. No hay captura de Wi-Fi escogido ni de la hoja + ni del menú ⚙.
 */
namespace Preferencias {

    class DispositivoRed {
        public string dev = "";
        public string tipo = "";
        public string nombre = "";
        public string estado = "";
        public string conexion = "";
    }

    class FilaRed : Gtk.ListBoxRow {
        public DispositivoRed d;
    }

    public class PanelNetwork : Panel {
        // MINT_RED_PRUEBA: solo lee: no enciende ni apaga el Wi-Fi.
        bool prueba = Environment.get_variable ("MINT_RED_PRUEBA") != null;
        uint temporizador = 0;
        Gtk.ListBox lista;
        Gtk.Frame der;
        DispositivoRed? seleccion = null;

        public PanelNetwork () {
            id = "com.apple.preference.network";
            nombre = "Network";
            palabras = "network, ethernet, wi-fi, wifi, ip address, dns, router, vpn, proxy, dhcp, bluetooth pan";
        }

        static string nombre_de_tipo (string tipo) {
            switch (tipo) {
            case "ethernet": return "Ethernet";
            case "wifi": return "Wi-Fi";
            case "bluetooth": return "Bluetooth PAN";
            case "vlan": return "VLAN";
            }
            return "";
        }

        static string icono_de_tipo (string tipo) {
            switch (tipo) {
            case "ethernet": return "network-wired-symbolic";
            case "wifi": return "network-wireless-symbolic";
            case "bluetooth": return "bluetooth-symbolic";
            }
            return "network-wired-symbolic";
        }

        static string nmcli (string[] args) {
            string[] cmd = { "nmcli" };
            foreach (var a in args) {
                cmd += a;
            }
            return salida_de_sin_recorte (cmd);
        }

        /** La salida tal cual, sin quitar espacios (nmcli -g puede traer líneas vacías con sentido). */
        static string salida_de_sin_recorte (string[] cmd) {
            try {
                var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                return salida ?? "";
            } catch (Error e) {
                return "";
            }
        }

        /** Los dispositivos de los tipos que Catalina llama servicios. */
        static List<DispositivoRed> dispositivos () {
            var salida = new List<DispositivoRed> ();
            var vistos = new HashTable<string, int> (str_hash, str_equal);
            foreach (var linea in nmcli ({ "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status" }).split ("\n")) {
                var partes = linea.split (":");
                if (partes.length < 4 || nombre_de_tipo (partes[1]) == "") {
                    continue;
                }
                var d = new DispositivoRed ();
                d.dev = partes[0];
                d.tipo = partes[1];
                d.estado = partes[2];
                d.conexion = string.joinv (":", partes[3:partes.length]);
                int n = (vistos.contains (d.tipo) ? vistos[d.tipo] : 0) + 1;
                vistos[d.tipo] = n;
                d.nombre = nombre_de_tipo (d.tipo) + (n > 1 ? " %d".printf (n) : "");
                salida.append (d);
            }
            return salida;
        }

        /** Los campos de `nmcli device show` como {clave: [valores]}. */
        static HashTable<string, GenericArray<string>> detalle (string dev) {
            var d = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
            foreach (var linea in nmcli ({ "-t", "device", "show", dev }).split ("\n")) {
                int i = linea.index_of (":");
                if (i < 0) {
                    continue;
                }
                var k = linea.substring (0, i);
                var v = linea.substring (i + 1);
                int c = k.index_of ("[");
                if (c >= 0) {
                    k = k.substring (0, c);
                }
                if (!d.contains (k)) {
                    d[k] = new GenericArray<string> ();
                }
                d[k].add (v);
            }
            return d;
        }

        static string primero (HashTable<string, GenericArray<string>> info, string clave) {
            var v = info[clave];
            return (v != null && v.length > 0) ? v[0] : "";
        }

        static string unidos (HashTable<string, GenericArray<string>> info, string clave) {
            var v = info[clave];
            if (v == null) {
                return "";
            }
            var sb = new StringBuilder ();
            for (int i = 0; i < v.length; i++) {
                if (i > 0) {
                    sb.append (", ");
                }
                sb.append (v[i]);
            }
            return sb.str;
        }

        static string mascara (int prefijo) {
            uint32 bits = 0;
            if (prefijo >= 32) {
                bits = uint32.MAX;
            } else if (prefijo > 0) {
                uint64 todo = 0xFFFFFFFF;
                bits = (uint32) ((todo << (32 - prefijo)) & 0xFFFFFFFF);
            }
            return "%u.%u.%u.%u".printf ((bits >> 24) & 255, (bits >> 16) & 255, (bits >> 8) & 255, bits & 255);
        }

        static Gtk.Widget gris_red (Gtk.Widget w, string motivo = "Not available on this computer.") {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 14, 14, 14, 14);
            var loc = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            loc.halign = Gtk.Align.CENTER;
            loc.pack_start (new Gtk.Label ("Location:"), false, false, 0);
            var combo = new Gtk.ComboBoxText ();
            combo.append ("a", "Automatic");
            combo.set_active (0);
            loc.pack_start (gris_red (combo, "Network locations do not exist on this computer."), false, false, 0);
            caja.pack_start (loc, false, false, 0);

            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            lista = new Gtk.ListBox ();
            lista.set_size_request (230, 270);
            lista.row_selected.connect ((f) => mostrar (f as FilaRed));
            var ml = marco_lista ();
            ml.add (lista);
            izq.pack_start (ml, true, true, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var t in new string[] { "+", "−", "⚙" }) {
                botones.pack_start (gris_red (new Gtk.Button.with_label (t), "Use Advanced… to edit the connections."), false, false, 0);
            }
            botones.margin_top = 4;
            botones.margin_bottom = 4;
            izq.pack_start (botones, false, false, 0);
            cuerpo.pack_start (izq, false, false, 0);
            der = marco_lista ();
            cuerpo.pack_start (der, true, true, 0);
            caja.pack_start (cuerpo, true, true, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            pie.pack_end (gris_red (new Gtk.Button.with_label ("Apply")), false, false, 0);
            pie.pack_end (gris_red (new Gtk.Button.with_label ("Revert")), false, false, 0);
            caja.pack_start (pie, false, false, 0);
            rellenar ();
            caja.show_all ();
            temporizador = Timeout.add_seconds (5, refrescar);
            caja.destroy.connect (() => {
                if (temporizador != 0) {
                    Source.remove (temporizador);
                    temporizador = 0;
                }
            });
            return caja;
        }

        // ── la lista y el detalle ────────────────────────────────────────
        void rellenar () {
            var elegido = lista.get_selected_row () as FilaRed;
            var previo = elegido != null ? elegido.d.dev : null;
            foreach (var f in lista.get_children ()) {
                lista.remove (f);
            }
            foreach (var d in dispositivos ()) {
                var fila = new FilaRed ();
                fila.d = d;
                var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                h.margin = 6;
                bool conectado = d.estado.has_prefix ("connected");
                var punto = new Gtk.Label (null);
                punto.set_markup ("<span foreground=\"%s\">●</span>".printf (conectado ? "#37c94b" : "#ff453a"));
                h.pack_start (punto, false, false, 0);
                var v = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                var nom = new Gtk.Label (d.nombre);
                nom.xalign = 0;
                v.pack_start (nom, false, false, 0);
                string estado = "Not Connected";
                if (conectado) {
                    estado = "Connected";
                } else if ((d.estado == "unavailable" || d.estado == "disconnected") && d.tipo == "wifi" && !wifi_encendido ()) {
                    estado = "Off";
                }
                var s = new Gtk.Label (estado);
                s.xalign = 0;
                s.get_style_context ().add_class ("mp-sd-detalle");
                v.pack_start (s, false, false, 0);
                h.pack_start (v, true, true, 0);
                h.pack_end (new Gtk.Image.from_icon_name (icono_de_tipo (d.tipo), Gtk.IconSize.LARGE_TOOLBAR), false, false, 0);
                fila.add (h);
                lista.add (fila);
                if (d.dev == previo) {
                    lista.select_row (fila);
                }
            }
            lista.show_all ();
            if (lista.get_selected_row () == null && lista.get_children ().length () > 0) {
                lista.select_row (lista.get_row_at_index (0));
            }
        }

        bool refrescar () {
            rellenar ();
            return true;
        }

        static bool wifi_encendido () {
            return nmcli ({ "radio", "wifi" }).strip () == "enabled";
        }

        void mostrar (FilaRed? fila) {
            foreach (var h in der.get_children ()) {
                der.remove (h);
            }
            if (fila == null) {
                return;
            }
            var d = fila.d;
            var info = detalle (d.dev);
            seleccion = d;
            bool conectado = d.estado.has_prefix ("connected");
            var g = new Gtk.Grid ();
            g.column_spacing = 12;
            g.row_spacing = 10;
            g.margin = 18;
            int fila_g = 0;
            g.attach (etiqueta_fila ("Status:"), 0, 0, 1, 1);
            var st = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var t = new Gtk.Label (conectado ? "Connected" : "Not Connected");
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            st.pack_start (t, false, false, 0);
            var ip4_completa = primero (info, "IP4.ADDRESS");
            var ip4 = ip4_completa.split ("/")[0];
            if (conectado && ip4 != "") {
                var s = new Gtk.Label ("%s is currently active and has the IP address %s.".printf (d.nombre, ip4));
                s.xalign = 0;
                s.set_line_wrap (true);
                s.set_max_width_chars (44);
                s.get_style_context ().add_class ("mp-sd-detalle");
                st.pack_start (s, false, false, 0);
            }
            g.attach (st, 1, 0, 1, 1);
            fila_g = 1;
            if (d.tipo == "wifi") {
                bool enc = wifi_encendido ();
                var b = new Gtk.Button.with_label ("Turn Wi-Fi %s".printf (enc ? "Off" : "On"));
                b.clicked.connect (() => alternar_wifi (enc));
                g.attach (b, 1, fila_g, 1, 1);
                fila_g++;
            }
            if (conectado) {
                // Configure IPv4: el método actual de la conexión; cambiarlo se hace en Advanced….
                var metodo = nmcli ({ "-g", "ipv4.method", "connection", "show", d.conexion }).strip ();
                g.attach (etiqueta_fila ("Configure IPv4:"), 0, fila_g, 1, 1);
                var c = new Gtk.ComboBoxText ();
                string texto_metodo;
                switch (metodo) {
                case "auto": texto_metodo = "Using DHCP"; break;
                case "manual": texto_metodo = "Manually"; break;
                case "link-local": texto_metodo = "Link-local only"; break;
                default: texto_metodo = metodo != "" ? metodo : "Using DHCP"; break;
                }
                c.append ("m", texto_metodo);
                c.set_active (0);
                g.attach (gris_red (c, "Change the IPv4 method in Advanced…"), 1, fila_g, 1, 1);
                fila_g++;
                var partes = ip4_completa.split ("/");
                var prefijo = partes.length > 1 ? partes[1] : "";
                fila_g = poner (g, fila_g, "IP Address:", ip4);
                int pref = 0;
                if (prefijo != "" && int.try_parse (prefijo, out pref)) {
                    fila_g = poner (g, fila_g, "Subnet Mask:", mascara (pref));
                }
                fila_g = poner (g, fila_g, "Router:", primero (info, "IP4.GATEWAY"));
                fila_g = poner (g, fila_g, "DNS Server:", unidos (info, "IP4.DNS"));
                fila_g = poner (g, fila_g, "Search Domains:", unidos (info, "IP4.DOMAIN"));
                if (info["IP6.ADDRESS"] != null && info["IP6.ADDRESS"].length > 0) {
                    fila_g = poner (g, fila_g, "IPv6 Address:", info["IP6.ADDRESS"][0].split ("/")[0]);
                }
            }
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            caja.pack_start (g, false, false, 0);
            caja.pack_start (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            pie.margin = 10;
            var av = new Gtk.Button.with_label ("Advanced…");
            av.clicked.connect (() => avanzado ());
            pie.pack_end (av, false, false, 0);
            caja.pack_start (pie, false, false, 0);
            der.add (caja);
            der.show_all ();
        }

        int poner (Gtk.Grid g, int fila, string titulo, string valor) {
            g.attach (etiqueta_fila (titulo), 0, fila, 1, 1);
            var v = new Gtk.Label (valor);
            v.xalign = 0;
            v.set_line_wrap (true);
            v.set_max_width_chars (40);
            v.selectable = true;
            g.attach (v, 1, fila, 1, 1);
            return fila + 1;
        }

        void alternar_wifi (bool encendido) {
            if (prueba) {
                return;
            }
            nmcli ({ "radio", "wifi", encendido ? "off" : "on" });
            rellenar ();
        }

        void avanzado () {
            if (prueba) {
                return;
            }
            if (seleccion != null && (seleccion.tipo == "ethernet" || seleccion.tipo == "vlan")
                && seleccion.conexion != "" && seleccion.conexion != "--") {
                // La hoja de Catalina (TCP/IP, DNS, WINS, 802.1X, Proxies, Hardware) sigue en el System Preferences de Python.
                abrir_en_python (id);
                return;
            }
            try {
                Process.spawn_async (null, { "nm-connection-editor" }, null,
                                     SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                     () => { Posix.setsid (); }, null);
            } catch (Error e) {
            }
        }
    }
}
