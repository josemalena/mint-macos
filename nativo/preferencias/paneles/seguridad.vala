/*
 * Security & Privacy: el panel de Catalina con sus cuatro pestañas (General, FileVault, Firewall, Privacy); port de settings/seguridad.py.
 *
 * Capturas: Screen Shot 2026-10-14 at 1.21.03 PM (General), 1.21.08 PM (FileVault), 1.21.11 PM (Firewall) y 1.21.15 PM (Privacy ▸
 * Location Services).
 *
 * General: Require password … after sleep or screen saver begins es lock-enabled y lock-delay de org.cinnamon.desktop.screensaver;
 * «Show a message when the screen is locked» y Set Lock Message… son default-message; Change Password… abre el módulo de usuario de
 * Cinnamon. Las opciones de tiempo, salvo «1 minute», no tienen captura.
 * FileVault: dice si el disco está cifrado (LUKS, con lsblk); Turn On FileVault… va en gris (cifrar el disco ya instalado no se hace
 * desde aquí). Firewall: dice si ufw está activo (systemctl); los botones van en gris porque cambiarlo pide root. Privacy ▸ Location
 * Services y el resto de categorías van en gris: Linux no tiene ese permiso por app.
 * Sin equivalente (en gris): Disable automatic login, Allow apps downloaded from, Advanced…
 * Los controles de usuario no necesitan el candado, así que no se dibuja.
 *
 * Privacy: cada categoría y su página. Los textos salen de Security.prefPane/Resources/en.lproj/Localizable.strings del disco de la
 * Mac (y de las capturas 16-privacy-*). Las nueve primeras y su orden son los de la captura; el orden de las demás, que en la Mac
 * quedan fuera de la vista de la barra lateral, es el de la guía «Change Privacy preferences on Mac» de macOS 10.15
 * (https://support.apple.com/guide/mac-help/mh32356/10.15/mac/10.15): orden de la guía, sin captura. Developer Tools no sale:
 * Catalina la oculta mientras no tenga aplicaciones.
 */
namespace Preferencias {

    class CategoriaPrivacidad {
        public string nombre;
        public string tipo;
        public string dato;
        public bool con_barra;
        public CategoriaPrivacidad (string nombre, string tipo, string dato = "", bool con_barra = false) {
            this.nombre = nombre;
            this.tipo = tipo;
            this.dato = dato;
            this.con_barra = con_barra;
        }
    }

    class FilaPrivacidad : Gtk.ListBoxRow {
        public string nombre_cat = "";
    }

    public class PanelSecurity : Panel {
        const int[] BLOQUEO_S = { 0, 5, 60, 300, 900, 3600, 14400, 28800 };
        const string[] BLOQUEO_TXT = { "immediately", "5 seconds", "1 minute", "5 minutes", "15 minutes", "1 hour", "4 hours", "8 hours" };
        // MINT_SEGURIDAD_PRUEBA: no cambia la configuración.
        bool prueba = Environment.get_variable ("MINT_SEGURIDAD_PRUEBA") != null;
        bool cargando = false;
        Settings? pantalla = null;
        Gtk.CheckButton mensaje_activo;

        public PanelSecurity () {
            id = "com.apple.preference.security";
            nombre = "Security & Privacy";
            palabras = "security, privacy, password, firewall, filevault, lock, location services, gatekeeper";
        }

        static string icono_privacidad (string nombre_cat) {
            switch (nombre_cat) {
            case "Location Services": return "locationservices";
            case "Contacts": return "contacts";
            case "Calendars": return "calendars";
            case "Reminders": return "reminders";
            case "Photos": return "photos";
            case "Camera": return "cameraservices";
            case "Microphone": case "Speech Recognition": return "microphoneservices";
            case "Accessibility": return "accessibilityservices";
            }
            return "";
        }

