/*
 * Notifications: el panel de Catalina (Screen Shot 2026-10-14 at 12.14.19 AM con Do Not Disturb y 12.14.33 AM con una app
 * escogida); port de settings/avisos.py.
 *
 * Cinnamon no filtra las notificaciones por app ni tiene horario de No Molestar: todo lo de esta pantalla se dibuja como en la
 * captura, en gris, como en una Mac sin esa función. La lista de la izquierda son las apps instaladas. Lo que Cinnamon sí sabe
 * (duración, posición, pantalla) no está en Catalina y queda en «Advanced».
 */
namespace Preferencias {

    class FilaAviso : Gtk.ListBoxRow {
        public string pagina = "dnd";
        public string nombre_app = "";
    }

    public class PanelNotifications : Panel {
        const string TEXTO = "Notification Center shows your alerts in the upper-right of your screen, without interrupting what you’re doing. Show and hide Notification Center by clicking its icon in the menu bar.";
        const string MOTIVO_AVISOS = "Notifications cannot be set per app on this computer.";
        Gtk.Label? titulo_app = null;
        Gtk.Label? estilo_app = null;

        public PanelNotifications () {
            id = "com.apple.preference.notifications";
            nombre = "Notifications";
            palabras = "notifications, alerts, banners, do not disturb, badges, notification center";
        }

        static Gtk.Widget gris_avisos (Gtk.Widget w) {
            w.set_sensitive (false);
            w.set_tooltip_text (MOTIVO_AVISOS);
            return w;
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 16, 16, 16, 16);
            var t = new Gtk.Label (TEXTO);
            t.xalign = 0;
            t.set_line_wrap (true);
            t.set_max_width_chars (80);
            caja.pack_start (t, false, false, 0);

            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var lista = new Gtk.ListBox ();
            lista.set_size_request (215, 330);
            var derecha = new Gtk.Stack ();
            derecha.add_named (pagina_no_molestar (), "dnd");
            derecha.add_named (pagina_app (), "app");
            var apps = new GenericArray<AppInfo> ();
            foreach (var a in AppInfo.get_all ()) {
                if (!a.should_show ()) {
                    continue;
                }
                var d = a as DesktopAppInfo;
                var categorias = d != null ? (d.get_categories () ?? "") : "";
                if ("Settings" in categorias) {
                    continue;
                }
                apps.add (a);
            }
            apps.sort ((a, b) => strcmp (a.get_display_name ().down (), b.get_display_name ().down ()));
            var primera = new FilaAviso ();
            agregar_fila (lista, primera, "Do Not Disturb", "dnd", "");
            for (int i = 0; i < apps.length && i < 60; i++) {
                agregar_fila (lista, new FilaAviso (), apps[i].get_display_name (), "app", "Badges, Sounds, Banners");
            }
            lista.row_selected.connect ((f) => {
                var fila = f as FilaAviso;
                if (fila != null) {
                    derecha.set_visible_child_name (fila.pagina);
                    titulo_app.set_text ("Allow Notifications from %s".printf (fila.nombre_app));
                    estilo_app.set_text ("%s alert style:".printf (fila.nombre_app));
                }
            });
            var pant = new Gtk.ScrolledWindow (null, null);
            pant.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            pant.set_min_content_width (215);
            pant.add (lista);
            var m1 = marco_lista ();
            var m2 = marco_lista ();
            m1.add (pant);
            m2.add (derecha);
            cuerpo.pack_start (m1, false, false, 0);
            cuerpo.pack_start (m2, true, true, 0);
            caja.pack_start (cuerpo, true, true, 0);

            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            pie.pack_start (new Gtk.Label ("Notification Center sort order:"), false, false, 0);
            var orden = new Gtk.ComboBoxText ();
            orden.append ("r", "Recents");
            orden.set_active (0);
            pie.pack_start (gris_avisos (orden), false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            derecha.show_all ();
            lista.select_row (lista.get_row_at_index (0));
            derecha.set_visible_child_name ("dnd");
            return caja;
        }

        void agregar_fila (Gtk.ListBox lista, FilaAviso fila, string nombre, string pagina, string sub) {
            var c = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            c.margin = 5;
            var l = new Gtk.Label (nombre);
            l.xalign = 0;
            c.pack_start (l, false, false, 0);
            if (sub != "") {
                var s = new Gtk.Label (sub);
                s.xalign = 0;
                s.get_style_context ().add_class ("mp-sd-detalle");
                c.pack_start (s, false, false, 0);
            }
            fila.add (c);
            fila.pagina = pagina;
            fila.nombre_app = nombre;
            lista.add (fila);
        }

