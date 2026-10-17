/*
 * Bluetooth: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.35 PM y 1.22.39 PM, la hoja Advanced…); port de settings/bt.py.
 *
 * Habla con BlueZ por D-Bus (org.bluez, bus del sistema): el estado del adaptador, Turn Bluetooth On/Off, la lista de dispositivos
 * con «Connected» / «Not Connected» y Connect / Disconnect del dispositivo escogido. La lista se refresca cada 3 segundos mientras
 * el panel está abierto. Sin equivalente (en gris): Show Bluetooth in menu bar y las tres casillas de Advanced… (el asistente de
 * arranque y despertar la computadora con un dispositivo). El contextual de un dispositivo y el emparejamiento de dispositivos
 * nuevos no tienen captura: la lista solo enseña los dispositivos ya emparejados.
 */
namespace Preferencias {

    class FilaBt : Gtk.ListBoxRow {
        public string ruta = "";
        public bool conectado = false;
    }

    class Adaptador {
        public string ruta;
        public Variant props;                // a{sv}
        public bool encendido () {
            var v = props.lookup_value ("Powered", VariantType.BOOLEAN);
            return v != null && v.get_boolean ();
        }
        public string alias () {
            var v = props.lookup_value ("Alias", VariantType.STRING);
            return v != null ? v.get_string () : "";
        }
    }

    class DispositivoBt {
        public string ruta;
        public Variant props;
        public string? texto (string clave) {
            var v = props.lookup_value (clave, VariantType.STRING);
            return v != null ? v.get_string () : null;
        }
        public bool bandera (string clave) {
            var v = props.lookup_value (clave, VariantType.BOOLEAN);
            return v != null && v.get_boolean ();
        }
    }

    public class PanelBluetooth : Panel {
        const string BLUEZ = "org.bluez";
        // MINT_BT_PRUEBA: solo lee: no enciende, apaga ni conecta.
        bool prueba = Environment.get_variable ("MINT_BT_PRUEBA") != null;
        Adaptador? adaptador = null;
        uint temporizador = 0;
        Gtk.Label estado_l;
        Gtk.Button boton;
        Gtk.Label visible_l;
        Gtk.ListBox lista;
        Gtk.Button conectar;

        public PanelBluetooth () {
            id = "com.apple.preferences.Bluetooth";
            nombre = "Bluetooth";
            palabras = "bluetooth, devices, pair, connect, discoverable, keyboard, mouse, headphones, speaker";
        }

        /** El adaptador y los dispositivos de GetManagedObjects, o (null, vacío) si BlueZ no contesta. */
        static void leer_estado (out Adaptador? adaptador, out List<DispositivoBt> dispositivos) {
            adaptador = null;
            dispositivos = new List<DispositivoBt> ();
            try {
                var bus = Bus.get_sync (BusType.SYSTEM);
                var r = bus.call_sync (BLUEZ, "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", null, null,
                                       DBusCallFlags.NONE, 5000, null);
                var objetos = r.get_child_value (0);
                var rutas = new GenericArray<string> ();
                var por_ruta = new HashTable<string, Variant> (str_hash, str_equal);
                for (size_t i = 0; i < objetos.n_children (); i++) {
                    var par = objetos.get_child_value (i);
                    var ruta = par.get_child_value (0).get_string ();
                    rutas.add (ruta);
                    por_ruta[ruta] = par.get_child_value (1);
                }
                rutas.sort ((a, b) => strcmp (a, b));
                for (int k = 0; k < rutas.length; k++) {
                    var ruta = rutas[k];
                    var ifaces = por_ruta[ruta];
                    var a = ifaces.lookup_value ("org.bluez.Adapter1", null);
                    if (a != null && adaptador == null) {
                        adaptador = new Adaptador ();
                        adaptador.ruta = ruta;
                        adaptador.props = a;
                    }
                    var d = ifaces.lookup_value ("org.bluez.Device1", null);
                    if (d != null) {
                        var dev = new DispositivoBt ();
                        dev.ruta = ruta;
                        dev.props = d;
                        dispositivos.append (dev);
                    }
                }
            } catch (Error e) {
                adaptador = null;
            }
        }

