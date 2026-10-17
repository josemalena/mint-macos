/*
 * mac-gatekeeper: la confirmación de Catalina al abrir una app bajada de Internet, para las AppImages de /Applications.
 *     mac-gatekeeper --app NOMBRE --ruta RUTA [--origen URL] [--icono RUTA]
 * Sale 0 si se pulsa Open y 1 si se pulsa Cancel, ⎋ o se cierra la ventana (2 si faltan argumentos). Cancel es el botón
 * por defecto: lo que abre una app que corre sin aislamiento no se confirma con un ⏎ distraído.
 * No hay captura de Catalina de esta ventana (pedida en pantallas-con-captura-pendientes.md): la forma es la del aviso del
 * invitado (ícono a la izquierda, texto en negrita y dos botones), con el escudo de advertencia sobre el ícono de la app.
 */
namespace Gatekeeper {

    string? opcion_app = null;
    string? opcion_ruta = null;
    string? opcion_origen = null;
    string? opcion_icono = null;

    const OptionEntry[] OPCIONES = {
        { "app", 0, 0, OptionArg.STRING, ref opcion_app, "Nombre de la app", "NOMBRE" },
        { "ruta", 0, 0, OptionArg.STRING, ref opcion_ruta, "Ruta del archivo que se abre", "RUTA" },
        { "origen", 0, 0, OptionArg.STRING, ref opcion_origen, "De dónde se bajó (URL)", "URL" },
        { "icono", 0, 0, OptionArg.STRING, ref opcion_icono, "Ícono de la app (ruta)", "RUTA" },
        { null }
    };

    const string CSS = """
.mac-gk-titulo { font-family: ".SF NS"; font-weight: bold; font-size: 13px; color: #dedfdf; }
.mac-gk-texto { font-family: ".SF NS"; font-size: 11px; color: #dedfdf; }
""";

    /** El host de una URL, o null si no hay origen o no se entiende. */
    public string? host_de (string? origen) {
        if (origen == null || origen.strip () == "") {
            return null;
        }
        try {
            var uri = Uri.parse (origen.strip (), UriFlags.PARSE_RELAXED);
            string? h = uri.get_host ();
            return (h != null && h != "") ? h : null;
        } catch (Error e) {
            return null;
        }
    }

    public class Alerta : MacOS.Alerta {
        const int ANCHO_G = 442;
        const int ALTO_G = 176;
        const int FRANJA_G = 24;
        const int LADO_ICONO = 64;

        Gdk.Pixbuf? icono = null;

        public Alerta (string nombre, string? origen, string? ruta_icono) {
            base (ANCHO_G, ALTO_G, FRANJA_G);
            icono = cargar_icono (ruta_icono);

            var dibujo = new Gtk.DrawingArea ();
            dibujo.set_size_request (LADO_ICONO, LADO_ICONO);
            dibujo.draw.connect ((cr) => {
                if (icono != null) {
                    Gdk.cairo_set_source_pixbuf (cr, icono, 0, 0);
                    cr.paint ();
                }
                // El escudo de advertencia, a la mitad, en la esquina de abajo a la derecha.
                cr.save ();
                cr.translate (LADO_ICONO - 32, LADO_ICONO - 32);
                cr.scale (0.55, 0.55);
                MacOS.dibujar_aviso (cr);
                cr.restore ();
                return false;
            });
            caja.put (dibujo, 20, FRANJA_G + 20);

            int ancho_texto = ANCHO_G - 20 - LADO_ICONO - 18 - 20;
            string corto = nombre.char_count () > 48 ? nombre.substring (0, nombre.index_of_nth_char (47)) + "…" : nombre;
            var titulo = new Gtk.Label ("“%s” is an app downloaded from the Internet. Are you sure you want to open it?".printf (corto));
            titulo.get_style_context ().add_class ("mac-gk-titulo");
            titulo.xalign = 0.0f;
            titulo.yalign = 0.0f;
            titulo.wrap = true;
            titulo.max_width_chars = 38;
            titulo.set_size_request (ancho_texto, -1);
            caja.put (titulo, 20 + LADO_ICONO + 18, FRANJA_G + 20);

            string? host = host_de (origen);
            var texto = new Gtk.Label (host != null ? "It was downloaded from %s.".printf (host) : "Its origin is unknown.");
            texto.get_style_context ().add_class ("mac-gk-texto");
            texto.xalign = 0.0f;
            texto.yalign = 0.0f;
            texto.wrap = true;
            texto.max_width_chars = 40;
            texto.set_size_request (ancho_texto, -1);
            caja.put (texto, 20 + LADO_ICONO + 18, FRANJA_G + 20 + 58);

            var cancelar = new Gtk.Button.with_label ("Cancel");
            cancelar.get_style_context ().add_class ("mac-boton-inv");
            cancelar.get_style_context ().add_class ("mac-boton-pordefecto");
            cancelar.set_size_request (71, 21);
            cancelar.clicked.connect (() => terminar (CANCELAR));
            var abrir = new Gtk.Button.with_label ("Open");
            abrir.get_style_context ().add_class ("mac-boton-inv");
            abrir.set_size_request (71, 21);
            abrir.clicked.connect (() => terminar (ACEPTAR));
            var fila = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            fila.set_size_request (ANCHO_G - 16, 21);
            fila.pack_end (abrir, false, false, 0);
            fila.pack_end (cancelar, false, false, 0);
            caja.put (fila, 0, ALTO_G - 21 - 20);
            show_all ();
            cancelar.grab_focus ();
        }

        // ⏎ es Cancel y ⎋ también.
        protected override bool al_teclear (Gdk.EventKey e) {
            if (e.keyval == Gdk.Key.Return || e.keyval == Gdk.Key.KP_Enter) {
                terminar (CANCELAR);
                return true;
            }
            return base.al_teclear (e);
        }

        static Gdk.Pixbuf? cargar_icono (string? ruta) {
            try {
                if (ruta != null && ruta != "" && FileUtils.test (ruta, FileTest.EXISTS)) {
                    return new Gdk.Pixbuf.from_file_at_size (ruta, LADO_ICONO, LADO_ICONO);
                }
                return Gtk.IconTheme.get_default ().load_icon ("application-x-executable", LADO_ICONO, Gtk.IconLookupFlags.FORCE_SIZE);
            } catch (Error e) {
                return null;
            }
        }
    }
}

int main (string[] args_in) {
    unowned string[] args = args_in;
    try {
        var ctx = new OptionContext ("");
        ctx.add_main_entries (Gatekeeper.OPCIONES, null);
        ctx.add_group (Gtk.get_option_group (true));
        ctx.parse (ref args);
    } catch (Error e) {
        stderr.printf ("mac-gatekeeper: %s\n", e.message);
        return 2;
    }
    if (Gatekeeper.opcion_app == null || Gatekeeper.opcion_ruta == null) {
        stderr.printf ("uso: mac-gatekeeper --app NOMBRE --ruta RUTA [--origen URL] [--icono RUTA]\n");
        return 2;
    }
    MacOS.aplicar_estilo_invitado ();
    MacOS.aplicar_css (Gatekeeper.CSS);
    var alerta = new Gatekeeper.Alerta (Gatekeeper.opcion_app, Gatekeeper.opcion_origen, Gatekeeper.opcion_icono);
    return alerta.ejecutar () == MacOS.Alerta.ACEPTAR ? 0 : 1;
}
