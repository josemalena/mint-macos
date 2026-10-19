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
    /**
     * Las medidas de la pantalla de bloqueo de High Sierra 10.13.6, medidas en la grabación de QuickTime de la MacBook (1280×800 pt, 1×;
     * referencias/bloqueo-high-sierra/INDICE.md), escaladas a la altura de esta pantalla: avatar de 72 pt con su centro a 291 pt de
     * arriba, el nombre de 13 pt debajo, el campo de 150×28 pt, los botones Cancel y Switch User a ~690 pt, y arriba a la derecha el reloj.
     */
    class Medidas {
        public static double escala = 1.0;
        public static int px (double pt) { return (int) Math.round (pt * escala); }
    }

    string css_para_escala () {
        return """
            window.bloqueo { background-color: #1e1f22; }
            .nombre-bloqueo { font-family: ".SF NS", sans-serif; font-size: %dpx; color: #ffffff; text-shadow: 0 1px 3px rgba(0, 0, 0, 0.45); }
            entry.clave-bloqueo { font-family: ".SF NS", sans-serif; font-size: %dpx; min-height: %dpx; padding: 0 %dpx 0 %dpx;
                border-radius: %dpx; border: none; box-shadow: none; outline: none; background-image: none;
                background-color: rgba(255, 255, 255, 0.36); color: #ffffff; caret-color: #ffffff; }
            entry.clave-bloqueo:focus { box-shadow: none; border: none; }
            entry.clave-bloqueo:disabled { color: rgba(255, 255, 255, 0.6); background-color: rgba(255, 255, 255, 0.28); }
            entry.clave-bloqueo selection { background-color: rgba(255, 255, 255, 0.5); color: #ffffff; }
            .guia-bloqueo { font-family: ".SF NS", sans-serif; font-size: %dpx; color: rgba(255, 255, 255, 0.62); }
            .reloj-bloqueo { font-family: ".SF NS", sans-serif; font-size: %dpx; color: #ffffff; text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45); }
            button.flecha-bloqueo { min-width: %dpx; min-height: %dpx; padding: 0; border-radius: 50%%; border: none; box-shadow: none;
                background-image: none; background-color: rgba(255, 255, 255, 0.36); color: #ffffff; }
            button.circulo-bloqueo { min-width: %dpx; min-height: %dpx; padding: 0; border-radius: 50%%; border: none; box-shadow: none;
                background-image: none; background-color: rgba(255, 255, 255, 0.22); color: #ffffff; font-size: %dpx; }
            button.circulo-bloqueo:disabled { background-color: rgba(255, 255, 255, 0.12); color: rgba(255, 255, 255, 0.45); }
            .etiqueta-circulo { font-family: ".SF NS", sans-serif; font-size: %dpx; color: #ffffff; text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45); }
        """.printf (Medidas.px (13), Medidas.px (13), Medidas.px (28), Medidas.px (6), Medidas.px (12), Medidas.px (14),
                    Medidas.px (13), Medidas.px (13), Medidas.px (22), Medidas.px (22), Medidas.px (35), Medidas.px (35), Medidas.px (18),
                    Medidas.px (11));
    }

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
                    return new Gdk.Pixbuf.from_file_at_scale (r, Medidas.px (72) * 2, Medidas.px (72) * 2, false);
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
            int chico_w = int.max (8, ancho / 48), chico_h = int.max (8, alto / 48);
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
            set_size_request (Medidas.px (72), Medidas.px (72));
        }
        public override bool draw (Cairo.Context c) {
            double r = Medidas.px (72) / 2.0;
            c.arc (r, r, r, 0, 2 * Math.PI);
            c.clip ();
            if (foto != null) {
                double k = (double) Medidas.px (72) / foto.width;
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
        Gtk.Widget campo_caja;      // el campo con su guía (lo que se atenúa y entra con fundido)
        Gtk.Widget centro_w;        // el bloque entero que se sacude: avatar, nombre y campo
        Gtk.Button flecha;
        Gtk.Label reloj;
        bool verificando = false;
        string servicio_pam;
        MainLoop lazo = new MainLoop ();
        int codigo = 1;

        public Principal () {
            servicio_pam = FileUtils.test ("/etc/pam.d/cinnamon-screensaver", FileTest.EXISTS) ? "cinnamon-screensaver" : "login";
            var pantalla0 = Gdk.Display.get_default ();
            var mon0 = pantalla0.get_primary_monitor () ?? pantalla0.get_monitor (0);
            Medidas.escala = mon0.get_geometry ().height / 800.0;     // las medidas son de una pantalla de 800 pt de alto
            var css = new Gtk.CssProvider ();
            try {
                css.load_from_data (css_para_escala (), -1);
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
            // El puntero se ve (como en la Mac)
            var cursor = new Gdk.Cursor.from_name (Gdk.Display.get_default (), "default");
            foreach (var c in cubiertas) {
                if (c.get_window () != null) {
                    c.get_window ().set_cursor (cursor);
                }
            }
            Timeout.add (100, reintentar_grab);
            Timeout.add (500, subir);
            clave.grab_focus ();
            // El campo entra con un fundido de ~120 ms
            campo_caja.opacity = 0;
            animar_opacidad (campo_caja, 0, 1, 120, null);
        }

        void armar_centro (Cubierta c, Gdk.Rectangle g) {
            var capa = new Gtk.Overlay ();
            capa.add (new Gtk.EventBox ());
            c.add (capa);

            // El bloque del centro: avatar (centro a 291 pt de arriba), nombre y campo de clave
            var centro = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            centro.halign = Gtk.Align.CENTER;
            centro.valign = Gtk.Align.START;
            centro.margin_top = Medidas.px (291) - Medidas.px (72) / 2;
            var avatar = new Avatar ();
            avatar.halign = Gtk.Align.CENTER;
            centro.pack_start (avatar, false, false, 0);
            var nombre = new Gtk.Label (nombre_completo ());
            nombre.get_style_context ().add_class ("nombre-bloqueo");
            nombre.justify = Gtk.Justification.CENTER;
            nombre.wrap = true;
            nombre.wrap_mode = Pango.WrapMode.WORD;
            nombre.max_width_chars = 24;
            nombre.margin_top = Medidas.px (12);
            centro.pack_start (nombre, false, false, 0);

            clave = new Gtk.Entry ();
            clave.get_style_context ().add_class ("clave-bloqueo");
            clave.visibility = false;
            clave.invisible_char = '●';
            clave.width_chars = 1;
            clave.set_size_request (Medidas.px (150), Medidas.px (28));
            clave.halign = Gtk.Align.CENTER;
            clave.max_length = 1024;
            guia = new Gtk.Label ("Enter Password");
            guia.get_style_context ().add_class ("guia-bloqueo");
            guia.halign = Gtk.Align.START;
            guia.valign = Gtk.Align.CENTER;
            guia.margin_start = Medidas.px (12);
            var con_guia = new Gtk.Overlay ();
            con_guia.add (clave);
            con_guia.add_overlay (guia);
            con_guia.set_overlay_pass_through (guia, true);
            // El círculo con la flecha → a la derecha del campo, que aparece al escribir; a la izquierda un hueco igual para que el campo siga centrado
            flecha = new Gtk.Button.with_label ("→");
            flecha.get_style_context ().add_class ("flecha-bloqueo");
            flecha.relief = Gtk.ReliefStyle.NONE;
            flecha.can_focus = false;
            flecha.valign = Gtk.Align.CENTER;
            flecha.opacity = 0;
            flecha.margin_start = Medidas.px (8);
            flecha.clicked.connect (enviar);
            var hueco = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            hueco.set_size_request (Medidas.px (22) + Medidas.px (8), 1);
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            fila.halign = Gtk.Align.CENTER;
            fila.margin_top = Medidas.px (12);
            fila.pack_start (hueco, false, false, 0);
            fila.pack_start (con_guia, false, false, 0);
            fila.pack_start (flecha, false, false, 0);
            campo_caja = con_guia;
            centro.pack_start (fila, false, false, 0);
            clave.changed.connect (() => {
                bool hay = clave.get_text_length () > 0;
                guia.visible = !hay;
                flecha.opacity = hay ? 1 : 0;
            });
            clave.activate.connect (enviar);
            centro_w = centro;
            capa.add_overlay (centro);

            // Abajo, a ~690 pt: Cancel (⊗) y Switch User, redondos con su texto
            var abajo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, Medidas.px (46));
            abajo.halign = Gtk.Align.CENTER;
            abajo.valign = Gtk.Align.START;
            abajo.margin_top = Medidas.px (690) - Medidas.px (35) / 2;
            var cancel = circulo ("⊗", "Cancel");
            ((Gtk.Button) cancel.get_children ().nth_data (0)).clicked.connect (() => { clave.text = ""; clave.grab_focus (); });
            abajo.pack_start (cancel, false, false, 0);
            var cambiar = circulo ("☺", "Switch User");
            // Cambiar de usuario pasaría por el greeter de LightDM: decisión de José (19-10-2026), solo con su sí
            ((Gtk.Button) cambiar.get_children ().nth_data (0)).sensitive = false;
            cambiar.set_tooltip_text ("Switching user needs the login window; not available from the lock screen yet.");
            abajo.pack_start (cambiar, false, false, 0);
            capa.add_overlay (abajo);

            // Arriba a la derecha el reloj («3:47 PM»); la batería y el Wi-Fi de la Mac no se dibujan (esta máquina no tiene batería)
            reloj = new Gtk.Label ("");
            reloj.get_style_context ().add_class ("reloj-bloqueo");
            reloj.halign = Gtk.Align.END;
            reloj.valign = Gtk.Align.START;
            reloj.margin_end = Medidas.px (14);
            reloj.margin_top = Medidas.px (4);
            capa.add_overlay (reloj);
            poner_hora ();
            Timeout.add_seconds (5, () => { poner_hora (); return Source.CONTINUE; });
        }

        void poner_hora () {
            reloj.label = new DateTime.now_local ().format ("%-I:%M %p");
        }

        Gtk.Box circulo (string simbolo, string texto) {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, Medidas.px (6));
            var b = new Gtk.Button.with_label (simbolo);
            b.get_style_context ().add_class ("circulo-bloqueo");
            b.relief = Gtk.ReliefStyle.NONE;
            b.can_focus = false;
            b.halign = Gtk.Align.CENTER;
            caja.pack_start (b, false, false, 0);
            var l = new Gtk.Label (texto);
            l.get_style_context ().add_class ("etiqueta-circulo");
            caja.pack_start (l, false, false, 0);
            return caja;
        }

        /** Un fundido de opacidad (de, a) en `ms` milisegundos. */
        void animar_opacidad (Gtk.Widget w, double de, double a, int ms, owned VoidFunc? al_terminar) {
            int64 inicio = get_monotonic_time ();
            Timeout.add (16, () => {
                double t = (get_monotonic_time () - inicio) / 1000.0 / ms;
                if (t >= 1) {
                    w.opacity = a;
                    if (al_terminar != null) al_terminar ();
                    return false;
                }
                w.opacity = de + (a - de) * t;
                return true;
            });
        }

        /** El teclado y el ratón son de esta pantalla. Mientras no se logre el grab se reintenta, y si se pierde, se retoma. */
        int grabs_fallidos = 0;
        int64 fallando_desde = 0;      // desde cuándo falla el grab sin parar (0 = no está fallando)
        bool recurso_usado = false;    // ya se pidió dm-tool lock en esta racha de fallos

        /**
         * Último recurso (fail-closed de verdad): si en ~2 s no se logra el grab, por cualquier motivo (Cinnamon sin Eval o colgado, otro
         * programa con el grab), el bloqueo no se queda «medio puesto»: se pide el del greeter de LightDM (dm-tool lock), que no depende de
         * nada de esta sesión. Se anota en el log de la sesión.
         */
        void ultimo_recurso () {
            recurso_usado = true;
            var dm_tool = Environment.find_program_in_path ("dm-tool");
            anotar ("el grab lleva más de 2 s sin lograrse: último recurso, dm-tool lock (%s)".printf (dm_tool ?? "no está dm-tool"));
            if (dm_tool == null) {
                return;
            }
            try {
                new Subprocess (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE, dm_tool, "lock");
            } catch (Error e) {
                anotar ("no pude lanzar dm-tool lock: %s".printf (e.message));
            }
        }

        void anotar (string linea) {
            warning ("%s", linea);
            try {
                var carpeta = Path.build_filename (Environment.get_user_state_dir (), "mint-macos");
                DirUtils.create_with_parents (carpeta, 0700);
                var f = FileStream.open (Path.build_filename (carpeta, "bloqueo.log"), "a");
                if (f != null) {
                    f.printf ("%s %s\n", new DateTime.now_local ().format ("%Y-%m-%d %H:%M:%S"), linea);
                }
            } catch (Error e) {
            }
        }

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
                grabs_fallidos++;
                // Quien tiene el grab es casi siempre Cinnamon: mientras hay un menú abierto Muffin agarra el teclado y el ratón
                // (begin_modal). Se le pide que suelte los modales (popModal de cada uno) y el siguiente intento ya lo logra.
                // Solo si el grab falló: sin él no hay nada que soltar.
                if (r == Gdk.GrabStatus.ALREADY_GRABBED && grabs_fallidos >= 3 && grabs_fallidos <= 30 && grabs_fallidos % 3 == 0) {
                    pedir_a_cinnamon_que_suelte ();
                }
                if (fallando_desde == 0) {
                    fallando_desde = get_monotonic_time ();
                }
                if (!recurso_usado && get_monotonic_time () - fallando_desde > 2000000) {
                    ultimo_recurso ();
                }
            } else {
                grabs_fallidos = 0;
                fallando_desde = 0;
                recurso_usado = false;
                if (!clave.has_focus) {
                    clave.grab_focus ();
                }
            }
            return Source.CONTINUE;
        }

        void pedir_a_cinnamon_que_suelte () {
            const string JS = "(function(){ let m = imports.ui.main; while (m.modalActorFocusStack.length > 0) " +
                "m.popModal(m.modalActorFocusStack[m.modalActorFocusStack.length - 1].actor); })()";
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                bus.call.begin ("org.Cinnamon", "/org/Cinnamon", "org.Cinnamon", "Eval", new Variant ("(s)", JS),
                                null, DBusCallFlags.NO_AUTO_START, 2000, null, (o, res) => {
                    try { bus.call.end (res); } catch (Error e) { warning ("Cinnamon no soltó el grab: %s", e.message); }
                });
            } catch (Error e) {
                warning ("sin bus de sesión para pedirle a Cinnamon que suelte el grab: %s", e.message);
            }
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
            flecha.sensitive = false;
            // El campo se atenúa en ~200 ms mientras se comprueba (High Sierra)
            animar_opacidad (campo_caja, 1, 0.6, 200, null);
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
            if (resultado == 0) {
                clave.text = "";
                codigo = 0;
                lazo.quit ();
                return;
            }
            // Clave mala: sacudida del bloque entero, el campo recupera su tono en ~170 ms y la clave queda SELECCIONADA para escribir encima
            clave.sensitive = true;
            flecha.sensitive = true;
            animar_opacidad (campo_caja, 0.6, 1, 170, null);
            clave.grab_focus ();
            clave.select_region (0, -1);
            sacudir ();
        }

        // La sacudida medida (QuickTime a 60 cuadros): 400 ms, horizontal, del bloque entero; empieza a la izquierda, ~3 vaivenes con amplitudes
        // 14, 14, 8 y 6 pt. (t en ms desde el principio, dx en pt)
        const int[] SACUDIDA_T = { 0, 17, 33, 50, 67, 83, 100, 117, 133, 150, 167, 183, 200, 217, 250, 267, 283, 317, 333, 350, 383, 400 };
        const int[] SACUDIDA_DX = { 0, -14, -13, -5, 6, 13, 12, 4, -6, -14, -13, -6, 3, 8, 3, -3, -8, -4, 2, 6, 3, 0 };

        void sacudir () {
            int64 inicio = get_monotonic_time ();
            Timeout.add (16, () => {
                double ms = (get_monotonic_time () - inicio) / 1000.0;
                double dx = 0;
                if (ms < 400) {
                    for (int i = 1; i < SACUDIDA_T.length; i++) {
                        if (ms <= SACUDIDA_T[i]) {
                            double f = (ms - SACUDIDA_T[i - 1]) / (SACUDIDA_T[i] - SACUDIDA_T[i - 1]);
                            dx = SACUDIDA_DX[i - 1] + (SACUDIDA_DX[i] - SACUDIDA_DX[i - 1]) * f;
                            break;
                        }
                    }
                }
                int px = (int) Math.round (dx * Medidas.escala);
                // El bloque está centrado: un margen a un lado de 2·dx lo corre dx
                centro_w.margin_start = px > 0 ? 2 * px : 0;
                centro_w.margin_end = px < 0 ? -2 * px : 0;
                if (ms >= 400) {
                    centro_w.margin_start = 0;
                    centro_w.margin_end = 0;
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
