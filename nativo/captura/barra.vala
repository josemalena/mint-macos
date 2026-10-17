/*
 * La barra flotante de ⇧⌘5, abajo al centro:
 *   ✕  pantalla entera · ventana · porción  |  grabar pantalla · grabar porción  |  Options ⌄  | Capture / Record
 * Medidas de la captura de José (Screen Shot 2026-10-14 at 12.08.04 AM, 409 × 76 con la sombra): barra de unos
 * 390 × 46, esquinas redondeadas, fondo oscuro translúcido, el botón elegido resaltado.
 * Capturas con el propio GDK y grabación con ffmpeg (x11grab); el archivo se llama como en la Mac:
 * «Screen Shot 2026-10-14 at 3.00.00 PM.png» y «Screen Recording … .mov».
 */
namespace Captura {
    const string CSS = """
#barra {
  background-color: rgba(44, 44, 46, 0.94);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 10px;
}
.boton-modo { background: none; border: none; box-shadow: none; border-radius: 6px; padding: 0; min-width: 40px; min-height: 30px; }
.boton-modo:hover { background-color: rgba(255, 255, 255, 0.08); }
.boton-modo.elegido { background-color: rgba(255, 255, 255, 0.20); }
#cerrar { background: none; border: none; box-shadow: none; padding: 0; min-width: 22px; min-height: 22px; }
#opciones { background: none; border: none; box-shadow: none; color: #e6e6e6; font-family: ".SF NS"; font-size: 13px; padding: 4px 8px; }
#opciones:hover { background-color: rgba(255, 255, 255, 0.08); border-radius: 6px; }
#accion { background-image: none; background-color: #2f7bf5; color: white; font-family: ".SF NS"; font-size: 13px;
          border: none; border-radius: 6px; padding: 3px 14px; box-shadow: none; text-shadow: none; }
#accion:hover { background-color: #4a8df7; }
#separador { background-color: rgba(255, 255, 255, 0.18); min-width: 1px; }
#pildora { background-color: rgba(44, 44, 46, 0.94); border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 12px; }
#miniatura { background-color: rgba(44, 44, 46, 0.94); border: 1px solid rgba(255, 255, 255, 0.14); border-radius: 6px; padding: 6px; }
""";

    public class Barra : Gtk.ApplicationWindow {
        Config cfg;
        Subprocess? grabacion = null;
        HashTable<string, Gtk.Button> botones = new HashTable<string, Gtk.Button> (str_hash, str_equal);
        Marco? marco = null;           // el marco de «Selected Portion» mientras está puesto
        Elegir? selector = null;       // el cursor de cámara de «Selected Window»
        int[]? rect = null;            // el último marco, para volver a ponerlo igual
        Gtk.MenuButton opciones;
        Gtk.Button accion;
        /** Hecha la captura o grabando: pedir ⇧⌘5 otra vez no debe volver a enseñar la barra. */
        public bool ocupada = false;

