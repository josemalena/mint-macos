/*
 * La pantalla de bloqueo, con la forma del login de Catalina (medidas del login de slick-greeter-mac, que salen de las capturas
 * de José): fondo de escritorio desenfocado, avatar de 144 px, el nombre en negrita a 20 px y un campo de 160×28 con «Enter Password».
 * PROVISIONAL en lo que no tiene captura (la Mac de José no tiene foto del bloqueo): botones de abajo, pistas de clave.
 *
 * Seguridad:
 *  - una ventana sin gestor (override-redirect) por monitor, tapando todo; el teclado y el ratón se agarran (grab) y se
 *    reintenta hasta lograrlo; si el grab se pierde se vuelve a tomar, y cada medio segundo la ventana se sube al frente
 *    (notificaciones, menús, el Dock);
 *  - nada pasa a la aplicación del frente: el grab es del teclado completo;
 *  - la clave se verifica con PAM (pam_ayuda.c) en un hilo y no se guarda; el campo y la copia se borran al terminar;
 *  - esta pantalla solo sale con código 0 si PAM dijo que sí; cualquier otra salida la relanza el supervisor.
 */
namespace Bloqueo {
    // (funciones y no const: valac no declara bien las const de un namespace en este archivo)
    int avatar_px () { return 144; }
    int ancho_campo () { return 160; }
    int alto_campo () { return 28; }

    const string CSS = """
        window.bloqueo { background-color: #1e1f22; }
        .nombre-bloqueo { font-family: ".SF NS", sans-serif; font-weight: bold; font-size: 20px; color: #ffffff;
            text-shadow: 0 1px 3px rgba(0, 0, 0, 0.45); }
        entry.clave-bloqueo { font-family: ".SF NS", sans-serif; font-size: 13px; min-height: 28px; padding: 0 6px 0 13px;
            border-radius: 14px; border: none; box-shadow: none; outline: none; background-image: none;
            background-color: rgba(255, 255, 255, 0.42); color: #ffffff; caret-color: #ffffff; }
        entry.clave-bloqueo:focus { box-shadow: none; border: none; }
        entry.clave-bloqueo:disabled { color: rgba(255, 255, 255, 0.6); background-color: rgba(255, 255, 255, 0.30); }
        .guia-bloqueo { font-family: ".SF NS", sans-serif; font-size: 13px; color: rgba(255, 255, 255, 0.62); }
    """;

    /** El nombre completo de la cuenta (el campo de nombre real) o, si no hay, el usuario. */
    string nombre_completo () {
        var real = Environment.get_real_name ();
        if (real == null || real == "" || real == "Unknown") {
            return Environment.get_user_name ();
        }
        return real;
    }

    /** La foto de la cuenta: ~/.face o la de AccountsService. */
    Gdk.Pixbuf? foto_de_la_cuenta () {
        string[] rutas = {
            Path.build_filename (Environment.get_home_dir (), ".face"),
            "/var/lib/AccountsService/icons/%s".printf (Environment.get_user_name ())
        };
        foreach (var r in rutas) {
            if (FileUtils.test (r, FileTest.IS_REGULAR)) {
                try {
                    return new Gdk.Pixbuf.from_file_at_scale (r, avatar_px () * 2, avatar_px () * 2, false);
                } catch (Error e) {
                }
            }
        }
        return null;
    }

    /** El fondo de escritorio de la cuenta (dconf), desenfocado: se achica y se vuelve a estirar, que sale un desenfoque suave. */
    Gdk.Pixbuf? fondo_desenfocado (int ancho, int alto) {
        string? uri = null;
        try {
            var cfg = new Settings ("org.cinnamon.desktop.background");
            uri = cfg.get_string ("picture-uri");
        } catch (Error e) {
        }
        if (uri == null || uri == "") {
            return null;
        }
        try {
            var archivo = File.new_for_uri (uri);
            var ruta = archivo.get_path ();
            if (ruta == null) {
                return null;
            }
            var original = new Gdk.Pixbuf.from_file (ruta);
            // «cover»: llena la pantalla recortando lo que sobre
            double k = double.max ((double) ancho / original.width, (double) alto / original.height);
            int w = (int) Math.ceil (original.width * k), h = (int) Math.ceil (original.height * k);
            int chico_w = int.max (8, ancho / 24), chico_h = int.max (8, alto / 24);
            var cubierto = original.scale_simple (w, h, Gdk.InterpType.BILINEAR);
            var recorte = new Gdk.Pixbuf.subpixbuf (cubierto, (w - ancho) / 2, (h - alto) / 2, ancho, alto);
            return recorte.scale_simple (chico_w, chico_h, Gdk.InterpType.BILINEAR).scale_simple (ancho, alto, Gdk.InterpType.BILINEAR);
        } catch (Error e) {
            return null;
        }
    }