        static CategoriaPrivacidad[] categorias () {
            const string SIN_APPS = "Apps that have requested access to %s will appear here.";
            return {
                new CategoriaPrivacidad ("Location Services", "ubicacion"),
                new CategoriaPrivacidad ("Contacts", "vacia", SIN_APPS.printf ("your contacts")),
                new CategoriaPrivacidad ("Calendars", "vacia", SIN_APPS.printf ("your calendars")),
                new CategoriaPrivacidad ("Reminders", "vacia", SIN_APPS.printf ("your reminders")),
                new CategoriaPrivacidad ("Photos", "vacia", SIN_APPS.printf ("your photos")),
                new CategoriaPrivacidad ("Camera", "vacia", SIN_APPS.printf ("your camera")),
                new CategoriaPrivacidad ("Microphone", "vacia", SIN_APPS.printf ("your microphone")),
                new CategoriaPrivacidad ("Speech Recognition", "vacia", "Apps that have requested access to speech recognition will appear here. Speech recognition sends recorded voice to Apple to process your requests."),
                new CategoriaPrivacidad ("Accessibility", "lista", "Allow the apps below to control your computer.", true),
                new CategoriaPrivacidad ("Input Monitoring", "lista", "Allow the apps below to monitor input from your keyboard even while using other apps.", true),
                new CategoriaPrivacidad ("Full Disk Access", "lista", "Allow the apps below to access data like Mail, Messages, Safari, Home, Time Machine backups, and certain administrative settings for all users on this Mac.", true),
                new CategoriaPrivacidad ("Files and Folders", "lista", "Allow the apps below to access files and folders.", true),
                new CategoriaPrivacidad ("Screen Recording", "vacia", SIN_APPS.printf ("record the contents of your screen")),
                new CategoriaPrivacidad ("Automation", "lista", "Allow the apps below to control other apps. This will provide access to documents and data in those apps, and to perform actions within them.", false),
                new CategoriaPrivacidad ("Advertising", "publicidad"),
                new CategoriaPrivacidad ("Analytics & Improvements", "analitica")
            };
        }

        static Gtk.Widget gris_seg (Gtk.Widget w, string motivo = "Not available on this computer.") {
            w.set_sensitive (false);
            w.set_tooltip_text (motivo);
            return w;
        }

        public override Gtk.Widget? construir () {
            cargando = true;
            pantalla = abrir_settings ("org.cinnamon.desktop.screensaver");
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 12;
            var stack = new Gtk.Stack ();
            stack.add_titled (general (), "general", "General");
            stack.add_titled (filevault (), "filevault", "FileVault");
            stack.add_titled (firewall (), "firewall", "Firewall");
            stack.add_titled (privacidad (), "privacy", "Privacy");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            caja.pack_start (pestanas, false, false, 0);
            var marco = marco_lista ();
            marco.add (stack);
            caja.pack_start (marco, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var av = gris (new Gtk.Button.with_label ("Advanced…"));
            av.margin_end = 6;
            pie.pack_end (av, false, false, 0);
            pie.margin_top = 4;
            pie.margin_bottom = 4;
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_SEGURIDAD_PESTANA");        // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            cargando = false;
            return caja;
        }

        // ── General ──────────────────────────────────────────────────────
        Gtk.Widget general () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            pagina.margin_top = 28;
            pagina.margin_start = 60;
            pagina.margin_bottom = 20;
            var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            f.pack_start (new Gtk.Label ("A login password has been set for this user"), false, false, 0);
            var b = new Gtk.Button.with_label ("Change Password…");
            b.clicked.connect (() => cambiar_clave ());
            f.pack_start (b, false, false, 0);
            pagina.pack_start (f, false, false, 0);

            var g = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            g.margin_start = 24;
            var requerir = new Gtk.CheckButton.with_label ("Require password");
            requerir.active = pantalla != null && pantalla.get_boolean ("lock-enabled");
            requerir.toggled.connect (() => { if (!cargando && !prueba && pantalla != null) pantalla.set_boolean ("lock-enabled", requerir.active); });
            g.pack_start (requerir, false, false, 0);
            var retraso = new Gtk.ComboBoxText ();
            for (int i = 0; i < BLOQUEO_S.length; i++) {
                retraso.append (BLOQUEO_S[i].to_string (), BLOQUEO_TXT[i]);
            }
            uint actual = pantalla != null ? pantalla.get_uint ("lock-delay") : 0;
            if (!retraso.set_active_id (actual.to_string ())) {
                retraso.append (actual.to_string (), "%u seconds".printf (actual));
                retraso.set_active_id (actual.to_string ());
            }
            retraso.changed.connect (() => {
                if (!cargando && !prueba && pantalla != null) {
                    pantalla.set_uint ("lock-delay", (uint) int.parse (retraso.get_active_id ()));
                }
            });
            g.pack_start (retraso, false, false, 0);
            g.pack_start (new Gtk.Label ("after sleep or screen saver begins"), false, false, 0);
            pagina.pack_start (g, false, false, 0);

            var m = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            m.margin_start = 24;
            var msg = pantalla != null ? pantalla.get_string ("default-message") : "";
            mensaje_activo = new Gtk.CheckButton.with_label ("Show a message when the screen is locked");
            mensaje_activo.active = msg != "";
            mensaje_activo.toggled.connect (() => mensaje (mensaje_activo));
            m.pack_start (mensaje_activo, false, false, 0);
            var fijar = new Gtk.Button.with_label ("Set Lock Message…");
            fijar.clicked.connect (() => dialogo_mensaje ());
            m.pack_start (fijar, false, false, 0);
            pagina.pack_start (m, false, false, 0);
            var auto = new Gtk.CheckButton.with_label ("Disable automatic login");
            auto.active = true;
            auto.margin_start = 24;
            pagina.pack_start (gris_seg (auto, "Automatic login is set in the login window settings."), false, false, 0);

            var sep = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            sep.margin_top = 24;
            sep.margin_bottom = 24;
            pagina.pack_start (sep, false, false, 0);
            var desde = new Gtk.Label ("Allow apps downloaded from:");
            desde.xalign = 0;
            pagina.pack_start (desde, false, false, 0);
            Gtk.RadioButton? grupo = null;
            string[] textos = { "App Store", "App Store and identified developers" };
            bool[] activas = { false, true };
            for (int i = 0; i < 2; i++) {
                var r = new Gtk.RadioButton.with_label_from_widget (grupo, textos[i]);
                if (grupo == null) {
                    grupo = r;
                }
                r.active = activas[i];
                r.margin_start = 24;
                pagina.pack_start (gris_seg (r, "Linux does not check where an app comes from."), false, false, 0);
            }
            return pagina;
        }

