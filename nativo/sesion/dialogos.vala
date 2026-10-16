/*
 * Los diálogos de sesión de Catalina: Restart, Shut Down y Log Out con su cuenta regresiva (captura 1.32.56 PM, 416 × 196),
 * y el aviso del invitado al cerrar sesión (captura 1.32.11 PM, 442 × 158). Mismas medidas y mismos textos que la versión
 * en Python (applets/applemenu@macos/applemenu.py), que es contra lo que se compara.
 */
namespace Sesion {

    public class AlertaConfirmar : MacOS.Alerta {
        const int ANCHO_C = 416;
        const int ALTO_C = 196;
        const int FRANJA_C = 21;

        public Gtk.CheckButton reabrir;
        private string modo;
        private Preset preset;
        private int restan;
        private uint temporizador = 0;
        private Gtk.Label cuenta;

        public AlertaConfirmar (string modo, int segundos, bool reabrir_por_defecto) {
            base (ANCHO_C, ALTO_C, FRANJA_C);
            this.modo = modo;
            this.preset = preset_de (modo);
            this.restan = int.max (1, segundos);

            var icono = new Gtk.DrawingArea ();
            icono.set_size_request (64, 64);
            icono.draw.connect ((cr) => { MacOS.dibujar_icono (cr, this.modo); return false; });
            caja.put (icono, 20, FRANJA_C + 21);

            int ancho_texto = ANCHO_C - 91 - 20;
            var derecha = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            derecha.set_size_request (ancho_texto, -1);
            caja.put (derecha, 91, FRANJA_C + 20);

            var titulo = new Gtk.Label (preset.titulo.replace ("\n", " "));
            titulo.get_style_context ().add_class ("mac-titulo");
            titulo.xalign = 0.0f;
            titulo.wrap = true;
            titulo.max_width_chars = 36;     // sin tope, el ancho «natural» (todo el texto en una línea) ensancha la ventana
            titulo.set_size_request (ancho_texto, -1);
            derecha.pack_start (titulo, false, false, 0);

            cuenta = new Gtk.Label ("");
            cuenta.get_style_context ().add_class ("mac-cuenta");
            cuenta.xalign = 0.0f;
            cuenta.wrap = true;
            cuenta.max_width_chars = 46;
            cuenta.set_size_request (ancho_texto, -1);
            cuenta.margin_top = 8;
            derecha.pack_start (cuenta, false, false, 0);

            reabrir = new Gtk.CheckButton.with_label ("Reopen windows when logging back in");
            reabrir.get_style_context ().add_class ("mac-casilla");
            reabrir.active = reabrir_por_defecto;
            reabrir.can_focus = false;
            reabrir.margin_top = 6;
            derecha.pack_start (reabrir, false, false, 0);

            var cancelar = new Gtk.Button.with_label ("Cancel");
            cancelar.get_style_context ().add_class ("mac-boton");
            cancelar.set_size_request (70, 19);
            cancelar.clicked.connect (() => terminar (CANCELAR));
            var accion = new Gtk.Button.with_label (preset.accion);
            accion.get_style_context ().add_class ("mac-boton");
            accion.get_style_context ().add_class ("mac-boton-accion");
            accion.set_size_request (70, 19);
            accion.clicked.connect (() => terminar (ACEPTAR));
            // Pegados a la derecha, a 16 px del borde interior (con el borde quedan los 20 de la Mac), 14 entre ellos.
            // Miden 70 como mínimo y crecen con el texto, como «Shut Down» en la Mac.
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 14);
            fila.set_size_request (ANCHO_C - 16, 19);
            fila.pack_end (accion, false, false, 0);
            fila.pack_end (cancelar, false, false, 0);
            caja.put (fila, 0, ALTO_C - 20 - 19);

            destroy.connect (() => {
                if (temporizador != 0) {
                    Source.remove (temporizador);
                    temporizador = 0;
                }
            });
            temporizador = Timeout.add (1000, al_segundo);
            actualizar_cuenta ();
            show_all ();
            accion.grab_focus ();
        }

        // ⏎ hace la acción, ⎋ cancela: como en la Mac.
        protected override bool al_teclear (Gdk.EventKey e) {
            if (e.keyval == Gdk.Key.Return || e.keyval == Gdk.Key.KP_Enter) {
                terminar (ACEPTAR);
                return true;
            }
            return base.al_teclear (e);
        }

        private void actualizar_cuenta () {
            cuenta.label = preset.cuenta.replace ("\n", " ").replace ("{n}", restan.to_string ());
        }

        private bool al_segundo () {
            restan--;
            if (restan <= 0) {
                temporizador = 0;
                terminar (ACEPTAR);
                return false;
            }
            actualizar_cuenta ();
            return true;
        }
    }

    public class AlertaInvitado : MacOS.Alerta {
        const int ANCHO_I = 442;
        const int ALTO_I = 158;
        const int FRANJA_I = 24;
        const string TITULO = "If you log out, your files will be deleted.";
        const string TEXTO = "You are logged in as a guest user. Logging out deletes all files and information " +
                             "in the guest user home folder. These files cannot be recovered.";

        public AlertaInvitado () {
            base (ANCHO_I, ALTO_I, FRANJA_I);

            var icono = new Gtk.DrawingArea ();
            icono.set_size_request (58, 58);
            icono.draw.connect ((cr) => { MacOS.dibujar_aviso (cr); return false; });
            caja.put (icono, 22, FRANJA_I + 19);

            int ancho_texto = ANCHO_I - 92 - 20;
            var titulo = new Gtk.Label (TITULO);
            titulo.get_style_context ().add_class ("mac-inv-titulo");
            titulo.xalign = 0.0f;
            titulo.set_size_request (ancho_texto, -1);
            caja.put (titulo, 92, FRANJA_I + 21);

            var texto = new Gtk.Label (TEXTO);
            texto.get_style_context ().add_class ("mac-inv-texto");
            texto.xalign = 0.0f;
            texto.yalign = 0.0f;
            texto.wrap = true;
            texto.max_width_chars = 36;
            texto.set_size_request (ancho_texto, -1);
            caja.put (texto, 92, FRANJA_I + 44);

            var cancelar = new Gtk.Button.with_label ("Cancel");
            cancelar.get_style_context ().add_class ("mac-boton-inv");
            cancelar.get_style_context ().add_class ("mac-boton-pordefecto");
            cancelar.set_size_request (71, 21);
            cancelar.clicked.connect (() => terminar (CANCELAR));
            var borrar = new Gtk.Button.with_label ("Delete Files & Log Out");
            borrar.get_style_context ().add_class ("mac-boton-inv");
            borrar.clicked.connect (() => terminar (ACEPTAR));
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            fila.set_size_request (ANCHO_I - 16, 21);
            fila.pack_end (borrar, false, false, 0);
            fila.pack_end (cancelar, false, false, 0);
            caja.put (fila, 0, ALTO_I - 21 - 20);
            show_all ();
            cancelar.grab_focus ();
        }

        // ⏎ es Cancel (lo destructivo no es el de por defecto) y ⎋ también.
        protected override bool al_teclear (Gdk.EventKey e) {
            if (e.keyval == Gdk.Key.Return || e.keyval == Gdk.Key.KP_Enter) {
                terminar (CANCELAR);
                return true;
            }
            return base.al_teclear (e);
        }
    }
}