        Gtk.Widget pagina_no_molestar () {
            var p = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            p.margin = 16;
            var t = new Gtk.Label ("Turn on Do Not Disturb in Notification Center");
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            p.pack_start (t, false, false, 0);
            var d = new Gtk.Label ("Banners and alerts will be hidden and notification sounds will be silenced.");
            d.xalign = 0;
            d.set_line_wrap (true);
            d.set_max_width_chars (48);
            d.get_style_context ().add_class ("mp-sd-detalle");
            p.pack_start (d, false, false, 0);
            var turn = new Gtk.Label ("Turn on Do Not Disturb:");
            turn.xalign = 0;
            turn.margin_top = 8;
            turn.margin_bottom = 8;
            p.pack_start (turn, false, false, 0);
            var desde = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var c = new Gtk.CheckButton.with_label ("From:");
            desde.pack_start (gris_avisos (c), false, false, 0);
            foreach (var hora in new string[] { "10:00 PM", "7:00 AM" }) {
                var e = new Gtk.Entry ();
                e.text = hora;
                e.width_chars = 9;
                desde.pack_start (gris_avisos (e), false, false, 0);
                if (hora.has_prefix ("10")) {
                    desde.pack_start (new Gtk.Label ("to:"), false, false, 0);
                }
            }
            p.pack_start (desde, false, false, 0);
            foreach (var texto in new string[] { "When the display is sleeping", "When the screen is locked",
                                                  "When mirroring to TVs and projectors" }) {
                var cb = new Gtk.CheckButton.with_label (texto);
                cb.active = true;
                p.pack_start (gris_avisos (cb), false, false, 0);
            }
            var cuando = new Gtk.Label ("When Do Not Disturb is turned on:");
            cuando.xalign = 0;
            cuando.margin_top = 8;
            cuando.margin_bottom = 8;
            p.pack_start (cuando, false, false, 0);
            foreach (var texto in new string[] { "Allow calls from everyone", "Allow repeated calls" }) {
                p.pack_start (gris_avisos (new Gtk.CheckButton.with_label (texto)), false, false, 0);
            }
            return p;
        }

        Gtk.Widget pagina_app () {
            var p = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            p.margin = 16;
            var sw = new Gtk.Switch ();
            sw.active = true;
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            fila.pack_start (gris_avisos (sw), false, false, 0);
            titulo_app = new Gtk.Label ("Allow Notifications");
            titulo_app.xalign = 0;
            titulo_app.get_style_context ().add_class ("mp-titulo-negrita");
            fila.pack_start (titulo_app, false, false, 0);
            p.pack_start (fila, false, false, 0);
            estilo_app = new Gtk.Label ("Alert style:");
            estilo_app.xalign = 0;
            p.pack_start (estilo_app, false, false, 0);
            var estilos = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            Gtk.RadioButton? grupo = null;
            string[] claves = { "none", "banners", "alerts" };
            string[] nombres = { "None", "Banners", "Alerts" };
            for (int i = 0; i < 3; i++) {
                var r = new Gtk.RadioButton.with_label_from_widget (grupo, nombres[i]);
                if (grupo == null) {
                    grupo = r;
                }
                r.active = claves[i] == "banners";
                estilos.pack_start (r, false, false, 0);
            }
            p.pack_start (gris_avisos (estilos), false, false, 0);
            var nota = new Gtk.Label ("Banners appear in the upper-right corner and go away automatically. Alerts stay on screen until dismissed.");
            nota.xalign = 0;
            nota.set_line_wrap (true);
            nota.set_max_width_chars (48);
            nota.get_style_context ().add_class ("mp-sd-detalle");
            p.pack_start (nota, false, false, 0);
            foreach (var texto in new string[] { "Show notifications on lock screen", "Show notification preview", "Show in Notification Center",
                                                  "Badge app icon", "Play sound for notifications" }) {
                var c = new Gtk.CheckButton.with_label (texto);
                c.active = true;
                p.pack_start (gris_avisos (c), false, false, 0);
            }
            return p;
        }
    }
}