        void cambiar_clave () {
            if (prueba) {
                return;
            }
            try {
                Process.spawn_async (null, { "cinnamon-settings", "user" }, null,
                                     SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL,
                                     () => { Posix.setsid (); }, null);
            } catch (Error e) {
            }
        }

        void mensaje (Gtk.CheckButton casilla) {
            if (cargando || prueba || pantalla == null) {
                return;
            }
            if (!casilla.active) {
                pantalla.set_string ("default-message", "");
            } else if (pantalla.get_string ("default-message") == "") {
                dialogo_mensaje ();
            }
        }

        void dialogo_mensaje () {
            if (pantalla == null) {
                return;
            }
            var d = new Gtk.Dialog ();
            d.transient_for = ventana;
            d.modal = true;
            d.set_decorated (false);
            d.get_style_context ().add_class ("mp-hoja");
            var c = d.get_content_area () as Gtk.Box;
            c.set_spacing (10);
            margenes (c, 20, 20, 20, 20);
            var l = new Gtk.Label ("Enter the message to show when the screen is locked:");
            l.xalign = 0;
            c.pack_start (l, false, false, 0);
            var e = new Gtk.Entry ();
            e.text = pantalla.get_string ("default-message");
            e.width_chars = 40;
            c.pack_start (e, false, false, 0);
            d.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            var ok = d.add_button ("OK", Gtk.ResponseType.OK);
            ok.get_style_context ().add_class ("suggested-action");
            d.set_default_response (Gtk.ResponseType.OK);
            d.show_all ();
            if (d.run () == Gtk.ResponseType.OK && !prueba) {
                pantalla.set_string ("default-message", e.get_text ());
                bool previo = cargando;
                cargando = true;
                mensaje_activo.active = e.get_text () != "";
                cargando = previo;
            }
            d.destroy ();
        }

