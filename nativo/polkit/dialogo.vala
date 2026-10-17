/*
 * El diálogo «… wants to make changes. Enter your password to allow this» de Catalina, igual que el de
 * polkit/agente.py (capturas 1.11.51 PM, 1.16.09 PM, 1.33.32 PM y 12.21.58 AM): User Name editable, clave que
 * solo se sacude si es mala, botón y candado según la acción. La clave vive en el campo mientras se teclea y
 * este código no la guarda, escribe ni imprime.
 */
namespace MacPolkit {
    const string APPS = "/.local/share/mint-macos/settings";

    const string CSS = """
window.mp-polkit { background-color: #2f2f2f; border: 1px solid #1a1a1a; color: #ffffff; }
.mp-polkit-franja { background-color: #3a3a3a; min-height: 22px; border-bottom: 1px solid #1f1f1f; }
.mp-polkit label { color: #ffffff; }
.mp-polkit .mp-titulo { font-weight: 700; font-size: 10pt; }
.mp-polkit .mp-texto { font-size: 9pt; color: rgba(255, 255, 255, 0.78); }
.mp-polkit entry { background-color: #232323; color: #ffffff; border: 1px solid #1a1a1a;
                   border-radius: 3px; padding: 3px 6px; min-height: 16px; }
.mp-polkit entry:focus { border-color: #0a64d6; box-shadow: 0 0 0 2px rgba(10, 100, 214, 0.55); }
.mp-polkit button { background-image: none; background-color: #5a5a5a; color: #ffffff; border: 1px solid #3a3a3a;
                    border-radius: 4px; padding: 3px 14px; min-height: 16px; text-shadow: none; box-shadow: none; }
.mp-polkit button.mp-defecto { background-color: #0a64d6; border-color: #0a4fa8; }
""";

    /** Lo que Catalina enseña con su propio texto para una acción (captura 1.33.32 PM). */
    public class Variante : Object {
        public string titulo;
        public string texto;
        public string boton;
        public string rotulo_nombre;
        public bool nombre_login;
        public bool icono_reiniciar;
        public string? extra;
    }

    public Variante? variante_de (string action_id) {
        if (action_id == "org.freedesktop.login1.reboot-multiple-sessions") {
            return new Variante () {
                titulo = "Restarting may cause other users logged into this computer to lose unsaved changes.",
                texto = "To avoid losing unsaved changes, log out all users before restarting. To continue without "
                    + "saving changes, enter an administrator name and password and then click Restart.",
                boton = "Restart",
                rotulo_nombre = "Name:",
                nombre_login = true,
                icono_reiniciar = true,
                extra = "Switch User…"
            };
        }
        return null;
    }

    bool css_cargado = false;

