/*
 * Software Update: el panel de Catalina (Screen Shot 2026-10-14 at 1.22.23 PM y 1.22.26 PM, la hoja Advanced…); port de
 * settings/actualizaciones.py.
 *
 * Con todo al día dice «Your computer is up to date» con la versión de Linux Mint y cuándo se revisó (refresh-last-run de
 * com.linuxmint.updates). Con actualizaciones pendientes dice cuántas hay (las del grupo «sistema» del motor del App Store,
 * org.mintmacos.Tienda1; sin motor, `apt list --upgradable`) y Update Now las instala ahí mismo, con barra de progreso y
 * Stop; la clave la pide mac-polkit. Catalina no tiene captura de ese estado: el texto es sobrio y no se adorna.
 * La hoja Advanced…: «Check for updates» es refresh-schedule-enabled y «Install app updates» es auto-update-flatpaks; «Download new
 * updates», «Install macOS updates» y «Install system data files and security updates» no tienen una clave que podamos escribir
 * aquí y van en gris.
 */
namespace Preferencias {

    public class PanelSoftwareUpdate : Panel {
        const string AJUSTES = "com.linuxmint.updates";
        // MINT_ACTUALIZACIONES_PRUEBA: no escribe en gsettings.
        bool prueba = Environment.get_variable ("MINT_ACTUALIZACIONES_PRUEBA") != null;
        Settings? cfg = null;
        Gtk.Label? titulo_w = null;
        Gtk.Label? detalle_w = null;
        Gtk.Button? ir_w = null;
        Gtk.Box? avance_w = null;
        Gtk.ProgressBar? barra_w = null;
        Gtk.Label? etapa_w = null;
        string? trabajo = null;
        int generacion = 0;

        public PanelSoftwareUpdate () {
            id = "com.apple.preferences.softwareupdate";
            nombre = "Software Update";
            palabras = "software update, updates, upgrade, packages, security, automatically keep up to date";
        }

        static string version () {
            try {
                string texto;
                FileUtils.get_contents ("/etc/os-release", out texto);
                string? nombre = null, version = null;
                foreach (var l in texto.split ("\n")) {
                    var i = l.index_of ("=");
                    if (i < 0) {
                        continue;
                    }
                    var k = l.substring (0, i).strip ();
                    var v = l.substring (i + 1).strip ();
                    if (v.length >= 2 && v.has_prefix ("\"") && v.has_suffix ("\"")) {
                        v = v.substring (1, v.length - 2);
                    }
                    if (k == "NAME") nombre = v;
                    if (k == "VERSION") version = v;
                }
                if (nombre != null && version != null) {
                    return "%s %s".printf (nombre, version);
                }
            } catch (Error e) {
            }
            return "Linux";
        }

        /** Cuántas actualizaciones de apt hay, o -1 si no se pudo mirar. */
        static int pendientes () {
            try {
                var p = new Subprocess (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE, "apt", "list", "--upgradable");
                string? salida;
                p.communicate_utf8 (null, null, out salida, null);
                int n = 0;
                foreach (var l in (salida ?? "").split ("\n")) {
                    if (l.contains ("/") && l.contains ("upgradable")) {
                        n++;
                    }
                }
                return n;
            } catch (Error e) {
                return -1;
            }
        }

        /** «Today at 3:04 PM» o «Oct 12 at 3:04 PM», siempre en inglés. */
        static string cuando (int64 segundos) {
            string[] meses = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
            var t = new DateTime.from_unix_local (segundos);
            var ahora = new DateTime.now_local ();
            string dia = (t.get_year () == ahora.get_year () && t.get_day_of_year () == ahora.get_day_of_year ())
                ? "Today" : "%s %d".printf (meses[t.get_month () - 1], t.get_day_of_month ());
            int h = t.get_hour ();
            int h12 = h % 12 == 0 ? 12 : h % 12;
            return "%s at %d:%02d %s".printf (dia, h12, t.get_minute (), h < 12 ? "AM" : "PM");
        }

