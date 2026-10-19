/*
 * Apple ID: el panel y la hoja de Sign In, sobre el servicio org.mintmacos.AppleID1 (rust/appleid/DBUS.md). El servicio hace lo
 * pesado (rclone, CalDAV, el llavero, Thunderbird); aquí solo se pide y se enseña. Una sola cuenta para dos cosas: iCloud Drive
 * (la contraseña del Apple ID y el código de 2FA) y Mail y Calendar (una contraseña de app).
 *
 * Las contraseñas y el código pasan del campo al servicio por D-Bus y no se guardan aquí: el campo se vacía en cuanto se manda.
 * Las llamadas pueden tardar un par de minutos (rclone y la red), así que todas son async y la hoja enseña «Connecting…».
 */
namespace Preferencias {

    public class EstadoAppleID : Object {
        public string apple_id = "";
        public bool icloud_con_sesion = false;
        public bool icloud_montado = false;
        public bool mail_configurado = false;
    }

    public class RespuestaAppleID : Object {
        public string resultado = "error";     // ok | necesita_codigo | error
        public string mensaje = "";
        public int calendarios = 0;
    }

    public delegate void AvisoAppleID ();

    public class AppleID : Object {
        const string NOMBRE = "org.mintmacos.AppleID1";
        const string RUTA = "/org/mintmacos/AppleID1";
        // IniciarSesion, EnviarCodigo y ConfigurarMail esperan a rclone y a la red.
        const int PLAZO_MS = 240000;

        static async Variant? llamar (string metodo, Variant? args, int plazo) throws GLib.Error {
            var bus = yield Bus.get (BusType.SESSION);
            return yield bus.call (NOMBRE, RUTA, NOMBRE, metodo, args, null, DBusCallFlags.NONE, plazo, null);
        }

        static string texto (VariantDict d, string clave) {
            var v = d.lookup_value (clave, VariantType.STRING);
            return v != null ? v.get_string () : "";
        }

        static bool booleano (VariantDict d, string clave) {
            var v = d.lookup_value (clave, VariantType.BOOLEAN);
            return v != null && v.get_boolean ();
        }

        /** Estado(); null si el servicio no contesta. (Llamarlo activa el servicio.) */
        public static async EstadoAppleID? estado () {
            try {
                var r = yield llamar ("Estado", null, 8000);
                var d = new VariantDict (r.get_child_value (0));
                var e = new EstadoAppleID ();
                e.apple_id = texto (d, "apple_id");
                e.icloud_con_sesion = booleano (d, "icloud_con_sesion");
                e.icloud_montado = booleano (d, "icloud_montado");
                e.mail_configurado = booleano (d, "mail_configurado");
                return e;
            } catch (GLib.Error e) {
                return null;
            }
        }

        static async RespuestaAppleID accion (string metodo, Variant args) {
            var res = new RespuestaAppleID ();
            try {
                var r = yield llamar (metodo, args, PLAZO_MS);
                var d = new VariantDict (r.get_child_value (0));
                res.resultado = texto (d, "resultado");
                res.mensaje = texto (d, "mensaje");
                var c = d.lookup_value ("cuantos_calendarios", VariantType.INT32);
                if (c != null) res.calendarios = c.get_int32 ();
            } catch (GLib.Error e) {
                res.resultado = "error";
                res.mensaje = "The Apple ID service is not available on this computer.";
            }
            if (res.resultado == "") res.resultado = "error";
            return res;
        }

        public static async RespuestaAppleID iniciar_sesion (string apple_id, string clave) {
            return yield accion ("IniciarSesion", new Variant ("(ss)", apple_id, clave));
        }

        public static async RespuestaAppleID enviar_codigo (string codigo) {
            return yield accion ("EnviarCodigo", new Variant ("(s)", codigo));
        }

        public static async RespuestaAppleID configurar_mail (string apple_id, string nombre, string clave_app) {
            return yield accion ("ConfigurarMail", new Variant ("(sss)", apple_id, nombre, clave_app));
        }

        public static async void cerrar_sesion () {
            try {
                yield llamar ("CerrarSesion", null, PLAZO_MS);
            } catch (GLib.Error e) {
                warning ("AppleID1.CerrarSesion: %s", e.message);
            }
        }

        /** Avisa cuando un Sign In, un Mail o un Sign Out terminó (señal Cambio). */
        public static void vigilar (owned AvisoAppleID aviso) {
            try {
                var bus = Bus.get_sync (BusType.SESSION);
                bus.signal_subscribe (NOMBRE, NOMBRE, "Cambio", RUTA, null, DBusSignalFlags.NONE, () => aviso ());
            } catch (GLib.Error e) {
                warning ("AppleID1: %s", e.message);
            }
        }
    }

    /** El panel de Apple ID: cómo están iCloud Drive y Mail y Calendar. No sale en la cuadrícula: se abre desde la franja de arriba. */
    public class PanelAppleID : Panel {
        public PanelAppleID () {
            id = "com.apple.preferences.AppleIDPrefPane";
            nombre = "Apple ID";
            palabras = "apple id, icloud, mail, calendar, sign in";
            grupo = "oculto";
        }