    // El CSS se carga una sola vez por proceso: el agente es residente y abre un diálogo por petición.
    void cargar_css () {
        if (css_cargado) {
            return;
        }
        var css = new Gtk.CssProvider ();
        try {
            css.load_from_data (CSS);
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css, 800);
            css_cargado = true;
        } catch (Error e) {
            warning ("CSS: %s", e.message);
        }
    }

    public class Dialogo : Gtk.Window {
        public signal void aceptado (string login);
        public signal void cancelado ();

        public Gtk.Entry usuario;
        public Gtk.Entry clave;
        Gtk.Button aceptar;
        Gtk.Button cancelar;
        HashTable<string, Usuario> autorizados;

        public Dialogo (string mensaje, string boton, string? icono_panel,
                        HashTable<string, Usuario> autorizados, Variante? v) {
            Object (type: Gtk.WindowType.TOPLEVEL);
            this.autorizados = autorizados;
            string msg = v != null ? v.titulo : mensaje;
            string btn = v != null ? v.boton : boton;
            decorated = false;
            resizable = false;
            set_keep_above (true);
            window_position = Gtk.WindowPosition.CENTER;
            skip_taskbar_hint = true;
            skip_pager_hint = true;
            type_hint = Gdk.WindowTypeHint.SPLASHSCREEN;
            title = "Authentication";
            get_style_context ().add_class ("mp-polkit");
            cargar_css ();

            var raiz = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var franja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            franja.get_style_context ().add_class ("mp-polkit-franja");
            raiz.pack_start (franja, false, false, 0);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 18);
            cuerpo.margin = 22;
            cuerpo.pack_start ((v != null && v.icono_reiniciar) ? icono_reiniciar () : icono (icono_panel), false, false, 0);
            var der = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            var t = new Gtk.Label (msg);
            t.xalign = 0;
            t.get_style_context ().add_class ("mp-titulo");
            t.wrap = true;
            t.max_width_chars = 48;
            der.pack_start (t, false, false, 0);
            var s = new Gtk.Label (v != null ? v.texto : "Enter your password to allow this.");
            s.xalign = 0;
            s.get_style_context ().add_class ("mp-texto");
            s.wrap = true;
            s.max_width_chars = 48;
            der.pack_start (s, false, false, 0);
            var g = new Gtk.Grid ();
            g.column_spacing = 8;
            g.row_spacing = 10;
            g.margin_top = 14;
            string[] rotulos = { v != null ? v.rotulo_nombre : "User Name:", "Password:" };
            for (int i = 0; i < 2; i++) {
                var l = new Gtk.Label (rotulos[i]);
                l.xalign = 1.0f;
                g.attach (l, 0, i, 1, 1);
            }
            usuario = new Gtk.Entry ();
            usuario.text = nombre_por_defecto (autorizados, v != null && v.nombre_login);
            usuario.width_chars = 34;
            usuario.hexpand = true;
            clave = new Gtk.Entry ();
            clave.width_chars = 34;
            clave.visibility = false;
            clave.input_purpose = Gtk.InputPurpose.PASSWORD;
            usuario.activate.connect (aceptar_ahora);
            clave.activate.connect (aceptar_ahora);
            g.attach (usuario, 1, 0, 1, 1);
            g.attach (clave, 1, 1, 1, 1);
            der.pack_start (g, false, false, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            botones.margin_top = 10;
            cancelar = new Gtk.Button.with_label ("Cancel");
            cancelar.clicked.connect (() => { cancelado (); });
            aceptar = new Gtk.Button.with_label (btn);
            aceptar.get_style_context ().add_class ("mp-defecto");
            aceptar.clicked.connect (aceptar_ahora);
            botones.pack_end (aceptar, false, false, 0);
            botones.pack_end (cancelar, false, false, 0);
            if (v != null && v.extra != null) {
                // Switch User…: lleva a la ventana de entrada (LightDM) y cierra este diálogo.
                var extra = new Gtk.Button.with_label (v.extra);
                extra.clicked.connect (cambiar_usuario);
                botones.pack_start (extra, false, false, 0);
            }
            der.pack_start (botones, false, false, 0);
            cuerpo.pack_start (der, true, true, 0);
            raiz.pack_start (cuerpo, true, true, 0);
            add (raiz);
            key_press_event.connect ((ev) => {
                if (ev.keyval == Gdk.Key.Escape) {
                    cancelado ();
                    return true;
                }
                return false;
            });
            delete_event.connect (() => { cancelado (); return true; });
            show_all ();
            usuario.select_region (0, 0);
            clave.grab_focus ();
            // Lo abre un proceso en segundo plano: sin esto Muffin no le da el foco y no se puede teclear la clave.
            // Muffin le niega el foco a una ventana sin hora de usuario reciente: se le pone la del servidor X.
            var x = get_window () as Gdk.X11.Window;
            if (x != null) {
                uint32 ahora = Gdk.X11.get_server_time (x);
                x.set_user_time (ahora);
                present_with_time (ahora);
            } else {
                present_with_time (Gdk.CURRENT_TIME);
            }
            clave.grab_focus ();
        }

        Gtk.Widget icono (string? panel) {
            // El candado naranja de la Mac y, si la acción lo pide, el ícono de la app abajo a la derecha.
            var area = new Gtk.DrawingArea ();
            area.set_size_request (72, 80);
            string base_dir = Environment.get_home_dir () + APPS;
            Gdk.Pixbuf? candado = null;
            Gdk.Pixbuf? insignia = null;
            try {
                candado = new Gdk.Pixbuf.from_file_at_scale (base_dir + "/glifos/LockLocked@2x.png", 60, 60, true);
            } catch (Error e) {
            }
            if (panel != null) {
                try {
                    insignia = new Gdk.Pixbuf.from_file_at_scale (base_dir + "/iconos/" + panel + ".png", 34, 34, true);
                } catch (Error e) {
                }
            }
            area.draw.connect ((cr) => {
                if (candado != null) {
                    Gdk.cairo_set_source_pixbuf (cr, candado, 2, 6);
                    cr.paint ();
                }
                if (insignia != null) {
                    Gdk.cairo_set_source_pixbuf (cr, insignia, 36, 40);
                    cr.paint ();
                }
                return false;
            });
            return area;
        }

        Gtk.Widget icono_reiniciar () {
            var area = new Gtk.DrawingArea ();
            area.set_size_request (72, 72);
            area.draw.connect ((cr) => {
                cr.set_source_rgb (139.0 / 255, 141.0 / 255, 142.0 / 255);
                cr.arc (34, 34, 32, 0, 2 * Math.PI);
                cr.fill ();
                cr.set_source_rgb (1, 1, 1);
                cr.set_line_width (2.6);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                cr.move_to (22, 34);
                cr.line_to (43, 21.5);
                cr.line_to (43, 46.5);
                cr.close_path ();
                cr.stroke ();
                return false;
            });
            return area;
        }

        void cambiar_usuario () {
            try {
                Process.spawn_async (null, { "dm-tool", "switch-to-greeter" }, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDOUT_TO_DEV_NULL | SpawnFlags.STDERR_TO_DEV_NULL, null, null);
            } catch (Error e) {
            }
            cancelado ();
        }

        void aceptar_ahora () {
            string? login = resolver_usuario (usuario.text, autorizados);
            if (login == null || clave.text == "") {
                sacudir ();
                return;
            }
            ocupado (true);
            aceptado (login);
        }

        public void ocupado (bool si) {
            usuario.sensitive = !si;
            clave.sensitive = !si;
            aceptar.sensitive = !si;
            cancelar.sensitive = true;
        }

        public void borrar_clave () {
            clave.text = "";
        }

        /** Clave o usuario malos: la ventana se sacude de lado a lado, sin ningún mensaje. */
        public void sacudir () {
            ocupado (false);
            borrar_clave ();
            clave.grab_focus ();
            int x0, y0;
            get_position (out x0, out y0);
            int[] pasos = { -12, 12, -10, 10, -6, 6, -3, 3, 0 };
            int i = 0;
            Timeout.add (28, () => {
                if (i >= pasos.length) {
                    return false;
                }
                move (x0 + pasos[i], y0);
                i++;
                return true;
            });
        }
    }
}
