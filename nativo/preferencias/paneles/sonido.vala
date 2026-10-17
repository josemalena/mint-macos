/*
 * Sound: el panel de Catalina con sus tres pestañas (Sound Effects, Output, Input); port de settings/sonido.py.
 *
 * Capturas: Screen Shot 2026-10-14 at 1.20.39 PM (Sound Effects), 1.20.52 PM (Output), 1.20.55 PM (Input).
 *
 * Conectado de verdad (PipeWire/PulseAudio con pactl): los dispositivos de salida y de entrada y cuál es el predeterminado,
 * Balance, Output volume, Mute e Input volume. En Sound Effects, «Play user interface sound effects» y «Play feedback when volume is
 * changed» son claves de org.cinnamon.desktop.sound. Sin equivalente aquí (en gris, como en una Mac sin esa función): Alert volume,
 * Play sound effects through, Show volume in menu bar y el medidor Input level.
 *
 * La lista de alertas (Basso, Blow, Bottle…) son sonidos de Apple: salen del disco de la Mac a
 * ~/.local/share/mint-macos/settings/sonidos/ y nunca van al repo. Sin ellos la lista queda vacía.
 */
namespace Preferencias {

    public delegate void EscalaDoble (double valor);

    public class PanelSound : Panel {
        // MINT_SONIDO_PRUEBA: no escribe en PipeWire ni en gsettings.
        bool prueba = Environment.get_variable ("MINT_SONIDO_PRUEBA") != null;
        bool cargando = false;
        Gtk.Scale? vol_salida = null;
        Gtk.Scale? vol_entrada = null;
        Gtk.Scale? balance = null;
        Gtk.CheckButton? mudo = null;

        public PanelSound () {
            id = "com.apple.preference.sound";
            nombre = "Sound";
            palabras = "sound, volume, output, input, microphone, speakers, balance, mute, alert, sound effects";
        }

        static string pactl (string[] args) {
            string[] cmd = { "pactl" };
            foreach (var a in args) {
                cmd += a;
            }
            try {
                var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                return p.get_successful () ? (salida ?? "") : "";
            } catch (Error e) {
                return "";
            }
        }

