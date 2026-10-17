/*
 * Users & Groups: el panel de Catalina (Screen Shot 2026-10-14 at 12.15.36 AM Password, 12.15.40 AM Login Items, 12.15.45 AM Login
 * Options); port de settings/usuarios.py.
 *
 * Password: la foto (~/.face), el nombre completo (GECOS de /etc/passwd) y Change Password…, que abre el módulo de usuario de
 * Cinnamon (la clave se cambia con polkit allí). Login Items: las apps de ~/.config/autostart (menos las de mint-macos, que son
 * piezas del propio sistema); + añade una app y − quita la entrada (la aparta a ~/.local/share/mint-macos/respaldos/autostart-quitados,
 * no la borra). Guest User, Groups, Login Options (todas las opciones), el candado y la casilla Hide no tienen equivalente de usuario
 * aquí: se dibujan como en las capturas, en gris. No hay captura con el candado abierto ni de Change Password…, la hoja + o los grupos.
 */
namespace Preferencias {

    public class PanelUsers : Panel {
        // MINT_USUARIOS_PRUEBA: no abre ni cambia nada.
        bool prueba = Environment.get_variable ("MINT_USUARIOS_PRUEBA") != null;
        Gtk.ListStore items;
        Gtk.TreeView arbol;

        public PanelUsers () {
            id = "com.apple.preferences.users";
            nombre = "Users & Groups";
            palabras = "users, groups, account, password, login items, startup, login options, guest";
        }

        static string autoarranque () {
            return Path.build_filename (Environment.get_home_dir (), ".config", "autostart");
        }

        static void usuario (out string nombre, out bool admin) {
            unowned Posix.Passwd? p = Posix.getpwuid (Posix.getuid ());
            var gecos = p != null ? (p.pw_gecos ?? "") : "";
            var primero = gecos.split (",")[0];
            var login = p != null ? p.pw_name : Environment.get_user_name ();
            nombre = primero != "" ? primero : login;
            admin = false;
            foreach (var grupo in new string[] { "sudo", "admin" }) {
                var linea = salida_de ({ "getent", "group", grupo });
                int i = linea.last_index_of (":");
                if (i >= 0) {
                    foreach (var m in linea.substring (i + 1).split (",")) {
                        if (m.strip () == login) {
                            admin = true;
                        }
                    }
                }
            }
        }

        static Gdk.Pixbuf? foto (int lado) {
            foreach (var n in new string[] { ".face", ".face.icon" }) {
                try {
                    return new Gdk.Pixbuf.from_file_at_size (Path.build_filename (Environment.get_home_dir (), n), lado, lado);
                } catch (Error e) {
                }
            }
            return null;
        }

        class Entrada {
            public string nombre;
            public string ruta;
            public string tipo;
        }

