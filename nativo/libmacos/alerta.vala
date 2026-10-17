/*
 * La base de las alertas de Catalina: ventana sin marco, con sombra si hay compositor, caja de 1 px con esquinas de 5,
 * franja de arriba y un Gtk.Fixed donde cada pieza va en su píxel (el Fixed no pinta su propio CSS, por eso la caja).
 * Las medidas salen de las capturas (ver estilo.vala).
 */
namespace MacOS {

    public abstract class Alerta : Gtk.Window {
        public const int ACEPTAR = 1;
        public const int CANCELAR = 0;

        /** El resultado: ACEPTAR o CANCELAR. */
        public int respuesta { get; protected set; default = CANCELAR; }

        /** Donde se ponen las piezas (en píxeles, desde la esquina de la caja, sin la sombra). */
        protected Gtk.Fixed caja;
        protected int ancho;
        protected int alto;
        protected int franja;

        private MainLoop? bucle = null;

        protected Alerta (int ancho, int alto, int franja) {
            Object (title: "");
            this.ancho = ancho;
            this.alto = alto;
            this.franja = franja;

            get_style_context ().add_class ("mac-dialogo");
            decorated = false;
            resizable = false;
            set_keep_above (true);
            skip_taskbar_hint = true;
            skip_pager_hint = true;
            type_hint = Gdk.WindowTypeHint.DIALOG;
            window_position = Gtk.WindowPosition.CENTER;

            int margen = 0;
            var pantalla = get_screen ();
            var visual = pantalla.get_rgba_visual ();
            if (visual != null && pantalla.is_composited ()) {
                set_visual (visual);
                app_paintable = true;
                margen = SOMBRA;
            }
            set_default_size (ancho + 2 * margen, alto + 2 * margen);

            var fondo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            fondo.get_style_context ().add_class ("mac-caja");
            fondo.set_size_request (ancho, alto);
            fondo.margin_top = margen;
            fondo.margin_bottom = margen;
            fondo.margin_start = margen;
            fondo.margin_end = margen;
            caja = new Gtk.Fixed ();
            caja.set_size_request (ancho, alto);
            fondo.pack_start (caja, true, true, 0);
            add (fondo);

            var barra = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            barra.get_style_context ().add_class ("mac-franja");
            barra.set_size_request (ancho - 2, franja);
            caja.put (barra, 1, 1);

            key_press_event.connect (al_teclear);
            delete_event.connect (() => { terminar (CANCELAR); return true; });
        }

        /** ⏎ y ⎋: lo que haga cada alerta (por defecto ⎋ cancela). */
        protected virtual bool al_teclear (Gdk.EventKey e) {
            if (e.keyval == Gdk.Key.Escape) {
                terminar (CANCELAR);
                return true;
            }
            return false;
        }

        public void terminar (int resultado) {
            respuesta = resultado;
            if (bucle != null) {
                bucle.quit ();
            }
        }

        protected void al_frente () {
            Idle.add (() => {
                present_with_time (Gdk.CURRENT_TIME);
                var ventana = get_window ();
                if (ventana != null) {
                    ventana.focus (Gdk.CURRENT_TIME);
                }
                return false;
            });
        }

        /** Enseña la alerta y espera la respuesta. */
        public int ejecutar () {
            show_all ();
            al_frente ();
            bucle = new MainLoop ();
            bucle.run ();
            return respuesta;
        }
    }
}