        public override Gtk.Widget? construir () {
            var cuadro = new Gtk.Grid ();
            cuadro.column_spacing = 14;
            cuadro.row_spacing = 14;
            cuadro.get_style_context ().add_class ("mp-propio");
            cuadro.halign = Gtk.Align.CENTER;
            margenes (cuadro, 22, 22, 30, 30);
            var e = ventana != null ? ventana.estado_apple : null;
            bool con_cuenta = e != null && e.apple_id != "";

            if (con_cuenta) {
                fila (cuadro, 0, "Apple ID:", e.apple_id, boton ("Sign Out…", () => ventana.cerrar_sesion_apple_id ()));
                fila (cuadro, 1, "iCloud Drive:", e.icloud_montado ? "On — appears in your home folder as iCloud Drive"
                                                                  : "Signed in, but iCloud Drive is not mounted.");
                fila (cuadro, 2, "Mail & Calendar:",
                      e.mail_configurado ? "Set up in Thunderbird" : "Not set up yet. It needs an app-specific password.",
                      boton (e.mail_configurado ? "Update…" : "Set Up…", () => ventana.hoja_apple_id (true)));
            } else {
                fila (cuadro, 0, "Apple ID:", "Not signed in", boton ("Sign In…", () => ventana.hoja_apple_id (false)));
                fila (cuadro, 1, "iCloud Drive:", "Off. Sign in to use your iCloud files.");
                fila (cuadro, 2, "Mail & Calendar:", "Sign in first.");
            }
            cuadro.show_all ();
            return cuadro;
        }

        delegate void Accion ();

        static Gtk.Widget boton (string texto, owned Accion accion) {
            var b = new Gtk.Button.with_label (texto);
            b.valign = Gtk.Align.CENTER;
            b.clicked.connect (() => accion ());
            return b;
        }

        static void fila (Gtk.Grid g, int n, string etiqueta, string estado, Gtk.Widget? accion = null) {
            g.attach (etiqueta_fila (etiqueta), 0, n, 1, 1);
            var l = new Gtk.Label (estado);
            l.xalign = 0;
            l.set_line_wrap (true);
            l.set_max_width_chars (34);
            g.attach (l, 1, n, 1, 1);
            if (accion != null) g.attach (accion, 2, n, 1, 1);
        }
    }

    /** Sign In como la hoja de Catalina, en pasos: la cuenta, el código de verificación, Mail y Calendar, y el final. */
    public class HojaAppleID : Gtk.Dialog {
        string paso = "cuenta";
        string apple_id = "";
        Gtk.Label titulo;
        Gtk.Label texto;
        Gtk.Label aviso;
        Gtk.Box campos;
        Gtk.Button siguiente;
        Gtk.Button cancelar;
        Gtk.Entry? e_id = null;
        Gtk.Entry? e_clave = null;
        Gtk.Entry? e_codigo = null;
        Gtk.Entry? e_app = null;
        /** Algo cambió en la cuenta: la ventana vuelve a pedir el estado. */
        public signal void terminado ();

        public HojaAppleID (Gtk.Window padre, string? apple_id_conocido) {
            Object (transient_for: padre, modal: true, destroy_with_parent: true, title: "Apple ID");
            set_decorated (false);
            set_resizable (false);
            set_default_size (420, -1);
            get_style_context ().add_class ("mp-hoja");
            var caja = get_content_area () as Gtk.Box;
            caja.set_spacing (10);
            caja.set_border_width (24);
            titulo = new Gtk.Label ("");
            titulo.get_style_context ().add_class ("mp-hoja-titulo");
            texto = new Gtk.Label ("");
            texto.set_line_wrap (true);
            texto.set_max_width_chars (44);
            texto.justify = Gtk.Justification.CENTER;
            texto.get_style_context ().add_class ("mp-hoja-texto");
            caja.pack_start (titulo, false, false, 0);
            caja.pack_start (texto, false, false, 0);
            campos = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            caja.pack_start (campos, false, false, 6);
            aviso = new Gtk.Label ("");
            aviso.set_line_wrap (true);
            aviso.set_max_width_chars (44);
            aviso.get_style_context ().add_class ("mp-hoja-error");
            caja.pack_start (aviso, false, false, 0);
            cancelar = add_button ("Cancel", Gtk.ResponseType.CANCEL) as Gtk.Button;
            siguiente = add_button ("Next", Gtk.ResponseType.OK) as Gtk.Button;
            siguiente.get_style_context ().add_class ("suggested-action");
            set_default_response (Gtk.ResponseType.OK);
            response.connect (al_responder);
            if (apple_id_conocido != null) this.apple_id = apple_id_conocido;
            paso_cuenta ();
            show_all ();
        }

        /** Para «Set Up…» del panel: con la sesión ya hecha, directo a Mail y Calendar. */
        public void ir_a_mail () {
            paso_mail ();
        }

        void limpiar () {
            foreach (var c in campos.get_children ()) campos.remove (c);
            aviso.set_text ("");
        }