    class Avatar : Gtk.DrawingArea {
        Gdk.Pixbuf? foto;
        public Avatar () {
            foto = foto_de_la_cuenta ();
            set_size_request (avatar_px (), avatar_px ());
        }
        public override bool draw (Cairo.Context c) {
            double r = avatar_px () / 2.0;
            c.arc (r, r, r, 0, 2 * Math.PI);
            c.clip ();
            if (foto != null) {
                double k = (double) avatar_px () / foto.width;
                c.scale (k, k);
                Gdk.cairo_set_source_pixbuf (c, foto, 0, 0);
                c.paint ();
            } else {
                c.set_source_rgba (1, 1, 1, 0.22);
                c.paint ();
                c.set_source_rgba (1, 1, 1, 0.7);
                c.arc (r, r * 0.8, r * 0.34, 0, 2 * Math.PI);
                c.fill ();
                c.arc (r, r * 1.75, r * 0.7, Math.PI, 2 * Math.PI);
                c.fill ();
            }
            return true;
        }
    }

    class Cubierta : Gtk.Window {
        Gdk.Pixbuf? fondo;
        public Cubierta (Gdk.Rectangle g) {
            Object (type: Gtk.WindowType.POPUP);
            get_style_context ().add_class ("bloqueo");
            decorated = false;
            app_paintable = true;
            skip_taskbar_hint = true;
            set_default_size (g.width, g.height);
            move (g.x, g.y);
            fondo = fondo_desenfocado (g.width, g.height);
        }
        public override bool draw (Cairo.Context c) {
            if (fondo != null) {
                Gdk.cairo_set_source_pixbuf (c, fondo, 0, 0);
                c.paint ();
                c.set_source_rgba (0, 0, 0, 0.28);
                c.paint ();
            } else {
                c.set_source_rgb (0.12, 0.12, 0.14);
                c.paint ();
            }
            return base.draw (c);
        }
    }

    class Principal : Object {
        Cubierta[] cubiertas = {};
        Cubierta? primera = null;
        Gtk.Entry clave;
        Gtk.Label guia;
        bool verificando = false;
        string servicio_pam;
        MainLoop lazo = new MainLoop ();
        int codigo = 1;

        public Principal () {
            servicio_pam = FileUtils.test ("/etc/pam.d/cinnamon-screensaver", FileTest.EXISTS) ? "cinnamon-screensaver" : "login";
            var css = new Gtk.CssProvider ();
            try {
                css.load_from_data (CSS, -1);
                Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            } catch (Error e) {
                warning ("CSS: %s", e.message);
            }
            var pantalla = Gdk.Display.get_default ();
            int n = pantalla.get_n_monitors ();
            var principal = pantalla.get_primary_monitor () ?? pantalla.get_monitor (0);
            for (int i = 0; i < n; i++) {
                var m = pantalla.get_monitor (i);
                Gdk.Rectangle g = m.get_geometry ();
                var c = new Cubierta (g);
                if (m == principal) {
                    armar_centro (c, g);
                    primera = c;
                }
                cubiertas += c;
            }
            foreach (var c in cubiertas) {
                c.show_all ();
            }
            Timeout.add (100, reintentar_grab);
            Timeout.add (500, subir);
            clave.grab_focus ();
        }