        /** Los sinks o sources de `pactl -f json list`. */
        static List<Json.Object> lista_json (string que) {
            var salida = new List<Json.Object> ();
            var texto = pactl ({ "-f", "json", "list", que });
            if (texto == "") {
                return salida;
            }
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (texto);
                var raiz = parser.get_root ();
                if (raiz == null || raiz.get_node_type () != Json.NodeType.ARRAY) {
                    return salida;
                }
                var arr = raiz.get_array ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    salida.append (arr.get_object_element (i));      // los objetos siguen vivos mientras viva el nodo raíz
                }
                raices.append (parser);
            } catch (Error e) {
            }
            return salida;
        }

        // Los parsers de los objetos devueltos se guardan para que no se liberen (Json.Object cuenta referencias, pero así es más seguro).
        static List<Json.Parser> raices = new List<Json.Parser> ();

        static string texto_de (Json.Object o, string clave, string defecto = "") {
            if (!o.has_member (clave)) {
                return defecto;
            }
            var n = o.get_member (clave);
            if (n.get_node_type () != Json.NodeType.VALUE || n.get_value_type () != typeof (string)) {
                return defecto;
            }
            return n.get_string ();
        }

        /** El texto de la columna Type, como los pone Catalina (USB, HDMI, Bluetooth, Headphone port…). */
        static string tipo_de (Json.Object d) {
            string bus = "";
            if (d.has_member ("properties") && d.get_member ("properties").get_node_type () == Json.NodeType.OBJECT) {
                bus = texto_de (d.get_object_member ("properties"), "device.bus");
            }
            var nombre_d = texto_de (d, "name").down ();
            var puerto = texto_de (d, "active_port").down ();
            if (bus == "usb") {
                return "USB";
            }
            if (bus == "bluetooth" || nombre_d.contains ("bluez")) {
                return "Bluetooth";
            }
            if (nombre_d.contains ("hdmi") || puerto.contains ("hdmi")) {
                return "HDMI";
            }
            if (puerto.contains ("headphone")) {
                return "Headphone port";
            }
            if (puerto.contains ("line")) {
                return "Audio line-in port";
            }
            return "Built-in";
        }

        /** El volumen más alto de los canales, de 0 a 100. */
        static double volumen_de (Json.Object? d) {
            double mejor = 0;
            if (d == null || !d.has_member ("volume") || d.get_member ("volume").get_node_type () != Json.NodeType.OBJECT) {
                return 0;
            }
            var v = d.get_object_member ("volume");
            foreach (var canal in v.get_members ()) {
                var c = v.get_member (canal);
                if (c.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }
                var t = texto_de (c.get_object (), "value_percent", "0%");
                double x;
                if (double.try_parse (t.replace ("%", ""), out x) && x > mejor) {
                    mejor = x;
                }
            }
            return mejor;
        }

        static bool mudo_de (Json.Object? d) {
            if (d == null || !d.has_member ("mute")) {
                return false;
            }
            var n = d.get_member ("mute");
            return n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (bool) && n.get_boolean ();
        }

        static Json.Object? predeterminado (string que, string orden) {
            var nom = pactl ({ orden }).strip ();
            foreach (var d in lista_json (que)) {
                if (texto_de (d, "name") == nom) {
                    return d;
                }
            }
            return null;
        }

        static Gtk.Scale deslizador (double valor, double minimo, double maximo, string? pie_izq, string? pie_der,
                                     owned EscalaDoble al_cambiar, int marcas = 11) {
            var esc = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, minimo, maximo, (maximo - minimo) / 100.0);
            esc.draw_value = false;
            esc.set_value (valor);
            esc.set_size_request (190, -1);
            esc.margin_start = 14;
            for (int i = 0; i < marcas; i++) {
                esc.add_mark (minimo + (maximo - minimo) * i / (marcas - 1), Gtk.PositionType.BOTTOM, null);
            }
            if (pie_izq != null) {
                esc.add_mark (minimo, Gtk.PositionType.BOTTOM, pie_izq);
                esc.add_mark (maximo, Gtk.PositionType.BOTTOM, pie_der);
            }
            esc.value_changed.connect (() => al_cambiar (esc.get_value ()));
            return esc;
        }

        // ── la página ────────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            cargando = true;
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 12;
            var stack = new Gtk.Stack ();
            stack.add_titled (pagina_efectos (), "efectos", "Sound Effects");
            stack.add_titled (pagina_dispositivos (true), "salida", "Output");
            stack.add_titled (pagina_dispositivos (false), "entrada", "Input");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);
            var pie_w = pie ();
            pie_w.margin_top = 6;
            pie_w.margin_bottom = 6;
            caja.pack_start (pie_w, false, false, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_SONIDO_PESTANA");        // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            cargando = false;
            return caja;
        }

        // ── Output volume y Mute (abajo, en las tres pestañas) ───────────
        Gtk.Widget pie () {
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 6;
            g.halign = Gtk.Align.CENTER;
            g.attach (etiqueta_fila ("Output volume:"), 0, 0, 1, 1);
            var sal = predeterminado ("sinks", "get-default-sink");
            double vol = sal != null ? volumen_de (sal) : 0;
            vol_salida = deslizador (vol, 0, 100, null, null, (v) => poner_volumen_salida (v));
            g.attach (vol_salida, 1, 0, 1, 1);
            mudo = new Gtk.CheckButton.with_label ("Mute");
            mudo.active = sal != null && mudo_de (sal);
            mudo.toggled.connect (() => poner_mudo (mudo.active));
            g.attach (mudo, 2, 0, 1, 1);
            var menu = new Gtk.CheckButton.with_label ("Show volume in menu bar");
            menu.active = true;
            menu.set_sensitive (false);
            menu.set_tooltip_text ("The volume control lives in the Cinnamon panel.");
            g.attach (menu, 1, 1, 2, 1);
            return g;
        }

        void poner_volumen_salida (double v) {
            if (cargando || prueba) {
                return;
            }
            pactl ({ "set-sink-volume", "@DEFAULT_SINK@", "%d%%".printf ((int) Math.rint (v)) });
        }

        void poner_mudo (bool si) {
            if (cargando || prueba) {
                return;
            }
            pactl ({ "set-sink-mute", "@DEFAULT_SINK@", si ? "1" : "0" });
        }

        // ── Sound Effects ────────────────────────────────────────────────
        Gtk.Widget pagina_efectos () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            margenes (pagina, 14, 14, 20, 20);
            var t = new Gtk.Label ("Select an alert sound:");
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            pagina.pack_start (t, false, false, 0);
            var lista = new Gtk.ListStore (3, typeof (string), typeof (string), typeof (string));
            var sonidos = Path.build_filename (carpeta_apps (), "sonidos");
            var rutas = new GenericArray<string> ();
            try {
                var dir = Dir.open (sonidos);
                string? n;
                while ((n = dir.read_name ()) != null) {
                    rutas.add (Path.build_filename (sonidos, n));
                }
            } catch (Error e) {
            }
            rutas.sort ((a, b) => strcmp (a, b));
            for (int i = 0; i < rutas.length; i++) {
                var base_ = Path.get_basename (rutas[i]);
                int punto = base_.last_index_of (".");
                Gtk.TreeIter it;
                lista.append (out it);
                lista.set (it, 0, punto > 0 ? base_.substring (0, punto) : base_, 1, "Built-in", 2, rutas[i], -1);
            }
            var arbol = new Gtk.TreeView.with_model (lista);
            string[] titulos = { "Name", "Type" };
            for (int i = 0; i < 2; i++) {
                var col = new Gtk.TreeViewColumn.with_attributes (titulos[i], new Gtk.CellRendererText (), "text", i, null);
                col.expand = true;
                arbol.append_column (col);
            }
            arbol.get_selection ().changed.connect (() => alerta_elegida (arbol.get_selection ()));
            var marco = marco_lista ();
            marco.set_size_request (-1, 130);
            var pantalla = new Gtk.ScrolledWindow (null, null);
            pantalla.add (arbol);
            marco.add (pantalla);
            pagina.pack_start (marco, false, false, 0);

            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 10;
            g.halign = Gtk.Align.CENTER;
            g.attach (etiqueta_fila ("Play sound effects through:"), 0, 0, 1, 1);
            var por = new Gtk.ComboBoxText ();
            por.append ("sel", "Selected sound output device");
            por.set_active (0);
            por.set_sensitive (false);
            por.set_tooltip_text ("Effects always use the selected output device here.");
            g.attach (por, 1, 0, 2, 1);
            g.attach (etiqueta_fila ("Alert volume:"), 0, 1, 1, 1);
            var av = deslizador (100, 0, 100, null, null, (v) => { }, 8);
            av.set_sensitive (false);
            av.set_tooltip_text ("Alerts follow the output volume on this computer.");
            g.attach (av, 1, 1, 2, 1);
            var cfg = abrir_settings ("org.cinnamon.desktop.sound");
            string[] claves = { "event-sounds", "volume-sound-enabled" };
            string[] textos = { "Play user interface sound effects", "Play feedback when volume is changed" };
            for (int i = 0; i < 2; i++) {
                var c = new Gtk.CheckButton.with_label (textos[i]);
                var clave = claves[i];
                c.active = cfg != null && cfg.get_boolean (clave);
                c.toggled.connect (() => { if (!cargando && !prueba && cfg != null) cfg.set_boolean (clave, c.active); });
                g.attach (c, 1, 2 + i, 2, 1);
            }
            pagina.pack_start (g, false, false, 0);
            return pagina;
        }

        void alerta_elegida (Gtk.TreeSelection seleccion) {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!seleccion.get_selected (out modelo, out it) || cargando || prueba) {
                return;
            }
            string ruta;
            modelo.get (it, 2, out ruta, -1);
            var cfg = abrir_settings ("org.cinnamon.sounds");
            if (cfg != null) {
                cfg.set_string ("notification-file", ruta);
                cfg.set_boolean ("notification-enabled", true);
            }
            try {
                Process.spawn_async (null, { "paplay", ruta }, null,
                                     SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL, null, null);
            } catch (Error e) {
            }
        }

        // ── Output e Input ───────────────────────────────────────────────
        Gtk.Widget pagina_dispositivos (bool salida) {
            var que = salida ? "sinks" : "sources";
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            margenes (pagina, 14, 14, 20, 20);
            var t = new Gtk.Label ("Select a device for sound %s:".printf (salida ? "output" : "input"));
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            pagina.pack_start (t, false, false, 0);

            var lista = new Gtk.ListStore (3, typeof (string), typeof (string), typeof (string));       // nombre, tipo, id de PipeWire
            var pred = pactl ({ salida ? "get-default-sink" : "get-default-source" }).strip ();
            Gtk.TreeIter elegido = Gtk.TreeIter ();
            bool hay_elegido = false;
            foreach (var d in lista_json (que)) {
                var nom = texto_de (d, "name");
                if (!salida && nom.has_suffix (".monitor")) {
                    continue;                           // los «monitor» son la salida escuchada, no un micrófono
                }
                Gtk.TreeIter it;
                lista.append (out it);
                lista.set (it, 0, texto_de (d, "description", nom), 1, tipo_de (d), 2, nom, -1);
                if (nom == pred) {
                    elegido = it;
                    hay_elegido = true;
                }
            }
            var arbol = new Gtk.TreeView.with_model (lista);
            string[] titulos = { "Name", "Type" };
            for (int i = 0; i < 2; i++) {
                var col = new Gtk.TreeViewColumn.with_attributes (titulos[i], new Gtk.CellRendererText (), "text", i, null);
                col.expand = true;
                arbol.append_column (col);
            }
            var marco = marco_lista ();
            marco.set_size_request (-1, 140);
            var pantalla = new Gtk.ScrolledWindow (null, null);
            pantalla.add (arbol);
            marco.add (pantalla);
            pagina.pack_start (marco, false, false, 0);

            var sub = new Gtk.Label ("Settings for the selected device:");
            sub.xalign = 0;
            pagina.pack_start (sub, false, false, 0);
            var g = new Gtk.Grid ();
            g.column_spacing = 10;
            g.row_spacing = 10;
            g.halign = Gtk.Align.CENTER;
            if (salida) {
                g.attach (etiqueta_fila ("Balance:"), 0, 0, 1, 1);
                balance = deslizador (0, -100, 100, "left", "right", (b) => poner_balance (b), 5);
                g.attach (balance, 1, 0, 1, 1);
            } else {
                g.attach (etiqueta_fila ("Input volume:"), 0, 0, 1, 1);
                vol_entrada = deslizador (0, 0, 100, null, null, (v) => poner_volumen_entrada (v));
                g.attach (vol_entrada, 1, 0, 1, 1);
                g.attach (etiqueta_fila ("Input level:"), 0, 1, 1, 1);
                var nivel = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                for (int i = 0; i < 15; i++) {
                    nivel.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);
                }
                nivel.set_sensitive (false);
                nivel.set_tooltip_text ("The input level meter is not available on this computer.");
                g.attach (nivel, 1, 1, 1, 1);
            }
            pagina.pack_start (g, false, false, 0);

            arbol.get_selection ().changed.connect (() => dispositivo_elegido (arbol.get_selection (), salida));
            if (hay_elegido) {
                arbol.get_selection ().select_iter (elegido);
            }
            return pagina;
        }

        void dispositivo_elegido (Gtk.TreeSelection seleccion, bool salida) {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!seleccion.get_selected (out modelo, out it)) {
                return;
            }
            string nom;
            modelo.get (it, 2, out nom, -1);
            Json.Object? d = null;
            foreach (var x in lista_json (salida ? "sinks" : "sources")) {
                if (texto_de (x, "name") == nom) {
                    d = x;
                    break;
                }
            }
            bool previo = cargando;
            cargando = true;
            if (d != null) {
                if (salida) {
                    double b = 0;
                    if (d.has_member ("balance") && d.get_member ("balance").get_node_type () == Json.NodeType.VALUE) {
                        b = d.get_double_member ("balance");
                    }
                    balance.set_value (b * 100);
                } else {
                    vol_entrada.set_value (volumen_de (d));
                }
            }
            cargando = previo;
            if (!previo && !prueba) {
                pactl ({ salida ? "set-default-sink" : "set-default-source", nom });
                if (salida) {        // el volumen y el mute de abajo son los del dispositivo recién elegido
                    cargando = true;
                    vol_salida.set_value (volumen_de (d));
                    mudo.active = mudo_de (d);
                    cargando = false;
                }
            }
        }

        /** b de -100 (todo a la izquierda) a 100 (todo a la derecha): baja el canal contrario. */
        void poner_balance (double b) {
            if (cargando || prueba) {
                return;
            }
            var d = predeterminado ("sinks", "get-default-sink");
            if (d == null) {
                return;
            }
            double v = volumen_de (d);
            double izq = v * (1 - double.max (0.0, b) / 100.0);
            double der = v * (1 + double.min (0.0, b) / 100.0);
            pactl ({ "set-sink-volume", "@DEFAULT_SINK@", "%d%%".printf ((int) Math.rint (izq)), "%d%%".printf ((int) Math.rint (der)) });
        }

        void poner_volumen_entrada (double v) {
            if (cargando || prueba) {
                return;
            }
            pactl ({ "set-source-volume", "@DEFAULT_SOURCE@", "%d%%".printf ((int) Math.rint (v)) });
        }
    }
}
