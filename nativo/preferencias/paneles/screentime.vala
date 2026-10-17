/*
 * Screen Time: las diez pantallas de Catalina, en gris (port de settings/screentime.py).
 *
 * Linux no tiene Screen Time: no hay uso que contar ni límites que aplicar. Se dibuja cada pantalla como en las capturas de Catalina
 * (08-pref-com.apple.preference.screentime--*, 16-screen-time-content-privacy-*) pero con la computadora de verdad: el uso, las
 * notificaciones y los «pickups» valen cero; la lista de Always Allowed son las aplicaciones instaladas con «0s». Los estados
 * (Downtime Off, App Limits On, Content & Privacy Off, Screen Time On) son los de la captura. Nada funciona ni debe.
 * Falta el ícono de cada fila de la barra lateral cuando no se sacó del disco de la Mac (deepmap2): entonces la fila va solo con el texto.
 */
namespace Preferencias {

    /** Las dos cuadrículas de App Usage / Notifications / Pickups, sin datos: la semana (S M T W T F S con la raya «avg») y el día (12 AM, 6 AM,
     *  12 PM, 6 PM), con su escala a la derecha. */
    class GraficasST : Gtk.DrawingArea {
        string[] semana;
        string[] dia;

        public GraficasST (string[] escala_semana, string[] escala_dia) {
            semana = escala_semana;
            dia = escala_dia;
            set_size_request (410, 150);
        }

        void cuadricula (Cairo.Context cr, double x, double y, double ancho, double alto, string[] escala, string[] etiquetas, bool avg = false) {
            cr.set_source_rgba (1, 1, 1, 0.12);
            cr.set_line_width (1);
            for (int i = 0; i < 4; i++) {
                double yy = Math.rint (y + alto * i / 3) + 0.5;
                cr.move_to (x, yy);
                cr.line_to (x + ancho, yy);
            }
            for (int i = 0; i <= etiquetas.length; i++) {
                double xx = Math.rint (x + ancho * i / etiquetas.length) + 0.5;
                cr.move_to (xx, y);
                cr.line_to (xx, y + alto);
            }
            cr.stroke ();
            cr.set_source_rgba (1, 1, 1, 0.55);
            cr.set_font_size (10);
            for (int i = 0; i < escala.length; i++) {
                cr.move_to (x + ancho + 6, y + alto * i / 3 + 4);
                cr.show_text (escala[i]);
            }
            for (int i = 0; i < etiquetas.length; i++) {
                cr.move_to (x + ancho * i / etiquetas.length + 2, y + alto + 12);
                cr.show_text (etiquetas[i]);
            }
            if (avg) {
                cr.set_source_rgba (0.2, 0.75, 0.3, 0.9);
                double[] guion = { 3, 3 };
                cr.set_dash (guion, 0);
                double yy = y + alto - 1.5;
                cr.move_to (x, yy);
                cr.line_to (x + ancho, yy);
                cr.stroke ();
                cr.set_dash (null, 0);
                cr.move_to (x + ancho + 6, yy + 3);
                cr.show_text ("avg");
            }
        }

        public override bool draw (Cairo.Context cr) {
            cuadricula (cr, 8, 6, 350, 52, semana, { "S", "M", "T", "W", "T", "F", "S" }, true);
            cuadricula (cr, 8, 82, 350, 44, dia, { "12 AM", "6 AM", "12 PM", "6 PM" });
            return false;
        }
    }

    class FilaST : Gtk.ListBoxRow {
        public string nombre_fila = "";
    }

    public class PanelScreenTime : Panel {
        const string MOTIVO_ST = "Screen Time is not available on this computer.";
        const string[] FILAS = { "App Usage", "Notifications", "Pickups", "", "Downtime", "App Limits", "Communication",
                                 "Always Allowed", "Content & Privacy" };

        public PanelScreenTime () {
            id = "com.apple.preference.screentime";
            nombre = "Screen Time";
            palabras = "screen time, app usage, notifications, pickups, downtime, app limits, communication, always allowed, content privacy";
        }

        static Gtk.Widget gris_st (Gtk.Widget w) {
            w.set_sensitive (false);
            w.set_tooltip_text (MOTIVO_ST);
            return w;
        }