        Gtk.Entry campo (string pista, bool secreto, string inicial = "") {
            var e = new Gtk.Entry ();
            e.set_placeholder_text (pista);
            e.set_visibility (!secreto);
            e.set_text (inicial);
            e.set_activates_default (true);
            campos.pack_start (e, false, false, 0);
            e.show ();
            return e;
        }

        void ocupado (bool si) {
            siguiente.set_sensitive (!si);
            campos.set_sensitive (!si);
            aviso.set_text (si ? "Connecting…" : "");
        }

        void paso_cuenta () {
            paso = "cuenta";
            limpiar ();
            titulo.set_text ("Sign in with your Apple ID");
            texto.set_text ("Connects iCloud Drive. Mail and Calendar come next with an app-specific password.");
            e_id = campo ("Apple ID", false, apple_id);
            e_clave = campo ("Password", true);
            siguiente.set_label ("Next");
            e_id.grab_focus ();
        }

        void paso_codigo () {
            paso = "codigo";
            limpiar ();
            titulo.set_text ("Verification Code");
            texto.set_text ("Enter the six-digit code that was sent to your other Apple devices.");
            e_codigo = campo ("000000", false);
            e_codigo.set_max_length (8);
            siguiente.set_label ("Verify");
            e_codigo.grab_focus ();
        }

        void paso_mail () {
            paso = "mail";
            limpiar ();
            titulo.set_text ("Mail and Calendar");
            texto.set_text ("iCloud Drive is connected. For Mail and Calendar in Thunderbird, Apple requires an app-specific password: "
                            + "create one at appleid.apple.com → Sign-In and Security → App-Specific Passwords.");
            var abrir = new Gtk.LinkButton.with_label ("https://appleid.apple.com/account/manage", "Open appleid.apple.com");
            campos.pack_start (abrir, false, false, 0);
            abrir.show ();
            e_app = campo ("App-specific password (xxxx-xxxx-xxxx-xxxx)", true);
            siguiente.set_label ("Set Up");
            cancelar.set_label ("Not Now");
            e_app.grab_focus ();
        }

        void paso_fin (int? calendarios) {
            paso = "fin";
            limpiar ();
            titulo.set_text ("You’re all set");
            var t = "iCloud Drive is mounted.";
            if (calendarios != null) {
                t += " Mail and %d calendar(s) are set up: open Thunderbird and, if it asks, choose the saved password.".printf (calendarios);
            }
            texto.set_text (t);
            siguiente.set_label ("Done");
            cancelar.hide ();
        }

        void al_responder (int r) {
            if (r != Gtk.ResponseType.OK) {
                if (paso == "mail") {
                    paso_fin (null);
                    terminado ();
                    return;
                }
                destroy ();
                return;
            }
            if (paso == "cuenta") {
                apple_id = e_id.get_text ().strip ();
                var clave = e_clave.get_text ();
                if (apple_id == "" || clave == "") {
                    aviso.set_text ("Enter your Apple ID and password.");
                    return;
                }
                e_clave.set_text ("");
                ocupado (true);
                AppleID.iniciar_sesion.begin (apple_id, clave, (o, res) => despues_de_clave (AppleID.iniciar_sesion.end (res)));
            } else if (paso == "codigo") {
                var cod = e_codigo.get_text ().strip ();
                if (cod == "") return;
                e_codigo.set_text ("");
                ocupado (true);
                AppleID.enviar_codigo.begin (cod, (o, res) => despues_del_codigo (AppleID.enviar_codigo.end (res)));
            } else if (paso == "mail") {
                var app = e_app.get_text ().strip ();
                if (app == "") {
                    aviso.set_text ("Paste the app-specific password.");
                    return;
                }
                e_app.set_text ("");
                var nombre = Environment.get_real_name ();
                if (nombre == "" || nombre == "Unknown") nombre = apple_id;
                ocupado (true);
                AppleID.configurar_mail.begin (apple_id, nombre, app, (o, res) => despues_de_mail (AppleID.configurar_mail.end (res)));
            } else {
                destroy ();
            }
        }

        void despues_de_clave (RespuestaAppleID r) {
            ocupado (false);
            if (r.resultado == "necesita_codigo") {
                paso_codigo ();
            } else if (r.resultado == "ok") {
                terminado ();
                paso_mail ();
            } else {
                aviso.set_text (r.mensaje != "" ? r.mensaje : "Apple did not accept the sign in.");
            }
        }

        void despues_del_codigo (RespuestaAppleID r) {
            ocupado (false);
            if (r.resultado == "ok") {
                terminado ();
                paso_mail ();
            } else if (r.resultado == "necesita_codigo") {
                aviso.set_text ("Apple asked for another code.");
            } else {
                aviso.set_text (r.mensaje != "" ? r.mensaje : "The code was not accepted.");
            }
        }

        void despues_de_mail (RespuestaAppleID r) {
            ocupado (false);
            if (r.resultado == "ok") {
                terminado ();
                paso_fin (r.calendarios);
            } else {
                aviso.set_text (r.mensaje != "" ? r.mensaje : "Mail and Calendar could not be set up.");
            }
        }
    }
}