        void armar_centro (Cubierta c, Gdk.Rectangle g) {
            var centro = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            centro.halign = Gtk.Align.CENTER;
            var avatar = new Avatar ();
            avatar.halign = Gtk.Align.CENTER;
            centro.pack_start (avatar, false, false, 0);
            var nombre = new Gtk.Label (nombre_completo ());
            nombre.get_style_context ().add_class ("nombre-bloqueo");
            nombre.justify = Gtk.Justification.CENTER;
            nombre.wrap = true;
            nombre.wrap_mode = Pango.WrapMode.WORD;
            nombre.max_width_chars = 15;
            nombre.margin_top = 31;
            centro.pack_start (nombre, false, false, 0);
            clave = new Gtk.Entry ();
            clave.get_style_context ().add_class ("clave-bloqueo");
            clave.visibility = false;
            clave.invisible_char = '●';
            clave.width_chars = 1;
            clave.set_size_request (ancho_campo (), alto_campo ());
            clave.halign = Gtk.Align.CENTER;
            clave.max_length = 1024;
            guia = new Gtk.Label ("Enter Password");
            guia.get_style_context ().add_class ("guia-bloqueo");
            guia.halign = Gtk.Align.START;
            guia.valign = Gtk.Align.CENTER;
            guia.margin_start = 14;
            var con_guia = new Gtk.Overlay ();
            con_guia.add (clave);
            con_guia.add_overlay (guia);
            con_guia.set_overlay_pass_through (guia, true);
            con_guia.halign = Gtk.Align.CENTER;
            con_guia.margin_top = 22;
            centro.pack_start (con_guia, false, false, 0);
            clave.changed.connect (() => { guia.visible = clave.get_text_length () == 0; });
            clave.activate.connect (enviar);

            var fijo = new Gtk.Fixed ();
            // El avatar empieza 169 px sobre el centro de la pantalla (medido en el login de Catalina)
            centro.set_size_request (ancho_campo () + 120, -1);
            fijo.put (centro, g.width / 2 - (ancho_campo () + 120) / 2, int.max (20, g.height / 2 - 169));
            c.add (fijo);
        }

        /** El teclado y el ratón son de esta pantalla. Mientras no se logre el grab se reintenta, y si se pierde, se retoma. */
        bool reintentar_grab () {
            if (primera == null) {
                return Source.CONTINUE;
            }
            var ventana = primera.get_window ();
            if (ventana == null) {
                return Source.CONTINUE;
            }
            var seat = Gdk.Display.get_default ().get_default_seat ();
            // GDK da el grab otra vez sin problema si ya es nuestro; si otro lo tiene, se queda en reintento
            var r = seat.grab (ventana, Gdk.SeatCapabilities.ALL, true, null, null, null);
            if (r != Gdk.GrabStatus.SUCCESS) {
                warning ("grab: %s (se reintenta)", r.to_string ());
            } else if (!clave.has_focus) {
                clave.grab_focus ();
            }
            return Source.CONTINUE;
        }

        bool subir () {
            foreach (var c in cubiertas) {
                var w = c.get_window ();
                if (w != null) {
                    w.raise ();
                }
            }
            return Source.CONTINUE;
        }

        void enviar () {
            if (verificando || clave.get_text_length () == 0) {
                return;
            }
            verificando = true;
            clave.sensitive = false;
            // Copia de la clave solo para PAM (el buffer de GTK no se puede borrar a mano): se borra al terminar
            unowned string texto = clave.get_text ();
            size_t largo = texto.length;
            var copia = new uint8[largo + 1];
            Memory.copy (copia, texto, largo);
            string usuario = Environment.get_user_name ();
            string servicio = servicio_pam;
            new Thread<int> ("pam", () => {
                int r = PamAyuda.autenticar (servicio, usuario, copia, largo);
                Memory.set (copia, 0, copia.length);
                Idle.add (() => { terminado (r); return false; });
                return r;
            });
        }

        void terminado (int resultado) {
            verificando = false;
            clave.sensitive = true;
            clave.text = "";
            if (resultado == 0) {
                codigo = 0;
                lazo.quit ();
                return;
            }
            clave.grab_focus ();
            sacudir ();
        }

        /** La sacudida de la Mac cuando la clave no es: el campo se mueve de lado a lado. */
        void sacudir () {
            int paso = 0;
            int[] mov = { -12, 12, -9, 9, -5, 5, -2, 2, 0 };
            clave.parent.margin_start = 0;
            Timeout.add (35, () => {
                clave.parent.margin_start = mov[paso] > 0 ? mov[paso] * 2 : 0;
                clave.parent.margin_end = mov[paso] < 0 ? -mov[paso] * 2 : 0;
                paso++;
                if (paso >= mov.length) {
                    clave.parent.margin_start = 0;
                    clave.parent.margin_end = 0;
                    return false;
                }
                return true;
            });
        }

        public int correr () {
            lazo.run ();
            var seat = Gdk.Display.get_default ().get_default_seat ();
            seat.ungrab ();
            return codigo;
        }
    }

    public int pantalla (string[] args) {
        unowned string[] a = args;
        Gtk.init (ref a);
        var p = new Principal ();
        return p.correr ();
    }
}