        static Gtk.Label etiq (string texto, bool negrita = false, bool detalle = false, float xalign = 0.0f) {
            var l = new Gtk.Label (null);
            l.xalign = xalign;
            if (negrita) {
                l.set_markup ("<b>%s</b>".printf (Markup.escape_text (texto)));
            } else {
                l.set_text (texto);
            }
            l.set_line_wrap (true);
            l.set_max_width_chars (40);     // sin tope, el ancho natural del texto ensancha toda la ventana
            if (detalle) {
                l.get_style_context ().add_class ("mp-sd-detalle");
            }
            return l;
        }

        static string nombre_usuario () {
            unowned Posix.Passwd? p = Posix.getpwuid (Posix.getuid ());
            if (p != null) {
                var n = (p.pw_gecos ?? "").split (",")[0];
                return n != "" ? n : p.pw_name;
            }
            return Environment.get_user_name ();
        }

        static string[] meses () {
            return { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
        }

        // ── la ventana ───────────────────────────────────────────────────
        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_bottom = 10;
            var paginas = new Gtk.Stack ();
            paginas.add_named (pagina_uso ("Usage", "0m", { "2h", "1h", "0", "" }, { "60m", "30m", "0", "" }, { "Time", "Limits" }, "Productivity"), "App Usage");
            paginas.add_named (pagina_uso ("Notifications", "0", { "30", "15", "0", "" }, { "20", "10", "0", "" }, { "Notifications" }, null), "Notifications");
            paginas.add_named (pagina_uso ("Pickups", "0", { "10", "5", "0", "" }, { "10", "5", "0", "" }, { "Pickups" }, null), "Pickups");
            paginas.add_named (pagina_downtime (), "Downtime");
            paginas.add_named (pagina_limites (), "App Limits");
            paginas.add_named (pagina_comunicacion (), "Communication");
            paginas.add_named (pagina_permitidas (), "Always Allowed");
            paginas.add_named (pagina_contenido (), "Content & Privacy");
            paginas.add_named (pagina_opciones (), "Options");

            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            izq.margin_top = 14;
            izq.set_size_request (188, 480);
            var avatar = gris_st (new Gtk.Image.from_icon_name ("avatar-default", Gtk.IconSize.DIALOG));
            avatar.margin_top = 8;
            avatar.margin_bottom = 8;
            izq.pack_start (avatar, false, false, 0);
            var usuario = new Gtk.ComboBoxText ();
            usuario.append ("u", nombre_usuario ());
            usuario.set_active (0);
            usuario.margin_start = 14;
            usuario.margin_end = 14;
            usuario.margin_top = 8;
            usuario.margin_bottom = 8;
            izq.pack_start (gris_st (usuario), false, false, 0);
            var lista = new Gtk.ListBox ();
            lista.set_selection_mode (Gtk.SelectionMode.SINGLE);
            foreach (var n in FILAS) {
                var fila = new FilaST ();
                if (n == "") {
                    fila.set_selectable (false);
                    fila.set_activatable (false);
                    fila.add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
                } else {
                    fila.add (fila_lateral (n));
                    fila.nombre_fila = n;
                }
                lista.add (fila);
            }
            var opciones = new FilaST ();
            opciones.add (fila_lateral ("Options"));
            opciones.nombre_fila = "Options";
            var pie = new Gtk.ListBox ();
            pie.set_selection_mode (Gtk.SelectionMode.SINGLE);
            lista.row_selected.connect ((f) => {
                var fila = f as FilaST;
                if (fila != null && fila.nombre_fila != "") {
                    pie.unselect_all ();
                    paginas.set_visible_child_name (fila.nombre_fila);
                }
            });
            izq.pack_start (lista, true, true, 0);
            pie.add (opciones);
            pie.row_selected.connect ((f) => {
                if (f != null) {
                    lista.unselect_all ();
                    paginas.set_visible_child_name ("Options");
                }
            });
            izq.pack_start (pie, false, false, 0);
            caja.pack_start (izq, false, false, 0);
            caja.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            der.margin = 12;
            der.set_size_request (440, 480);
            der.pack_start (paginas, true, true, 0);
            var ayuda = new Gtk.Button.with_label ("?");
            ayuda.get_style_context ().add_class ("circular");
            ayuda.set_size_request (24, 24);
            ayuda.halign = Gtk.Align.END;
            der.pack_end (gris_st (ayuda), false, false, 0);
            caja.pack_start (der, true, true, 0);
            caja.show_all ();
            paginas.show_all ();
            lista.select_row (lista.get_row_at_index (0));
            paginas.set_visible_child_name ("App Usage");
            var pedida = Environment.get_variable ("MINT_SCREENTIME_PAGINA");        // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                foreach (var f in lista.get_children ()) {
                    var fila = f as FilaST;
                    if (fila != null && fila.nombre_fila == pedida) {
                        lista.select_row (fila);
                    }
                }
                if (pedida == "Options") {
                    pie.select_row (opciones);
                }
            }
            return caja;
        }

        static string icono_de_fila (string n) {
            if (n == "App Usage") {
                return "Usage";
            }
            if (n == "Content & Privacy") {
                return "Content and Privacy";
            }
            return n;
        }

        /** Una fila de la barra lateral: el ícono de Catalina (si está sacado del disco) y el nombre. */
        Gtk.Widget fila_lateral (string n) {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            caja.margin = 6;
            var icono = IconosCatalina.de_screentime (icono_de_fila (n), 24);
            if (icono != null) {
                caja.pack_start (icono, false, false, 0);
            }
            var l = new Gtk.Label (n);
            l.xalign = 0;
            caja.pack_start (l, true, true, 0);
            return caja;
        }

        // ── App Usage, Notifications y Pickups ───────────────────────────
        Gtk.Widget pagina_uso (string titulo, string valor, string[] escala_semana, string[] escala_dia, string[] columnas, string? leyenda) {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var fecha = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var ahora = new DateTime.now_local ();
            var hoy = "Today, %s %d".printf (meses ()[ahora.get_month () - 1], ahora.get_day_of_month ());
            fecha.pack_end (gris_st (new Gtk.Button.with_label ("›")), false, false, 0);
            fecha.pack_end (gris_st (new Gtk.Button.with_label ("Today")), false, false, 0);
            fecha.pack_end (gris_st (new Gtk.Button.with_label ("‹")), false, false, 0);
            var etq_fecha = new Gtk.Label (hoy + " ⌄");
            etq_fecha.xalign = 1.0f;
            var ef = gris_st (etq_fecha);
            ef.margin_start = 8;
            ef.margin_end = 8;
            fecha.pack_end (ef, false, false, 0);
            pagina.pack_start (fecha, false, false, 0);
            var marco = marco_lista ();
            var interior = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            interior.margin = 12;
            interior.pack_start (etiq (titulo, false, true), false, false, 0);
            var grande = new Gtk.Label (null);
            grande.xalign = 0.0f;
            grande.set_markup ("<span size=\"x-large\">%s</span>".printf (valor));
            interior.pack_start (grande, false, false, 0);
            interior.pack_start (new GraficasST (escala_semana, escala_dia), false, false, 0);
            if (leyenda != null) {
                interior.pack_start (etiq ("■ " + leyenda, false, true), false, false, 0);
                interior.pack_start (etiq (valor), false, false, 0);
            } else {
                interior.pack_start (etiq ("Total " + titulo, false, true), false, false, 0);
                interior.pack_start (etiq (valor), false, false, 0);
            }
            // La tabla: Show: Apps | Categories (solo en App Usage), columnas y la fila All Apps.
            var tabla = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            tabla.margin = 8;
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            if (titulo == "Usage") {
                cab.pack_start (etiq ("Show:", false, true), false, false, 0);
                cab.pack_start (gris_st (new Gtk.Button.with_label ("Apps")), false, false, 0);
                cab.pack_start (etiq ("Categories"), false, false, 0);
            } else {
                cab.pack_start (etiq ("Apps", false, true), false, false, 0);
            }
            foreach (var c in columnas) {
                var ec = etiq (c, false, true);
                ec.margin_start = 12;
                ec.margin_end = 12;
                cab.pack_end (ec, false, false, 0);
            }
            tabla.pack_start (cab, false, false, 0);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            fila.margin_top = 6;
            fila.margin_bottom = 6;
            fila.pack_start (etiq ("All Apps"), false, false, 0);
            var ev = etiq (valor);
            ev.margin_start = 12;
            ev.margin_end = 12;
            fila.pack_end (ev, false, false, 0);
            tabla.pack_start (fila, false, false, 0);
            interior.pack_start (tabla, true, true, 0);
            marco.add (interior);
            pagina.pack_start (marco, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var todos = new Gtk.ComboBoxText ();
            todos.append ("a", "All Devices");
            todos.set_active (0);
            pie.pack_start (gris_st (todos), false, false, 0);
            int h = ahora.get_hour ();
            int h12 = h % 12 == 0 ? 12 : h % 12;
            pie.pack_end (etiq ("Updated today at %d:%02d %s".printf (h12, ahora.get_minute (), h < 12 ? "AM" : "PM"), false, true, 1.0f), false, false, 0);
            pagina.pack_start (pie, false, false, 0);
            return pagina;
        }

        // ── Downtime ─────────────────────────────────────────────────────
        Gtk.Widget cabecera (string estado, string valor, string boton, string texto) {
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var t = new Gtk.Label (null);
            t.xalign = 0.0f;
            t.set_markup ("%s <b>%s</b>".printf (Markup.escape_text (estado), valor));
            fila.pack_start (t, true, true, 0);
            fila.pack_end (gris_st (new Gtk.Button.with_label (boton)), false, false, 0);
            c.pack_start (fila, false, false, 0);
            c.pack_start (etiq (texto), false, false, 0);
            return c;
        }

        Gtk.Widget pagina_downtime () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            pagina.pack_start (cabecera ("Downtime:", "Off", "Turn On…",
                                         "Set a schedule for time away from the screen. During downtime, only apps that you choose to allow and phone calls will be available."), false, false, 0);
            pagina.pack_start (etiq ("Schedule:", true), false, false, 0);
            pagina.pack_start (etiq ("Downtime will apply to all devices that are using iCloud for screen time. A downtime reminder will appear five minutes before downtime."), false, false, 0);
            var r1 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var every = new Gtk.RadioButton.with_label_from_widget (null, "Every Day");
            r1.pack_start (every, false, false, 0);
            var e1 = new Gtk.Entry ();
            e1.text = "10:00 PM";
            e1.width_chars = 9;
            r1.pack_start (e1, false, false, 0);
            r1.pack_start (new Gtk.Label ("to"), false, false, 0);
            var e2 = new Gtk.Entry ();
            e2.text = "6:00 AM";
            e2.width_chars = 9;
            r1.pack_start (e2, false, false, 0);
            pagina.pack_start (gris_st (r1), false, false, 0);
            pagina.pack_start (gris_st (new Gtk.RadioButton.with_label_from_widget (every, "Custom")), false, false, 0);
            return pagina;
        }

        // ── App Limits ───────────────────────────────────────────────────
        Gtk.Widget pagina_limites () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            pagina.pack_start (cabecera ("App Limits:", "On", "Turn Off…",
                                         "Set daily time limits for app categories you want to manage. App limits reset every day at midnight."), false, false, 0);
            var marco = marco_lista ();
            marco.set_size_request (-1, 230);
            var cab = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            fila.margin = 6;
            fila.pack_start (etiq ("Limits", false, true), true, true, 0);
            fila.pack_start (etiq ("Time Amount", false, true), true, true, 0);
            cab.pack_start (fila, false, false, 0);
            marco.add (cab);
            pagina.pack_start (gris_st (marco), false, false, 0);
            pagina.pack_start (etiq ("App limits apply to all devices that are using iCloud for screen time. A notification will appear five minutes before the limit expires."), false, false, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var t in new string[] { "+", "−" }) {
                botones.pack_start (gris_st (new Gtk.Button.with_label (t)), false, false, 0);
            }
            pie.pack_start (botones, false, false, 0);
            pie.pack_end (gris_st (new Gtk.Button.with_label ("Edit Limit…")), false, false, 0);
            pagina.pack_start (pie, false, false, 0);
            return pagina;
        }

        // ── Communication ────────────────────────────────────────────────
        Gtk.Widget radios (string titulo, string[] opciones, int activa, string nota, int con_editar = -1) {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            caja.pack_start (etiq (titulo), false, false, 0);
            Gtk.RadioButton? grupo = null;
            for (int i = 0; i < opciones.length; i++) {
                var r = new Gtk.RadioButton.with_label_from_widget (grupo, opciones[i]);
                if (grupo == null) {
                    grupo = r;
                }
                r.active = i == activa;
                var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
                fila.pack_start (r, false, false, 0);
                if (con_editar == i) {
                    fila.pack_start (new Gtk.Button.with_label ("Edit…"), false, false, 0);
                }
                caja.pack_start (gris_st (fila), false, false, 0);
            }
            var n = etiq (nota, false, true);
            n.margin_start = 20;
            caja.pack_start (n, false, false, 0);
            return caja;
        }

        Gtk.Widget pagina_comunicacion () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 14);
            pagina.pack_start (etiq ("Limits apply to Phone, FaceTime, Messages, and iCloud contacts. Communication to known emergency numbers identified by your carrier is always allowed."), false, false, 0);
            pagina.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);
            pagina.pack_start (radios ("During screen time, allow communication with:",
                                       { "Contacts Only", "Contacts & Groups with at Least One Contact", "Everyone" }, 2,
                                       "Allow one-on-one and group conversations with anyone including unknown numbers."), false, false, 0);
            pagina.pack_start (radios ("During downtime, allow communication with:", { "Specific Contacts", "Everyone" }, 1,
                                       "During downtime, allow one-on-one and group conversations with anyone including unknown numbers.", 0), false, false, 0);
            return pagina;
        }

        // ── Always Allowed ───────────────────────────────────────────────
        Gtk.Widget pagina_permitidas () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            pagina.pack_start (etiq ("Always allowed apps and contacts are available during downtime, or if you selected the “All Apps & Categories” app limit."), false, false, 0);
            pagina.pack_start (radios ("During downtime, allow communication with:", { "Specific Contacts", "Everyone" }, 1,
                                       "During downtime, allow one-on-one and group conversations with anyone including unknown numbers.", 0), false, false, 0);
            var cab = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            cab.pack_start (etiq ("Allowed Apps:"), true, true, 0);
            cab.pack_end (gris_st (new Gtk.SearchEntry ()), false, false, 0);
            pagina.pack_start (cab, false, false, 0);
            var marco = marco_lista ();
            var desplazable = new Gtk.ScrolledWindow (null, null);
            desplazable.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            desplazable.set_size_request (-1, 250);
            var lista = new Gtk.ListBox ();
            lista.set_selection_mode (Gtk.SelectionMode.NONE);
            var cab_t = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            cab_t.margin = 6;
            cab_t.pack_start (etiq ("Sort by Daily Usage ⌄"), true, true, 0);
            var du = etiq ("Daily Usage", false, true);
            du.margin_start = 6;
            du.margin_end = 6;
            cab_t.pack_end (du, false, false, 0);
            lista.add (cab_t);
            // Solo aplicaciones: los módulos de configuración de Cinnamon también son .desktop
            var apps = new GenericArray<AppInfo> ();
            foreach (var a in AppInfo.get_all ()) {
                var d = a as DesktopAppInfo;
                var cat = d != null ? (d.get_categories () ?? "") : "";
                bool ajustes = false;
                foreach (var c in cat.split (";")) {
                    if (c == "Settings") {
                        ajustes = true;
                    }
                }
                if (a.should_show () && !ajustes && !(a.get_id () ?? "").has_prefix ("cinnamon-settings")) {
                    apps.add (a);
                }
            }
            apps.sort ((a, b) => strcmp (a.get_name ().down (), b.get_name ().down ()));
            for (int i = 0; i < apps.length && i < 40; i++) {
                var a = apps[i];
                var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                fila.margin = 5;
                fila.pack_start (new Gtk.CheckButton (), false, false, 0);
                var icono = a.get_icon ();
                if (icono != null) {
                    var imagen = new Gtk.Image.from_gicon (icono, Gtk.IconSize.LARGE_TOOLBAR);
                    imagen.set_pixel_size (24);
                    fila.pack_start (imagen, false, false, 0);
                }
                var nl = new Gtk.Label (a.get_name ());
                nl.xalign = 0;
                fila.pack_start (nl, true, true, 0);
                var cero = etiq ("0s");
                cero.margin_start = 6;
                cero.margin_end = 6;
                fila.pack_end (cero, false, false, 0);
                lista.add (fila);
            }
            desplazable.add (lista);
            marco.add (gris_st (desplazable));
            pagina.pack_start (marco, true, true, 0);
            return pagina;
        }

        // ── Content & Privacy ────────────────────────────────────────────
        /** Una columna «Allow:» con sus casillas. */
        Gtk.Widget casillas (string[] textos, bool[] marcadas, string titulo = "") {
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var t = etiq (titulo, false, true, 1.0f);
            t.set_size_request (80, -1);
            fila.pack_start (t, false, false, 0);
            var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            for (int i = 0; i < textos.length; i++) {
                var c = new Gtk.CheckButton.with_label (textos[i]);
                c.active = marcadas[i];
                col.pack_start (c, false, false, 0);
            }
            fila.pack_start (col, false, false, 0);
            return fila;
        }

        Gtk.Widget pagina_contenido () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            pagina.pack_start (cabecera ("Content & Privacy Restrictions:", "Off", "Turn On…",
                                         "Restrict explicit content, purchases, downloads, and privacy settings."), false, false, 0);
            var pestanas = new Gtk.Stack ();
            // Content
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var web = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var t = etiq ("Web Content:", false, true, 1.0f);
            t.set_size_request (80, -1);
            web.pack_start (t, false, false, 0);
            var rds = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            Gtk.RadioButton? grupo = null;
            string[] accesos = { "Unrestricted Access", "Limit Adult Websites", "Allowed Websites Only" };
            for (int i = 0; i < 3; i++) {
                var r = new Gtk.RadioButton.with_label_from_widget (grupo, accesos[i]);
                if (grupo == null) {
                    grupo = r;
                }
                r.active = i == 1;
                rds.pack_start (r, false, false, 0);
            }
            rds.pack_start (new Gtk.Button.with_label ("Customize…"), false, false, 0);
            web.pack_start (rds, false, false, 0);
            c.pack_start (web, false, false, 0);
            c.pack_start (casillas ({ "Explicit Language in Siri & Dictionary", "Web Search Content in Siri" }, { true, true }, "Allow:"), false, false, 0);
            c.pack_start (casillas ({ "Music Profiles" }, { true }), false, false, 0);
            c.pack_start (casillas ({ "Multiplayer Games in Game Center", "Adding Friends in Game Center" }, { true, true }), false, false, 0);
            pestanas.add_titled (gris_st (c), "Content", "Content");
            // Stores
            var s = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var t2 = etiq ("Ratings for:", false, true, 1.0f);
            t2.set_size_request (80, -1);
            fila.pack_start (t2, false, false, 0);
            var pais = new Gtk.ComboBoxText ();
            pais.append ("p", "Dominican Republic");
            pais.set_active (0);
            fila.pack_start (pais, true, true, 0);
            s.pack_start (fila, false, false, 0);
            foreach (var nombre_c in new string[] { "Movies", "TV Shows", "Apps" }) {
                var f = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
                var e = etiq (nombre_c == "Movies" ? "Allowed Content:" : "", false, true, 1.0f);
                e.set_size_request (80, -1);
                f.pack_start (e, false, false, 0);
                f.pack_start (etiq (nombre_c), false, false, 0);
                f.pack_end (new Gtk.ComboBoxText (), false, false, 0);
                s.pack_start (f, false, false, 0);
            }
            s.pack_start (casillas ({ "Explicit Books", "Explicit Music, Podcasts & News" }, { false, false }), false, false, 0);
            s.pack_start (casillas ({ "Installing Apps", "Deleting Apps", "In-app Purchases" }, { true, true, true }, "Allow on iOS:"), false, false, 0);
            var pw = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            var e3 = etiq ("Require Password:", false, true, 1.0f);
            e3.set_size_request (80, -1);
            pw.pack_start (e3, false, false, 0);
            var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            var a1 = new Gtk.RadioButton.with_label_from_widget (null, "Always Require");
            var a2 = new Gtk.RadioButton.with_label_from_widget (a1, "Require after 15 minutes");
            a2.active = true;
            col.pack_start (a1, false, false, 0);
            col.pack_start (a2, false, false, 0);
            col.pack_start (etiq ("Require a password for additional purchases after making a purchase from the iTunes, Book, or App Store.", false, true), false, false, 0);
            pw.pack_start (col, false, false, 0);
            s.pack_start (pw, false, false, 0);
            pestanas.add_titled (gris_st (s), "Stores", "Stores");
            // Apps
            var a = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            a.pack_start (casillas ({ "Camera", "Books Store", "Siri & Dictation" }, { true, true, true }, "Allow:"), false, false, 0);
            a.pack_start (casillas ({ "Mail", "Safari", "FaceTime", "Wallet", "CarPlay", "iTunes Store", "Podcasts", "AirDrop", "Screen Recording" },
                                    { true, true, true, false, false, true, true, true, true }, "Allow on iOS:"), false, false, 0);
            pestanas.add_titled (gris_st (a), "Apps", "Apps");
            // Other
            var o = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            o.pack_start (etiq ("Restricting changes locks the current settings. The screen time passcode will be required to make changes. Restrictions affect iOS only.", false, true), false, false, 0);
            o.pack_start (casillas ({ "Passcode Changes", "Account Changes", "Cellular Data Changes", "Do Not Disturb While Driving", "TV Provider", "Background App Activities" },
                                    { true, true, true, true, true, true }, "Allow Changes:"), false, false, 0);
            var b = new Gtk.Button.with_label ("Open Privacy Settings…");
            b.halign = Gtk.Align.CENTER;
            b.margin_top = 12;
            b.margin_bottom = 12;
            o.pack_start (b, false, false, 0);
            pestanas.add_titled (gris_st (o), "Other", "Other");
            // Los cuatro segmentos con su ancho natural (el StackSwitcher los iguala al más ancho y la ventana se ensancha).
            var selector = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            selector.get_style_context ().add_class ("linked");
            selector.halign = Gtk.Align.CENTER;
            selector.get_style_context ().add_class ("mp-pestanas");
            Gtk.RadioButton? primero = null;
            foreach (var nombre_p in new string[] { "Content", "Stores", "Apps", "Other" }) {
                var rb = new Gtk.RadioButton.with_label_from_widget (primero, nombre_p);
                rb.set_mode (false);
                if (primero == null) {
                    primero = rb;
                }
                var destino = nombre_p;
                rb.toggled.connect (() => { if (rb.active) pestanas.set_visible_child_name (destino); });
                selector.pack_start (rb, false, false, 0);
            }
            pagina.pack_start (selector, false, false, 0);
            pagina.pack_start (pestanas, true, true, 0);
            return pagina;
        }

        // ── Options ──────────────────────────────────────────────────────
        Gtk.Widget pagina_opciones () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            pagina.pack_start (cabecera ("Screen Time:", "On", "Turn Off…", ""), false, false, 0);
            var compartir = new Gtk.CheckButton.with_label ("Share across devices");
            compartir.active = true;
            pagina.pack_start (gris_st (compartir), false, false, 0);
            pagina.pack_start (etiq ("You can enable this on any iPhone, iPad, or Mac signed in to iCloud to report your combined screen time.", false, true), false, false, 0);
            var clave = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            clave.pack_start (new Gtk.CheckButton.with_label ("Use Screen Time Passcode"), true, true, 0);
            clave.pack_end (new Gtk.Button.with_label ("Change Passcode…"), false, false, 0);
            pagina.pack_start (gris_st (clave), false, false, 0);
            pagina.pack_start (etiq ("Use a passcode to secure Screen Time settings, and to allow for more time when limits expire.", false, true), false, false, 0);
            return pagina;
        }
    }
}