        public override Gtk.Widget? construir () {
            cfg = abrir_settings (AJUSTES);
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 20;
            caja.margin_bottom = 14;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            izq.set_size_request (240, -1);
            var icono = imagen_icono_panel (id, 112);
            icono.margin_top = 10;
            icono.margin_bottom = 10;
            izq.pack_start (icono, false, false, 0);
            var t = new Gtk.Label ("Software Update");
            t.get_style_context ().add_class ("mp-titulo-negrita");
            izq.pack_start (t, false, false, 0);
            caja.pack_start (izq, false, false, 0);
            caja.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);

            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            der.margin_start = 40;
            der.margin_end = 20;
            titulo_w = new Gtk.Label ("Checking for updates…");
            var titulo = titulo_w;
            titulo.xalign = 0;
            titulo.get_style_context ().add_class ("mp-titulo-negrita");
            der.pack_start (titulo, false, false, 0);
            int64 ultima = 0;
            if (cfg != null && "refresh-last-run" in cfg.list_keys ()) {
                var v = cfg.get_value ("refresh-last-run");
                if (v.is_of_type (VariantType.INT32)) {
                    ultima = v.get_int32 ();
                } else if (v.is_of_type (VariantType.INT64)) {
                    ultima = v.get_int64 ();
                } else if (v.is_of_type (VariantType.UINT32)) {
                    ultima = v.get_uint32 ();
                } else if (v.is_of_type (VariantType.UINT64)) {
                    ultima = (int64) v.get_uint64 ();
                }
            }
            if (ultima != 0) {
                var d = new Gtk.Label ("Last checked: %s".printf (cuando (ultima)));
                d.xalign = 0;
                d.get_style_context ().add_class ("mp-sd-detalle");
                der.pack_start (d, false, false, 0);
            }
            detalle_w = null;
            ir_w = new Gtk.Button.with_label ("Update Now");
            ir_w.halign = Gtk.Align.START;
            ir_w.margin_top = 12;
            ir_w.margin_bottom = 12;
            ir_w.no_show_all = true;
            ir_w.clicked.connect (instalar);
            der.pack_start (ir_w, false, false, 0);

            avance_w = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            avance_w.no_show_all = true;
            avance_w.margin_top = 12;
            barra_w = new Gtk.ProgressBar ();
            avance_w.pack_start (barra_w, false, false, 0);
            var fila_av = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            etapa_w = new Gtk.Label ("");
            etapa_w.xalign = 0;
            etapa_w.get_style_context ().add_class ("mp-sd-detalle");
            fila_av.pack_start (etapa_w, true, true, 0);
            var parar = new Gtk.Button.with_label ("Stop");
            parar.clicked.connect (cancelar);
            fila_av.pack_end (parar, false, false, 0);
            avance_w.pack_start (fila_av, false, false, 0);
            der.pack_start (avance_w, false, false, 0);
            der.pack_start (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var auto = new Gtk.CheckButton.with_label ("Automatically keep my computer up to date");
            auto.active = false;
            auto.set_sensitive (false);
            auto.set_tooltip_text ("Update Manager checks for updates; installing them stays manual.");
            pie.pack_start (auto, false, false, 0);
            var av = new Gtk.Button.with_label ("Advanced…");
            av.clicked.connect (() => hoja ());
            pie.pack_end (av, false, false, 0);
            der.pack_start (pie, false, false, 0);
            caja.pack_start (der, true, true, 0);
            caja.set_size_request (-1, 190);
            caja.show_all ();
            ir_w.hide ();
            avance_w.hide ();

            var motor = Tienda.Motor.instancia;
            var h_progreso = motor.progreso.connect (al_progreso);
            var h_terminado = motor.terminado.connect (al_terminar);
            caja.destroy.connect (() => { motor.disconnect (h_progreso); motor.disconnect (h_terminado); });
            refrescar.begin ();
            return caja;
        }

        /** Cuántas actualizaciones del sistema hay: el motor (grupo «sistema»), y sin motor `apt list`. */
        async void refrescar () {
            int gen = ++generacion;
            int n;
            string e;
            if (Tienda.Motor.instancia.conectar (out e)) {
                try {
                    var lista = yield Tienda.Motor.instancia.actualizaciones ("sistema");
                    n = (int) lista.length;
                } catch (Error err) {
                    n = pendientes ();
                }
            } else {
                n = pendientes ();
            }
            if (gen != generacion || titulo_w == null) {
                return;
            }
            if (n > 0) {
                titulo_w.label = "%d update%s available.".printf (n, n == 1 ? "" : "s");
            } else {
                titulo_w.label = "Your computer is up to date — %s".printf (version ());
            }
            ir_w.visible = n > 0 && trabajo == null;
        }