        static void poner_propiedad (string ruta, string interfaz, string nombre_p, Variant valor) throws Error {
            var bus = Bus.get_sync (BusType.SYSTEM);
            bus.call_sync (BLUEZ, ruta, "org.freedesktop.DBus.Properties", "Set",
                           new Variant ("(ssv)", interfaz, nombre_p, valor), null, DBusCallFlags.NONE, 15000, null);
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 20, 20, 20, 20);
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            izq.set_size_request (210, -1);
            var icono = imagen_icono_panel (id, 130);
            icono.margin_top = 12;
            icono.margin_bottom = 12;
            izq.pack_start (icono, false, false, 0);
            estado_l = new Gtk.Label (null);
            estado_l.get_style_context ().add_class ("mp-titulo-negrita");
            izq.pack_start (estado_l, false, false, 0);
            boton = new Gtk.Button ();
            boton.clicked.connect (() => alternar ());
            izq.pack_start (boton, false, false, 0);
            visible_l = new Gtk.Label (null);
            visible_l.set_line_wrap (true);
            visible_l.set_justify (Gtk.Justification.CENTER);
            visible_l.margin_top = 6;
            visible_l.margin_bottom = 6;
            izq.pack_start (visible_l, false, false, 0);
            caja.pack_start (izq, false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var marco = new Gtk.Frame (null);
            marco.get_style_context ().add_class ("mp-sd-lista");
            var cab = new Gtk.Label ("Devices");
            cab.xalign = 0;
            cab.margin = 6;
            cab.get_style_context ().add_class ("mp-titulo-negrita");
            var interior = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            interior.pack_start (cab, false, false, 0);
            lista = new Gtk.ListBox ();
            lista.set_selection_mode (Gtk.SelectionMode.SINGLE);
            lista.row_selected.connect (() => botones ());
            var pant = new Gtk.ScrolledWindow (null, null);
            pant.set_size_request (-1, 240);
            pant.add (lista);
            interior.pack_start (pant, true, true, 0);
            marco.add (interior);
            der.pack_start (marco, true, true, 0);

            var accion = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            conectar = new Gtk.Button.with_label ("Connect");
            conectar.clicked.connect (() => conmutar ());
            accion.pack_start (conectar, false, false, 0);
            der.pack_start (accion, false, false, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var menu = new Gtk.CheckButton.with_label ("Show Bluetooth in menu bar");
            menu.active = true;
            menu.set_sensitive (false);
            menu.set_tooltip_text ("The Bluetooth menu lives in the Cinnamon panel.");
            pie.pack_start (menu, false, false, 0);
            var av = new Gtk.Button.with_label ("Advanced…");
            av.clicked.connect (() => hoja ());
            pie.pack_end (av, false, false, 0);
            der.pack_start (pie, false, false, 0);
            caja.pack_start (der, true, true, 0);

            caja.show_all ();
            refrescar ();
            visible_para_otros (true);         // como Catalina: visible mientras el panel está abierto
            temporizador = Timeout.add_seconds (3, refrescar);
            caja.destroy.connect (() => {
                if (temporizador != 0) {
                    Source.remove (temporizador);
                    temporizador = 0;
                }
                visible_para_otros (false);
            });
            return caja;
        }

        /** Discoverable del adaptador (BlueZ lo apaga solo a los 180 s si el panel no lo hace antes). */
        void visible_para_otros (bool si) {
            if (prueba || adaptador == null || !adaptador.encendido ()) {
                return;
            }
            try {
                poner_propiedad (adaptador.ruta, "org.bluez.Adapter1", "Discoverable", new Variant.boolean (si));
            } catch (Error e) {
            }
        }

        // ── el estado ────────────────────────────────────────────────────
        bool refrescar () {
            Adaptador? a;
            List<DispositivoBt> dispositivos;
            leer_estado (out a, out dispositivos);
            adaptador = a;
            if (a == null) {
                estado_l.set_text ("Bluetooth: Not Available");
                boton.hide ();
                visible_l.set_text ("");
            } else {
                bool enc = a.encendido ();
                estado_l.set_text ("Bluetooth: %s".printf (enc ? "On" : "Off"));
                boton.set_label ("Turn Bluetooth %s".printf (enc ? "Off" : "On"));
                boton.show ();
                visible_l.set_text (enc ? "Now discoverable as\n“%s”".printf (a.alias ()) : "");
            }
            var ruta_elegida = ruta_elegida_ahora ();
            foreach (var f in lista.get_children ()) {
                lista.remove (f);
            }
            foreach (var d in dispositivos) {
                if (!d.bandera ("Paired")) {
                    continue;
                }
                var fila = new FilaBt ();
                fila.ruta = d.ruta;
                fila.conectado = d.bandera ("Connected");
                var h = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                h.margin = 6;
                h.pack_start (new Gtk.Image.from_icon_name ((d.texto ("Icon") ?? "bluetooth") + "-symbolic", Gtk.IconSize.LARGE_TOOLBAR),
                              false, false, 0);
                var v = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                var alias = d.texto ("Alias");
                var nom = (alias != null && alias != "") ? alias : (d.texto ("Name") ?? (d.texto ("Address") ?? ""));
                var l1 = new Gtk.Label (nom);
                l1.xalign = 0;
                v.pack_start (l1, false, false, 0);
                var s = new Gtk.Label (fila.conectado ? "Connected" : "Not Connected");
                s.xalign = 0;
                s.get_style_context ().add_class ("mp-sd-detalle");
                v.pack_start (s, false, false, 0);
                h.pack_start (v, true, true, 0);
                fila.add (h);
                lista.add (fila);
                if (d.ruta == ruta_elegida) {
                    lista.select_row (fila);
                }
            }
            lista.show_all ();
            botones ();
            return true;
        }

        string? ruta_elegida_ahora () {
            var f = lista.get_selected_row () as FilaBt;
            return f != null ? f.ruta : null;
        }

        void botones () {
            var f = lista.get_selected_row () as FilaBt;
            conectar.set_visible (f != null);
            if (f != null) {
                conectar.set_label (f.conectado ? "Disconnect" : "Connect");
            }
        }

        // ── acciones ─────────────────────────────────────────────────────
        void alternar () {
            if (adaptador == null || prueba) {
                return;
            }
            bool enc = adaptador.encendido ();
            try {
                poner_propiedad (adaptador.ruta, "org.bluez.Adapter1", "Powered", new Variant.boolean (!enc));
            } catch (Error e) {
            }
            refrescar ();
        }

        void conmutar () {
            var f = lista.get_selected_row () as FilaBt;
            if (f == null || prueba) {
                return;
            }
            var metodo = f.conectado ? "Disconnect" : "Connect";
            try {
                var bus = Bus.get_sync (BusType.SYSTEM);
                bus.call.begin (BLUEZ, f.ruta, "org.bluez.Device1", metodo, null, null, DBusCallFlags.NONE, 30000, null,
                                (o, r) => {
                    try {
                        bus.call.end (r);
                    } catch (Error e) {
                    }
                    refrescar ();
                });
            } catch (Error e) {
            }
        }

        void hoja () {
            var d = new Gtk.Dialog ();
            d.transient_for = ventana;
            d.modal = true;
            d.set_decorated (false);
            d.get_style_context ().add_class ("mp-hoja");
            var c = d.get_content_area () as Gtk.Box;
            c.set_spacing (8);
            margenes (c, 20, 20, 20, 20);
            string[] titulos = { "Open Bluetooth Setup Assistant at startup if no keyboard is detected",
                                 "Open Bluetooth Setup Assistant at startup if no mouse or trackpad is detected",
                                 "Allow Bluetooth devices to wake this computer" };
            string[] detalles = {
                "If you use a keyboard and your computer doesn’t detect one when you start your computer, the Bluetooth Setup Assistant will open to connect the Bluetooth keyboard.",
                "If you use a mouse or trackpad and your computer doesn’t detect one when you start your computer, the Bluetooth Setup Assistant will open to connect the Bluetooth mouse or trackpad.",
                "If you use a Bluetooth keyboard or mouse or trackpad, and your computer goes to sleep, you can press a key on your keyboard or click your mouse or trackpad to wake your computer." };
            for (int i = 0; i < 3; i++) {
                var b = new Gtk.CheckButton.with_label (titulos[i]);
                b.active = true;
                b.set_sensitive (false);
                b.set_tooltip_text ("Not available on this computer.");
                c.pack_start (b, false, false, 0);
                var t = new Gtk.Label (detalles[i]);
                t.xalign = 0;
                t.set_line_wrap (true);
                t.set_max_width_chars (70);
                t.margin_start = 24;
                t.get_style_context ().add_class ("mp-sd-detalle");
                t.margin_top = 4;
                t.margin_bottom = 4;
                c.pack_start (t, false, false, 0);
            }
            var ok = d.add_button ("OK", Gtk.ResponseType.OK);
            ok.get_style_context ().add_class ("suggested-action");
            d.set_default_response (Gtk.ResponseType.OK);
            d.show_all ();
            d.run ();
            d.destroy ();
        }
    }
}