        // ── FileVault ────────────────────────────────────────────────────
        Gtk.Widget filevault () {
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            pagina.margin = 26;
            pagina.valign = Gtk.Align.START;
            pagina.pack_start (imagen_icono_panel (id, 64), false, false, 0);
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var t = new Gtk.Label ("FileVault secures the data on your disk by encrypting its contents automatically.");
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (34);
            f.pack_start (t, true, true, 0);
            f.pack_end (gris_seg (new Gtk.Button.with_label ("Turn On FileVault…"), "Encrypting the installed disk is not done from here."), false, false, 0);
            c.pack_start (f, false, false, 0);
            var aviso = new Gtk.Label (null);
            aviso.xalign = 0;
            aviso.set_markup ("<span foreground=\"#ff453a\">WARNING:</span> You will need your login password or a recovery key to access your data. If you forget both, the data will be lost.");
            aviso.set_line_wrap (true);
            aviso.set_max_width_chars (70);
            c.pack_start (aviso, false, false, 0);
            bool cifrado = false;
            foreach (var tipo in salida_de ({ "lsblk", "-no", "TYPE" }).split_set (" \t\n")) {
                if (tipo == "crypt") {
                    cifrado = true;
                }
            }
            var fuente = salida_de ({ "findmnt", "-no", "SOURCE", "/" });
            string disco = "";
            if (fuente != "") {
                var etiquetas = salida_de ({ "lsblk", "-no", "LABEL", fuente }).split ("\n");
                disco = etiquetas.length > 0 ? etiquetas[0].strip () : "";
            }
            if (disco == "") {
                disco = Path.get_basename (fuente);
            }
            if (disco == "") {
                disco = "this disk";
            }
            var estado = new Gtk.Label ("FileVault is turned %s for the disk “%s”.".printf (cifrado ? "on" : "off", disco));
            estado.xalign = 0;
            estado.margin_top = 20;
            estado.margin_bottom = 20;
            c.pack_start (estado, false, false, 0);
            pagina.pack_start (c, true, true, 0);
            return pagina;
        }

        // ── Firewall ─────────────────────────────────────────────────────
        Gtk.Widget firewall () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            pagina.margin = 26;
            pagina.valign = Gtk.Align.START;
            bool activo = salida_de ({ "systemctl", "is-active", "ufw" }) == "active";
            var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var punto = new Gtk.Label (null);
            punto.set_markup ("<span foreground=\"%s\">●</span>".printf (activo ? "#37c94b" : "#d0d0d0"));
            f.pack_start (punto, false, false, 0);
            var t = new Gtk.Label ("Firewall: %s".printf (activo ? "On" : "Off"));
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            f.pack_start (t, true, true, 0);
            f.pack_end (gris_seg (new Gtk.Button.with_label ("Turn %s Firewall".printf (activo ? "Off" : "On")), "Changing the firewall needs the administrator."), false, false, 0);
            pagina.pack_start (f, false, false, 0);
            var d = new Gtk.Label (activo ? "This computer’s firewall is currently turned on."
                                          : "This computer’s firewall is currently turned off. All incoming connections to this computer are allowed.");
            d.xalign = 0;
            d.set_line_wrap (true);
            d.set_max_width_chars (60);
            pagina.pack_start (d, false, false, 0);
            var o = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            o.pack_end (gris (new Gtk.Button.with_label ("Firewall Options…")), false, false, 0);
            pagina.pack_start (o, false, false, 0);
            return pagina;
        }

        // ── Privacy ──────────────────────────────────────────────────────
        Gtk.Widget privacidad () {
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            pagina.margin = 16;
            var lista = new Gtk.ListBox ();
            var desplazable = new Gtk.ScrolledWindow (null, null);
            desplazable.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            desplazable.set_size_request (210, 330);
            var paginas = new Gtk.Stack ();
            var cats = categorias ();
            foreach (var cat in cats) {
                var fila = new FilaPrivacidad ();
                var caja_fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                caja_fila.margin = 8;
                var icono = IconosCatalina.de_privacidad (icono_privacidad (cat.nombre), 24);
                if (icono != null) {
                    caja_fila.pack_start (icono, false, false, 0);
                }
                var l = new Gtk.Label (cat.nombre);
                l.xalign = 0;
                caja_fila.pack_start (l, true, true, 0);
                fila.add (caja_fila);
                fila.nombre_cat = cat.nombre;
                lista.add (fila);
                paginas.add_named (pagina_privacidad (cat), cat.nombre);
            }
            lista.row_selected.connect ((f) => {
                var fp = f as FilaPrivacidad;
                if (fp != null) {
                    paginas.set_visible_child_name (fp.nombre_cat);
                }
            });
            desplazable.add (lista);
            var ml = marco_lista ();
            ml.add (desplazable);
            pagina.pack_start (ml, false, false, 0);
            pagina.pack_start (paginas, true, true, 0);
            paginas.show_all ();
            lista.select_row (lista.get_row_at_index (0));
            paginas.set_visible_child_name (cats[0].nombre);
            return pagina;
        }

        static Gtk.Label texto_priv (string t, bool negrita = false) {
            var l = new Gtk.Label (null);
            l.xalign = 0;
            if (negrita) {
                l.set_markup ("<b>%s</b>".printf (Markup.escape_text (t)));
            } else {
                l.set_text (t);
            }
            l.set_line_wrap (true);
            l.set_max_width_chars (48);
            return l;
        }