        void instalar () {
            if (prueba || trabajo != null) {
                return;
            }
            ir_w.hide ();
            avance_w.show_all ();
            barra_w.pulse ();
            etapa_w.label = "Waiting…";
            Tienda.Motor.instancia.actualizar.begin ("sistema", new string[0], (o, res) => {
                try {
                    trabajo = Tienda.Motor.instancia.actualizar.end (res);
                } catch (Error err) {
                    fallo (err.message);
                }
            });
        }

        void cancelar () {
            if (trabajo == null) {
                return;
            }
            Tienda.Motor.instancia.cancelar.begin (trabajo, (o, res) => {
                try { Tienda.Motor.instancia.cancelar.end (res); } catch (Error err) { }
            });
        }

        void al_progreso (string t, uint pct, string etapa) {
            if (trabajo == null) {
                trabajo = t;     // la señal llegó antes que la respuesta de Actualizar
            }
            if (t != trabajo || avance_w == null) {
                return;
            }
            if (pct <= 100) {
                barra_w.fraction = pct / 100.0;
            } else {
                barra_w.pulse ();
            }
            switch (etapa) {
            case "autorizando": etapa_w.label = "Waiting for authorization…"; break;
            case "descargando": etapa_w.label = "Downloading…"; break;
            case "instalando": etapa_w.label = "Installing…"; break;
            case "limpiando": etapa_w.label = "Cleaning up…"; break;
            default: etapa_w.label = "Waiting…"; break;
            }
        }

        void al_terminar (string t, string id, string tipo, bool ok, string codigo, string mensaje) {
            if (t != trabajo || avance_w == null) {
                return;
            }
            trabajo = null;
            avance_w.hide ();
            if (!ok && codigo != "cancelado" && codigo != "sin-autorizacion") {
                fallo (mensaje != "" ? mensaje : codigo);
                return;
            }
            refrescar.begin ();
        }

        void fallo (string mensaje) {
            trabajo = null;
            avance_w.hide ();
            titulo_w.label = "Couldn’t install the updates.";
            ir_w.show ();
            ir_w.label = "Try Again";
            ir_w.set_tooltip_text (mensaje);
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
            var cab = new Gtk.Label ("Automatically:");
            cab.xalign = 0;
            c.pack_start (cab, false, false, 0);
            string[] textos = { "Check for updates", "Download new updates when available", "Install OS updates", "Install app updates",
                                "Install system data files and security updates" };
            string[] claves = { "refresh-schedule-enabled", "", "", "auto-update-flatpaks", "" };
            for (int i = 0; i < textos.length; i++) {
                var b = new Gtk.CheckButton.with_label (textos[i]);
                var clave = claves[i];
                if (clave != "" && cfg != null && clave in cfg.list_keys ()) {
                    b.active = cfg.get_boolean (clave);
                    b.toggled.connect (() => { if (!prueba) cfg.set_boolean (clave, b.active); });
                } else {
                    b.active = false;
                    b.set_sensitive (false);
                    b.set_tooltip_text ("Not available on this computer.");
                }
                c.pack_start (b, false, false, 0);
            }
            var um = new Gtk.Button.with_label ("Open Update Manager…");
            um.halign = Gtk.Align.START;
            um.margin_top = 6;
            um.clicked.connect (() => {
                try {
                    Process.spawn_async (null, { "mintupdate" }, null, SpawnFlags.SEARCH_PATH, () => { Posix.setsid (); }, null);
                } catch (Error e) {
                }
            });
            c.pack_start (um, false, false, 0);
            var ok = d.add_button ("OK", Gtk.ResponseType.OK);
            ok.get_style_context ().add_class ("suggested-action");
            d.set_default_response (Gtk.ResponseType.OK);
            d.show_all ();
            d.run ();
            d.destroy ();
        }
    }
}