        public Barra (Gtk.Application app) {
            Object (application: app, type: Gtk.WindowType.TOPLEVEL);
            cfg = Config.cargar ();
            bool conocido = false;
            foreach (var m in MODOS) if (m == cfg.modo) conocido = true;
            if (!cfg.recordar || !conocido) cfg.modo = "pantalla";

            var prov = new Gtk.CssProvider ();
            try {
                prov.load_from_data (CSS);
            } catch (Error e) {
                warning ("CSS: %s", e.message);
            }
            Gtk.StyleContext.add_provider_for_screen (get_screen (), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
            var scr = get_screen ();
            if (scr.get_rgba_visual () != null) set_visual (scr.get_rgba_visual ());
            set_app_paintable (true);
            set_decorated (false);
            set_keep_above (true);
            set_skip_taskbar_hint (true);
            set_type_hint (Gdk.WindowTypeHint.DOCK);
            set_title ("Screenshot");
            destroy.connect (() => soltar_armado ());

            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            fila.name = "barra";
            fila.set_margin_top (14); fila.set_margin_bottom (14); fila.set_margin_start (14); fila.set_margin_end (14);
            add (fila);

            var cerrar = new Gtk.Button ();
            cerrar.name = "cerrar";
            cerrar.add (area_icono ("cerrar", 22, 22));
            cerrar.set_margin_start (8); cerrar.set_margin_end (6);
            cerrar.clicked.connect (() => destroy ());
            fila.pack_start (cerrar, false, false, 0);

            foreach (var m in MODOS) {
                if (m == "grabar-pantalla") fila.pack_start (separador (), false, false, 8);
                var b = new Gtk.Button ();
                b.get_style_context ().add_class ("boton-modo");
                b.add (area_icono (m));
                b.set_tooltip_text (tip_de (m));
                var modo = m;
                b.clicked.connect (() => elegir (modo, true));
                botones.insert (m, b);
                fila.pack_start (b, false, false, 0);
            }
            fila.pack_start (separador (), false, false, 8);

            opciones = new Gtk.MenuButton ();
            opciones.name = "opciones";
            opciones.set_label ("Options ⌄");
            opciones.set_popup (menu ());
            fila.pack_start (opciones, false, false, 0);
            fila.pack_start (separador (), false, false, 8);

            accion = new Gtk.Button.with_label ("Capture");
            accion.name = "accion";
            accion.set_margin_end (8);
            accion.clicked.connect (() => ejecutar ());
            fila.pack_start (accion, false, false, 0);

            elegir (cfg.modo, false);
            show_all ();
            centrar ();
            Idle.add (() => { centrar (); return false; });
            Timeout.add (120, () => { armar (); return false; });
        }

        void centrar () {
            var pant = get_screen ();
            move ((pant.get_width () - get_allocated_width ()) / 2, pant.get_height () - 150);
        }

        static Gtk.Widget separador () {
            var s = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            s.name = "separador";
            s.set_margin_top (8); s.set_margin_bottom (8);
            return s;
        }

        void elegir (string modo, bool armar_ya) {
            cfg.modo = modo;
            botones.foreach ((m, b) => {
                var ctx = b.get_style_context ();
                if (m == modo) ctx.add_class ("elegido"); else ctx.remove_class ("elegido");
            });
            accion.set_label (modo.has_prefix ("grabar") ? "Record" : "Capture");
            cfg.guardar ();
            opciones.set_popup (menu ());       // Save to cambia entre capturar y grabar
            if (armar_ya) armar ();
        }

        void soltar_armado () {
            if (marco != null) {
                rect = marco.get_rect ();
                marco.destroy ();
                marco = null;
            }
            if (selector != null) {
                selector.destroy ();
                selector = null;
            }
        }

        /**
         * Lo que cada modo deja puesto antes de pulsar Capture, como en la Mac: la porción tiene su marco; la ventana,
         * el cursor de cámara (se elige con un clic, sin usar Capture); la pantalla entera, nada: Capture la toma.
         */
        void armar () {
            soltar_armado ();
            if (cfg.modo == "porcion" || cfg.modo == "grabar-porcion") {
                if (rect == null) {
                    var pant = get_screen ();
                    int ancho = pant.get_width () / 2, alto = pant.get_height () / 2;
                    rect = { pant.get_width () / 4, pant.get_height () / 4, ancho, alto };
                }
                marco = new Marco (rect, this);
            } else if (cfg.modo == "ventana") {
                selector = new Elegir ((wid) => tras_elegir_ventana (wid), this);
            }
        }

        public override bool key_press_event (Gdk.EventKey e) {
            if (e.keyval == Gdk.Key.Escape) {
                destroy ();
                return true;
            }
            if (e.keyval == Gdk.Key.Return || e.keyval == Gdk.Key.KP_Enter) {
                ejecutar ();
                return true;
            }
            return base.key_press_event (e);
        }

        // ── el menú Options ────────────────────────────────────────────────
        delegate void Aplicar ();

        static void titulo (Gtk.Menu m, string t) {
            var i = new Gtk.MenuItem.with_label (t);
            i.set_sensitive (false);
            m.append (i);
        }

        // Una opción de un grupo (Save to, Timer, Microphone): escoger una desmarca las otras. Se aplica al activarla
        // (aunque ya estuviera marcada) y el menú se rehace, para que las marcas no queden viejas.
        void marca (Gtk.Menu m, string texto, bool activo, owned Aplicar cb) {
            var i = new Gtk.CheckMenuItem.with_label (texto);
            i.set_active (activo);
            i.set_draw_as_radio (false);
            i.activate.connect (() => {
                cb ();
                Idle.add (() => { opciones.set_popup (menu ()); return false; });
            });
            m.append (i);
        }

        Gtk.Menu menu () {
            var m = new Gtk.Menu ();

            titulo (m, "Save to");
            bool grabando = cfg.modo.has_prefix ("grabar");
            var destino = cfg.destino;
            var actual = cfg.guardar_en != "" ? cfg.guardar_en : escritorio ();
            var todas = carpetas_rutas ();
            var nombres = new string[] { "Desktop", "Documents" };
            for (int k = 0; k < 2; k++) {                // Desktop y Documents
                var ruta = todas[k];
                marca (m, nombres[k], destino == "carpeta" && ruta == actual, () => carpeta_elegida (ruta));
            }
            if (actual != todas[0] && actual != todas[1]) {      // la carpeta escogida con Other Location…, como «SS» en la Mac
                var r = actual;
                var base_ = Path.get_basename (actual.has_suffix ("/") && actual.length > 1 ? actual.substring (0, actual.length - 1) : actual);
                marca (m, base_ != "" ? base_ : actual, destino == "carpeta", () => carpeta_elegida (r));
            }
            if (!grabando) marca (m, "Clipboard", destino == "clipboard", () => poner_texto ("destino", "clipboard"));
            marca (m, "Mail", destino == "mail", () => poner_texto ("destino", "mail"));
            var mensajes = new Gtk.CheckMenuItem.with_label ("Messages");
            mensajes.set_sensitive (false);
            mensajes.set_draw_as_radio (false);
            m.append (mensajes);
            marca (m, grabando ? "QuickTime Player" : "Preview", destino == "preview", () => poner_texto ("destino", "preview"));
            var otra = new Gtk.MenuItem.with_label ("Other Location…");
            otra.activate.connect (() => otra_carpeta ());
            m.append (otra);
            m.append (new Gtk.SeparatorMenuItem ());
            titulo (m, "Timer");
            string[] t_texto = { "None", "5 Seconds", "10 Seconds" };
            int[] t_seg = { 0, 5, 10 };
            for (int k = 0; k < 3; k++) {
                var seg = t_seg[k];
                marca (m, t_texto[k], cfg.temporizador == seg, () => { cfg.temporizador = seg; cfg.guardar (); });
            }
            m.append (new Gtk.SeparatorMenuItem ());
            titulo (m, "Microphone");
            marca (m, "None", cfg.micro == "", () => poner_texto ("micro", ""));
            foreach (var fuente in micros ()) {
                var f = fuente;
                marca (m, f, cfg.micro == f, () => poner_texto ("micro", f));
            }
            m.append (new Gtk.SeparatorMenuItem ());
            titulo (m, "Options");
            var mini = new Gtk.CheckMenuItem.with_label ("Show Floating Thumbnail");
            mini.set_active (cfg.miniatura);
            mini.toggled.connect (() => { cfg.miniatura = mini.get_active (); cfg.guardar (); });
            m.append (mini);
            var recordar = new Gtk.CheckMenuItem.with_label ("Remember Last Selection");
            recordar.set_active (cfg.recordar);
            recordar.toggled.connect (() => { cfg.recordar = recordar.get_active (); cfg.guardar (); });
            m.append (recordar);
            m.show_all ();
            return m;
        }

        void poner_texto (string clave, string valor) {
            if (clave == "destino") cfg.destino = valor;
            else if (clave == "micro") cfg.micro = valor;
            cfg.guardar ();
        }

        void carpeta_elegida (string ruta) {
            cfg.destino = "carpeta";
            cfg.guardar_en = ruta;
            cfg.guardar ();
        }

        void otra_carpeta () {
            // El marco, la cámara y demás capas están a pantalla completa y por encima de todo: el diálogo quedaba
            // tapado, sin poder tocarlo, y la herramienta parecía colgada. Se sueltan antes y se vuelven a armar después.
            soltar_armado ();
            var d = new Gtk.FileChooserDialog ("Choose", this, Gtk.FileChooserAction.SELECT_FOLDER,
                                               "Cancel", Gtk.ResponseType.CANCEL, "Choose", Gtk.ResponseType.OK);
            d.set_keep_above (true);
            if (d.run () == Gtk.ResponseType.OK) carpeta_elegida (d.get_filename ());
            d.destroy ();
            opciones.set_popup (menu ());
            armar ();
        }

        // ── hacer la captura o la grabación ────────────────────────────────
        /** El botón Capture (o Record) hace la captura ya, con el modo escogido y el temporizador de Options. */
        void ejecutar () {
            var modo = cfg.modo;
            if (modo == "ventana") return;           // la ventana se elige con un clic, no con Capture
            int[]? dato = null;
            if (modo == "porcion" || modo == "grabar-porcion") {
                if (marco == null) return;
                rect = marco.get_rect ();
                dato = rect;
            }
            soltar_armado ();
            ocupada = true;
            hide ();
            con_temporizador (() => hacer (modo, dato, null));
        }

        void tras_elegir_ventana (string? wid) {
            selector = null;
            if (wid == null) return;
            ocupada = true;
            hide ();
            con_temporizador (() => hacer ("ventana", null, wid));
        }

        delegate void Despues ();

        void con_temporizador (owned Despues fn) {
            uint ms = (uint) (int.max (cfg.temporizador, 0) * 1000 + 250);
            Timeout.add (ms, () => { fn (); return false; });
        }

        string destino_real () {
            return (cfg.destino == "clipboard" && cfg.modo.has_prefix ("grabar")) ? "carpeta" : cfg.destino;
        }

        /** Dónde se escribe el archivo: la carpeta escogida, o una temporal si va al portapapeles, al correo o a un visor. */
        string carpeta () {
            if (destino_real () != "carpeta") return temporales ();
            return cfg.guardar_en != "" ? cfg.guardar_en : escritorio ();
        }

        void hacer (string modo, int[]? dato, string? wid) {
            var dir = carpeta ();
            if (modo.has_prefix ("grabar")) {
                grabar (dir, dato);
                return;
            }
            var ruta = nombre_libre (dir, "Screen Shot", "png");
            try {
                if (modo == "ventana") {
                    if (!capturar_ventana (wid, ruta)) con_sombra (ruta);     // sin sombra propia: se le pone la de la Mac
                } else {
                    capturar_pantalla (ruta, dato);
                }
            } catch (Error e) {
                stderr.printf ("No se pudo capturar: %s\n", e.message);
                destroy ();
                return;
            }
            entregar (destino_real (), ruta);
            bool borrar = destino_real () == "clipboard";      // al portapapeles no se deja archivo
            if (cfg.miniatura) {
                miniatura (ruta, borrar);
            } else {
                if (borrar) FileUtils.remove (ruta);
                destroy ();
            }
        }

        void capturar_pantalla (string ruta, int[]? dato) throws Error {
            var scr = get_screen ();
            int x = 0, y = 0, w = scr.get_width (), h = scr.get_height ();
            if (dato != null) {
                x = dato[0]; y = dato[1]; w = dato[2]; h = dato[3];
            }
            var pb = Gdk.pixbuf_get_from_window (scr.get_root_window (), x, y, w, h);
            if (pb == null) throw new IOError.FAILED ("no se pudo leer la pantalla");
            pb.save (ruta, "png");
        }

        /**
         * Guarda la ventana con su canal alfa. Si la ventana trae marco del gestor, se toma el marco; si dibuja su propia
         * sombra con _GTK_FRAME_EXTENTS, se recorta. Devuelve true si la propia ventana ya trae una sombra o margen
         * transparente en los bordes (entonces no se le añade la de la Mac).
         */
        bool capturar_ventana (string wid, string ruta) throws Error {
            var display = Gdk.Display.get_default () as Gdk.X11.Display;
            var cliente = new Gdk.X11.Window.foreign_for_display (display, (X.Window) ulong.parse (wid));
            Gdk.Window arriba = cliente;
            int ox = 0, oy = 0;
            var padre = cliente.get_parent ();
            if (padre != null && padre.get_window_type () != Gdk.WindowType.ROOT) {
                arriba = padre;
                cliente.get_position (out ox, out oy);
            }
            var ext = extensiones_gtk (cliente);
            Gdk.Pixbuf? pb;
            if (ext[0] != 0 || ext[1] != 0 || ext[2] != 0 || ext[3] != 0) {
                int x = ox + ext[0], y = oy + ext[2];
                int ancho = cliente.get_width () - ext[0] - ext[1], alto = cliente.get_height () - ext[2] - ext[3];
                arriba = (ox != 0 || oy != 0) ? padre : cliente;
                pb = Gdk.pixbuf_get_from_window (arriba, x, y, ancho, alto);
            } else {
                pb = Gdk.pixbuf_get_from_window (arriba, 0, 0, arriba.get_width (), arriba.get_height ());
            }
            if (pb == null) throw new IOError.FAILED ("no se pudo leer la ventana");
            pb.save (ruta, "png");
            if (!pb.get_has_alpha ()) return false;
            int w = pb.get_width (), h = pb.get_height (), fila = pb.get_rowstride (), canales = pb.get_n_channels ();
            unowned uint8[] datos = pb.get_pixels ();
            int[,] centros = { { w / 2, 0 }, { w / 2, h - 1 }, { 0, h / 2 }, { w - 1, h / 2 } };
            for (int i = 0; i < 4; i++) {
                if (datos[centros[i, 1] * fila + centros[i, 0] * canales + 3] < 250) return true;
            }
            return false;
        }

        void miniatura (string ruta, bool borrar) {
            var w = new Gtk.Window (Gtk.WindowType.POPUP);
            var scr = w.get_screen ();
            if (scr.get_rgba_visual () != null) w.set_visual (scr.get_rgba_visual ());
            w.set_app_paintable (true);
            var caja = new Gtk.EventBox ();
            caja.name = "miniatura";
            try {
                var pb = new Gdk.Pixbuf.from_file_at_scale (ruta, 160, 100, true);
                caja.add (new Gtk.Image.from_pixbuf (pb));
            } catch (Error e) {
                caja.add (new Gtk.Label (Path.get_basename (ruta)));
            }
            bool terminada = false;
            Despues fin = () => {
                if (terminada) return;
                terminada = true;
                if (borrar) FileUtils.remove (ruta);
                w.destroy ();
                destroy ();         // la barra (oculta); al ser la última ventana, el programa sale
            };
            caja.button_press_event.connect (() => { abrir (ruta); fin (); return false; });
            w.add (caja);
            w.show_all ();
            w.move (scr.get_width () - w.get_allocated_width () - 20, scr.get_height () - w.get_allocated_height () - 40);
            Timeout.add (5000, () => { fin (); return false; });
        }

        void grabar (string dir, int[]? region) {
            var ruta = nombre_libre (dir, "Screen Recording", "mov");
            var scr = get_screen ();
            int x = 0, y = 0, w = scr.get_width (), h = scr.get_height ();
            if (region != null) {
                x = region[0]; y = region[1]; w = region[2]; h = region[3];
            }
            w -= w % 2;
            h -= h % 2;
            var pantalla = Environment.get_variable ("DISPLAY") ?? ":0";
            string[] cmd = { "ffmpeg", "-y", "-loglevel", "error", "-f", "x11grab", "-framerate", "30",
                             "-video_size", "%dx%d".printf (w, h), "-i", "%s+%d,%d".printf (pantalla, x, y) };
            if (cfg.micro != "") {
                cmd += "-f"; cmd += "pulse"; cmd += "-i"; cmd += cfg.micro;
            }
            cmd += "-c:v"; cmd += "libx264"; cmd += "-preset"; cmd += "ultrafast"; cmd += "-pix_fmt"; cmd += "yuv420p";
            if (cfg.micro != "") {
                cmd += "-c:a"; cmd += "aac";
            }
            cmd += ruta;
            try {
                grabacion = new Subprocess.newv (cmd, SubprocessFlags.STDIN_PIPE);
            } catch (Error e) {
                stderr.printf ("No se pudo grabar: %s\n", e.message);
                destroy ();
                return;
            }
            pildora (ruta);
        }

        /** El botón de parar, abajo al centro (en la Mac es un ícono de la barra de menú). */
        void pildora (string ruta) {
            var w = new Gtk.Window (Gtk.WindowType.POPUP);
            var scr = w.get_screen ();
            if (scr.get_rgba_visual () != null) w.set_visual (scr.get_rgba_visual ());
            w.set_app_paintable (true);
            var b = new Gtk.Button.with_label ("■  Stop Recording");
            b.name = "accion";
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.name = "pildora";
            caja.set_margin_top (6); caja.set_margin_bottom (6); caja.set_margin_start (6); caja.set_margin_end (6);
            caja.pack_start (b, true, true, 4);
            w.add (caja);
            w.show_all ();
            w.move ((scr.get_width () - w.get_allocated_width ()) / 2, scr.get_height () - 90);
            b.clicked.connect (() => parar (w, ruta));
        }

        void parar (Gtk.Window w, string ruta) {
            var g = grabacion;
            grabacion = null;
            if (g == null) return;
            Despues terminar = () => {
                w.destroy ();
                if (destino_real () == "preview" || destino_real () == "mail") {
                    entregar (destino_real (), ruta);        // QuickTime Player ↔ el reproductor predeterminado
                }
                destroy ();
            };
            try {
                g.get_stdin_pipe ().write ("q".data);
                g.get_stdin_pipe ().flush ();
            } catch (Error e) {
                g.send_signal (Posix.Signal.INT);
            }
            uint corte = Timeout.add (10000, () => { g.force_exit (); return false; });
            g.wait_async.begin (null, (obj, res) => {
                try {
                    g.wait_async.end (res);
                } catch (Error e) {
                }
                Source.remove (corte);
                terminar ();
            });
        }
    }
}