        static Gtk.Widget boton_priv (string t) {
            var b = new Gtk.Button.with_label (t);
            b.halign = Gtk.Align.END;
            return gris (b);
        }

        Gtk.Widget pagina_privacidad (CategoriaPrivacidad cat) {
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            if (cat.tipo == "ubicacion") {
                var c = new Gtk.CheckButton.with_label ("Enable Location Services");
                c.active = true;
                der.pack_start (gris (c), false, false, 0);
                der.pack_start (texto_priv ("Allow the apps and services below to determine your location."), false, false, 0);
                var marco = marco_lista ();
                marco.set_size_request (-1, 200);
                der.pack_start (gris (marco), true, true, 0);
                var b = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                b.pack_end (boton_priv ("About Location Services & Privacy…"), false, false, 0);
                der.pack_start (b, false, false, 0);
            } else if (cat.tipo == "vacia") {
                var marco = marco_lista ();
                var centro = new Gtk.Label (cat.dato);
                centro.justify = Gtk.Justification.CENTER;
                centro.set_line_wrap (true);
                centro.set_max_width_chars (32);
                marco.add (centro);
                der.pack_start (gris (marco), true, true, 0);
            } else if (cat.tipo == "lista") {
                der.pack_start (texto_priv (cat.dato), false, false, 0);
                var marco = marco_lista ();
                marco.set_size_request (-1, 200);
                der.pack_start (gris (marco), true, true, 0);
                if (cat.con_barra) {
                    var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                    botones.get_style_context ().add_class ("linked");
                    foreach (var t in new string[] { "+", "−" }) {
                        botones.pack_start (gris (new Gtk.Button.with_label (t)), false, false, 0);
                    }
                    der.pack_start (botones, false, false, 0);
                }
            } else if (cat.tipo == "publicidad") {
                der.pack_start (texto_priv ("All Advertisers", true), false, false, 0);
                var limitar = new Gtk.CheckButton.with_label ("Limit Ad Tracking");
                der.pack_start (gris (limitar), false, false, 0);
                der.pack_start (texto_priv ("Opt out of receiving ads targeted to your interests in Apple Apps and your iOS devices. You may still receive the same number of ads, but the ads may be less relevant to you."), false, false, 0);
                der.pack_start (boton_priv ("Reset Advertising Identifier"), false, false, 0);
                var aa = texto_priv ("Advertising in Apple Apps", true);
                aa.margin_top = 12;
                aa.margin_bottom = 12;
                der.pack_start (aa, false, false, 0);
                der.pack_start (texto_priv ("View the information used by Apple to deliver more relevant ads to you in Apple News, Stocks, and the iOS App Store. Your personal data is not provided to third parties."), false, false, 0);
                der.pack_start (boton_priv ("View Ad Information"), false, false, 0);
                var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                pie.pack_end (boton_priv ("About Advertising & Privacy…"), false, false, 0);
                der.pack_end (pie, false, false, 0);
            } else {   // analitica
                der.pack_start (texto_priv ("Help Apple and app developers improve their products and services automatically."), false, false, 0);
                var marco = marco_lista ();
                var desplazable = new Gtk.ScrolledWindow (null, null);
                desplazable.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
                desplazable.set_size_request (-1, 240);
                var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
                col.margin = 8;
                string[] titulos = { "Share Mac Analytics", "Improve Siri & Dictation", "Share with App Developers" };
                string[] detalles = {
                    "Help Apple improve its products and services by automatically sending diagnostics and usage data. Diagnostic data may include locations.",
                    "Help improve Siri and Dictation by allowing Apple to store and review audio of your Siri and Dictation interactions from this device.",
                    "Help app developers improve their apps by allowing Apple to share crash and usage data with them." };
                for (int i = 0; i < 3; i++) {
                    col.pack_start (new Gtk.CheckButton.with_label (titulos[i]), false, false, 0);
                    var d = texto_priv (detalles[i]);
                    d.margin_start = 26;
                    d.get_style_context ().add_class ("mp-sd-detalle");
                    col.pack_start (d, false, false, 0);
                }
                desplazable.add (col);
                marco.add (desplazable);
                der.pack_start (gris (marco), true, true, 0);
                var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                pie.pack_end (boton_priv ("About Analytics and Privacy…"), false, false, 0);
                der.pack_start (pie, false, false, 0);
            }
            return der;
        }
    }
}