        /** [(nombre, ruta, tipo)] de las apps de ~/.config/autostart que se abren al entrar (sin las de mint-macos). */
        static List<Entrada> entradas_de_inicio () {
            var salida = new List<Entrada> ();
            var nombres = new GenericArray<string> ();
            try {
                var dir = Dir.open (autoarranque ());
                string? n;
                while ((n = dir.read_name ()) != null) {
                    if (n.has_suffix (".desktop")) {
                        nombres.add (n);
                    }
                }
            } catch (Error e) {
                return salida;
            }
            nombres.sort ((a, b) => strcmp (a, b));
            for (int i = 0; i < nombres.length; i++) {
                var n = nombres[i];
                if (n.has_prefix ("mint-macos")) {
                    continue;
                }
                var ruta = Path.build_filename (autoarranque (), n);
                var kf = new KeyFile ();
                try {
                    kf.load_from_file (ruta, KeyFileFlags.NONE);
                    var g = "Desktop Entry";
                    if (!kf.has_group (g)) {
                        continue;
                    }
                    var oculto = kf.has_key (g, "Hidden") ? kf.get_string (g, "Hidden").down () : "false";
                    var activo = kf.has_key (g, "X-GNOME-Autostart-enabled") ? kf.get_string (g, "X-GNOME-Autostart-enabled").down () : "true";
                    if (oculto == "true" || activo == "false") {
                        continue;
                    }
                    var e = new Entrada ();
                    e.nombre = kf.has_key (g, "Name") ? kf.get_string (g, "Name") : n;
                    e.ruta = ruta;
                    e.tipo = "Application";
                    salida.append (e);
                } catch (Error e) {
                    continue;
                }
            }
            return salida;
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 14, 14, 14, 14);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var marco = marco_lista ();
            var col = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            col.set_size_request (190, 300);
            string nombre_u;
            bool admin;
            usuario (out nombre_u, out admin);
            var enc = new Gtk.Label ("Current User");
            enc.xalign = 0;
            enc.margin = 6;
            enc.get_style_context ().add_class ("mp-sd-detalle");
            col.pack_start (enc, false, false, 0);
            var actual = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actual.margin = 6;
            var pb = foto (32);
            actual.pack_start (pb != null ? new Gtk.Image.from_pixbuf (pb) : new Gtk.Image.from_icon_name ("avatar-default", Gtk.IconSize.DND),
                               false, false, 0);
            var v = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var ln = new Gtk.Label (nombre_u);
            ln.xalign = 0;
            v.pack_start (ln, false, false, 0);
            var r = new Gtk.Label (admin ? "Admin" : "Standard");
            r.xalign = 0;
            r.get_style_context ().add_class ("mp-sd-detalle");
            v.pack_start (r, false, false, 0);
            actual.pack_start (v, true, true, 0);
            col.pack_start (actual, false, false, 0);
            var otros = new Gtk.Label ("Other Users");
            otros.xalign = 0;
            otros.margin = 6;
            otros.get_style_context ().add_class ("mp-sd-detalle");
            col.pack_start (otros, false, false, 0);
            var invitado = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            invitado.margin = 6;
            invitado.pack_start (new Gtk.Image.from_icon_name ("avatar-default", Gtk.IconSize.LARGE_TOOLBAR), false, false, 0);
            var iv = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var g1 = new Gtk.Label ("Guest User");
            g1.xalign = 0;
            iv.pack_start (g1, false, false, 0);
            var g2 = new Gtk.Label ("Off");
            g2.xalign = 0;
            iv.pack_start (g2, false, false, 0);
            invitado.pack_start (iv, true, true, 0);
            invitado.set_sensitive (false);
            invitado.set_tooltip_text ("The guest session is set in the login window settings.");
            col.pack_start (invitado, false, false, 0);
            var grupos = new Gtk.Label ("Groups");
            grupos.xalign = 0;
            grupos.margin = 6;
            gris (grupos);
            col.pack_start (grupos, false, false, 0);
            col.pack_start (new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0), true, true, 0);
            col.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);
            var opciones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            opciones.margin = 8;
            opciones.pack_start (new Gtk.Image.from_icon_name ("go-home-symbolic", Gtk.IconSize.LARGE_TOOLBAR), false, false, 0);
            opciones.pack_start (new Gtk.Label ("Login Options"), false, false, 0);
            opciones.set_sensitive (false);
            opciones.set_tooltip_text ("The login window options are set by the system administrator.");
            col.pack_start (opciones, false, false, 0);
            marco.add (col);
            izq.pack_start (marco, true, true, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            botones.pack_start (gris (new Gtk.Button.with_label ("+")), false, false, 0);
            botones.pack_start (gris (new Gtk.Button.with_label ("−")), false, false, 0);
            botones.margin_top = 4;
            botones.margin_bottom = 4;
            izq.pack_start (botones, false, false, 0);
            cuerpo.pack_start (izq, false, false, 0);

            var stack = new Gtk.Stack ();
            stack.add_titled (pagina_clave (nombre_u), "password", "Password");
            stack.add_titled (pagina_inicio (), "items", "Login Items");
            var pestanas = new Gtk.StackSwitcher ();
            pestanas.stack = stack;
            pestanas.halign = Gtk.Align.CENTER;
            pestanas.get_style_context ().add_class ("mp-pestanas");
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            der.pack_start (pestanas, false, false, 0);
            var m2 = marco_lista ();
            m2.add (stack);
            der.pack_start (m2, true, true, 0);
            cuerpo.pack_start (der, true, true, 0);
            caja.pack_start (cuerpo, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var candado = new Gtk.Image.from_icon_name ("changes-prevent-symbolic", Gtk.IconSize.LARGE_TOOLBAR);
            candado.set_sensitive (false);
            candado.set_tooltip_text ("Changes to other users need the administrator password.");
            pie.pack_start (candado, false, false, 0);
            pie.pack_start (new Gtk.Label ("Click the lock to make changes."), false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            var pedida = Environment.get_variable ("MINT_USUARIOS_PESTANA");        // solo para las pruebas visuales
            if (pedida != null && pedida != "") {
                stack.set_visible_child_name (pedida);
            }
            return caja;
        }

        // ── Password ─────────────────────────────────────────────────────
        Gtk.Widget pagina_clave (string nombre_u) {
            var pagina = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            pagina.margin = 18;
            pagina.valign = Gtk.Align.START;
            var pb = foto (64);
            pagina.pack_start (pb != null ? new Gtk.Image.from_pixbuf (pb) : new Gtk.Image.from_icon_name ("avatar-default", Gtk.IconSize.DIALOG),
                               false, false, 0);
            var t = new Gtk.Label (nombre_u);
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo-negrita");
            pagina.pack_start (t, true, true, 0);
            var b = new Gtk.Button.with_label ("Change Password…");
            b.clicked.connect (() => cambiar_clave ());
            pagina.pack_start (b, false, false, 0);
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

        // ── Login Items ──────────────────────────────────────────────────
        Gtk.Widget pagina_inicio () {
            var pagina = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            pagina.margin = 16;
            var cab = new Gtk.Label ("These items will open automatically when you log in:");
            cab.xalign = 0;
            pagina.pack_start (cab, false, false, 0);
            items = new Gtk.ListStore (4, typeof (string), typeof (string), typeof (string), typeof (bool));
            arbol = new Gtk.TreeView.with_model (items);
            arbol.append_column (new Gtk.TreeViewColumn.with_attributes ("Item", new Gtk.CellRendererText (), "text", 0, null));
            arbol.append_column (new Gtk.TreeViewColumn.with_attributes ("Kind", new Gtk.CellRendererText (), "text", 2, null));
            var hide = new Gtk.CellRendererToggle ();
            hide.activatable = false;
            arbol.append_column (new Gtk.TreeViewColumn.with_attributes ("Hide", hide, "active", 3, null));
            var pant = new Gtk.ScrolledWindow (null, null);
            pant.set_size_request (-1, 190);
            pant.add (arbol);
            var m = marco_lista ();
            m.add (pant);
            pagina.pack_start (m, true, true, 0);
            var n = new Gtk.Label ("To hide an application when you log in, select the checkbox in the Hide column next to the application.");
            n.xalign = 0;
            n.set_line_wrap (true);
            n.set_max_width_chars (60);
            n.get_style_context ().add_class ("mp-sd-detalle");
            pagina.pack_start (n, false, false, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            var mas = new Gtk.Button.with_label ("+");
            mas.clicked.connect (() => agregar ());
            var menos = new Gtk.Button.with_label ("−");
            menos.clicked.connect (() => quitar ());
            botones.pack_start (mas, false, false, 0);
            botones.pack_start (menos, false, false, 0);
            pagina.pack_start (botones, false, false, 0);
            recargar ();
            return pagina;
        }

        void recargar () {
            items.clear ();
            foreach (var e in entradas_de_inicio ()) {
                Gtk.TreeIter it;
                items.append (out it);
                items.set (it, 0, e.nombre, 1, e.ruta, 2, e.tipo, 3, false, -1);
            }
        }

        void agregar () {
            var d = Object.new (typeof (Gtk.AppChooserDialog), "transient-for", ventana, "modal", true, null) as Gtk.AppChooserDialog;
            if (d.run () == Gtk.ResponseType.OK && !prueba) {
                var info = d.get_app_info () as DesktopAppInfo;
                var origen = info != null ? info.get_filename () : null;
                if (origen != null && FileUtils.test (origen, FileTest.IS_REGULAR)) {
                    DirUtils.create_with_parents (autoarranque (), 0755);
                    var destino = Path.build_filename (autoarranque (), Path.get_basename (origen));
                    if (!FileUtils.test (destino, FileTest.EXISTS)) {
                        try {
                            string texto;
                            FileUtils.get_contents (origen, out texto);
                            FileUtils.set_contents (destino, texto);
                        } catch (Error e) {
                        }
                    }
                }
            }
            d.destroy ();
            recargar ();
        }

        void quitar () {
            Gtk.TreeModel modelo;
            Gtk.TreeIter it;
            if (!arbol.get_selection ().get_selected (out modelo, out it) || prueba) {
                return;
            }
            string ruta;
            modelo.get (it, 1, out ruta, -1);
            if (Path.get_dirname (ruta) == autoarranque ()) {
                // No se borra: se aparta a un respaldo, para poder devolverla (Plank, Solaar y Spotlyte son de aquí).
                var respaldo = Path.build_filename (Environment.get_home_dir (), ".local", "share", "mint-macos", "respaldos", "autostart-quitados");
                DirUtils.create_with_parents (respaldo, 0755);
                FileUtils.rename (ruta, Path.build_filename (respaldo, Path.get_basename (ruta)));
            }
            recargar ();
        }
    }
}
